import AppKit
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

    /// Indstillinger shown in the editor canvas instead of the active document.
    @Published var showSettings = false

    let editorPool = EditorPool()

    /// Transient confirmation shown by the main window (e.g. "Sti kopieret").
    @Published private(set) var toast: String?
    private var toastTask: Task<Void, Never>?

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
        guard let index = projects.firstIndex(where: { $0.folderURL == folder }) else { return }
        let removed = projects.remove(at: index)
        persistProjects()

        let closing = openDocs.filter { doc in
            guard let url = doc.url else { return false }
            return canonical(url.deletingLastPathComponent()) == removed.folderURL
        }
        closing.forEach { $0.flush() }
        openDocs.removeAll { doc in closing.contains { $0 === doc } }
        closing.forEach { editorPool.close($0.id) }
        if let active = activeDoc, closing.contains(where: { $0 === active }) {
            activeDoc = openDocs.last
            updateWindowChrome()
        }
    }

    /// Rescans project folders, publishing only if something actually changed —
    /// this runs on every window focus, and a wholesale array swap would make
    /// the sidebar visibly rebuild.
    func refreshFiles() {
        let rescanned = projects.map { Project(folderURL: $0.folderURL, files: FolderScanner.scan($0.folderURL)) }
        guard !rescanned.elementsEqual(projects, by: { $0.files == $1.files }) else { return }
        projects = rescanned
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
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            presentReadFailure(url)
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
        updateWindowChrome()
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
    /// drafts and documents whose last write failed.
    var dirtyDocs: [OpenDocument] {
        openDocs.filter(\.isDirty)
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
    }

    private func presentReadFailure(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Kunne ikke læse \(url.lastPathComponent)"
        alert.informativeText = "Filen kunne ikke læses som UTF-8-tekst."
        alert.runModal()
    }
}
