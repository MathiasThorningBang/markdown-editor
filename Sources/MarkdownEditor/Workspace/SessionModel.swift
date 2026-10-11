import AppKit
import Combine
import SwiftUI

struct Project: Identifiable {
    let folderURL: URL
    var files: [FileEntry]
    var id: URL { folderURL }
    var name: String { folderURL.lastPathComponent }
}

/// The main window's state: the persistent list of project folders, their
/// .md files, and the documents opened from them. Projects accumulate as
/// files/folders are opened and survive relaunches.
@MainActor
final class SessionModel: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var openDocs: [OpenDocument] = []
    @Published private(set) var activeDoc: OpenDocument?

    /// Settings shown in the editor canvas instead of the active document.
    @Published var showSettings = false

    let editorPool = EditorPool()

    /// Each open file keeps its web view for instant switching; past this many,
    /// the least recently used hidden ones are released. Text and autosave live
    /// in OpenDocument, so only the view and its undo history go.
    private static let liveEditorLimit = 8
    private var recentDocs: [OpenDocument] = []

    /// Transient confirmation shown by the main window (e.g. "Path copied").
    @Published private(set) var toast: String?
    private var toastTask: Task<Void, Never>?
    private var statsSubscription: AnyCancellable?

    func showToast(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    private static let projectsDefaultsKey = "projectFolders"

    weak var window: NSWindow? {
        didSet {
            // The sidebar replaces the tab bar — never let macOS tab the window.
            window?.tabbingMode = .disallowed
            updateWindowChrome()
        }
    }

    init() {
        var isDirectory: ObjCBool = false
        projects = (UserDefaults.standard.stringArray(forKey: Self.projectsDefaultsKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDirectory) && isDirectory.boolValue }
            .map { Project(folderURL: $0, files: FolderScanner.scan($0)) }
        persistProjects() // prune folders that no longer exist

        // Agents edit open files on disk: one cheap modification-date check per file per second.
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                openDocs.forEach { $0.syncWithDisk() }
            }
        }
    }

    func addProject(_ folder: URL) {
        let key = canonical(folder)
        guard !projects.contains(where: { $0.folderURL == key }) else { return }
        projects.insert(Project(folderURL: key, files: FolderScanner.scan(key)), at: 0)
        persistProjects()
    }

    /// Most-recently-opened project goes to the top. Called for opens from
    /// outside the app (Finder, ⌘O, drag) — sidebar clicks deliberately don't
    /// reorder, so groups stay put while you browse them.
    func bumpProject(_ folder: URL) {
        let key = canonical(folder)
        guard let index = projects.firstIndex(where: { $0.folderURL == key }), index != 0 else { return }
        projects.insert(projects.remove(at: index), at: 0)
        persistProjects()
    }

    /// Removes the group from the sidebar (files on disk are untouched) and
    /// closes its open documents.
    func removeProject(_ folder: URL) {
        guard projects.contains(where: { $0.folderURL == folder }) else { return }
        let closing = openDocs.filter { doc in
            guard let url = doc.url else { return false }
            return canonical(url.deletingLastPathComponent()) == folder
        }
        // A failed write leaves the text only in memory; keep the project instead of losing it.
        guard closing.map({ $0.flush() }).allSatisfy({ $0 }) else { return }
        projects.removeAll { $0.folderURL == folder }
        persistProjects()
        discard(closing)
    }

    /// Rescans project folders, publishing only if something actually changed —
    /// this runs on every window focus, and a wholesale array swap would make
    /// the sidebar visibly rebuild.
    func refreshFiles() {
        let rescanned = projects.map { Project(folderURL: $0.folderURL, files: FolderScanner.scan($0.folderURL)) }
        if !rescanned.elementsEqual(projects, by: { $0.files == $1.files }) {
            projects = rescanned
        }
        // Renamed or deleted outside the app: drop clean documents. A dirty one stays
        // open (flush won't recreate the old file) until it's saved elsewhere or closed.
        let gone = openDocs.filter { doc in
            guard let url = doc.url else { return false }
            return !doc.isDirty && !FileManager.default.fileExists(atPath: url.path)
        }
        if !gone.isEmpty { discard(gone) }
    }

    func document(for url: URL) -> OpenDocument? {
        let target = url.standardizedFileURL
        return openDocs.first { $0.url?.standardizedFileURL == target }
    }

    func select(_ url: URL) {
        addProject(url.deletingLastPathComponent())
        if let existing = document(for: url) {
            guard existing !== activeDoc else { return }
            activeDoc?.flush()
            activate(existing)
            return
        }
        guard let text = FolderScanner.isHTML(url) ? "" : (try? String(contentsOf: url, encoding: .utf8)) else {
            OpenDocument.presentReadFailure(url)
            return
        }
        activeDoc?.flush()
        let doc = OpenDocument(url: url, text: text)
        openDocs.append(doc)
        activate(doc)
    }

    func newDocument() {
        activeDoc?.flush()
        let doc = OpenDocument()
        openDocs.append(doc)
        activate(doc)
    }

    func activate(_ doc: OpenDocument) {
        activeDoc = doc
        showSettings = false
        recentDocs.removeAll { $0 === doc }
        recentDocs.append(doc)
        recentDocs.dropLast(Self.liveEditorLimit).forEach { editorPool.close($0.id) }
        updateWindowChrome()
    }

    /// ⌘W: closes Settings if shown, else the active document, else the window.
    func closeActive() {
        if showSettings {
            showSettings = false
            return
        }
        guard let doc = activeDoc else {
            window?.performClose(nil)
            return
        }
        doc.flush()
        guard !doc.isDirty || confirmDiscard([doc]) else { return }
        discard([doc])
    }

    /// ⌘S: untitled documents get the save panel, saved documents just flush
    /// ahead of the autosave debounce.
    func saveActive() {
        guard let doc = activeDoc else { return }
        if doc.url == nil {
            guard doc.saveAs(defaultDirectory: projects.first?.folderURL), let url = doc.url else { return }
            addProject(url.deletingLastPathComponent())
            refreshFiles()
            updateWindowChrome()
        } else {
            doc.flush()
        }
    }

    func flushAll() {
        openDocs.forEach { $0.flush() }
    }

    /// Documents that would lose content if dropped now: unsaved untitled
    /// drafts and documents whose last write failed or whose file vanished.
    var dirtyDocs: [OpenDocument] {
        openDocs.filter(\.isDirty)
    }

    /// Drops documents and their web views; the most recently used remaining
    /// document becomes active if the active one went. Callers flush first.
    private func discard(_ docs: [OpenDocument]) {
        let ids = Set(docs.map(\.id))
        openDocs.removeAll { ids.contains($0.id) }
        recentDocs.removeAll { ids.contains($0.id) }
        ids.forEach(editorPool.close)
        if let active = activeDoc, ids.contains(active.id) {
            activeDoc = recentDocs.last
            updateWindowChrome()
        }
    }

    /// Asks before dropping text that only exists in memory. True = go ahead.
    func confirmDiscard(_ docs: [OpenDocument]) -> Bool {
        let alert = NSAlert()
        alert.messageText = docs.count == 1
            ? "Do you want to save \(docs[0].displayName)?"
            : "Do you want to save \(docs.count) documents?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return docs.allSatisfy { doc in
                guard doc.saveAs(defaultDirectory: projects.first?.folderURL), let url = doc.url else { return false }
                addProject(url.deletingLastPathComponent())
                return true
            }
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func canonical(_ folder: URL) -> URL {
        folder.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func persistProjects() {
        UserDefaults.standard.set(projects.map(\.folderURL.path), forKey: Self.projectsDefaultsKey)
    }

    private func updateWindowChrome() {
        guard let window else { return }
        window.title = activeDoc?.displayName ?? "Markdown Editor"
        window.representedURL = activeDoc?.url
        // Word and token count under the title, live while the file changes.
        window.subtitle = ""
        statsSubscription = activeDoc.flatMap { doc in
            doc.isHTML ? nil : doc.$text.sink { [weak window] text in
                window?.subtitle = OpenDocument.stats(for: text)
            }
        }
    }
}
