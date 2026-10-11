import AppKit
import UniformTypeIdentifiers

/// One open markdown file: in-memory text with silent debounced autosave.
/// Untitled documents (url == nil) are only written once the user picks a
/// location via the save panel.
@MainActor
final class OpenDocument: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var url: URL?
    @Published private(set) var text: String
    @Published private(set) var lastSavedText: String

    /// Called after the file changed on disk and was re-read; the document's
    /// view shows the new version.
    var onReload: (() -> Void)?

    private var saveTask: Task<Void, Never>?
    private var saveFailurePresented = false
    /// The file's modification date as this document last read or wrote it.
    private var diskDate: Date?
    private var conflictPresented = false

    init(url: URL, text: String) {
        self.url = url
        self.text = text
        self.lastSavedText = text
        self.diskDate = Self.modificationDate(url)
    }

    init() {
        self.url = nil
        self.text = ""
        self.lastSavedText = ""
    }

    var isDirty: Bool { text != lastSavedText }
    var isHTML: Bool { url.map(FolderScanner.isHTML) ?? false }
    var displayName: String { url?.lastPathComponent ?? "Untitled" }

    /// "path:12-14" followed by the passage as a quote, for pasting to an agent.
    /// The editor shows text without markup, so the lines are a best guess:
    /// the first source lines containing the passage's first and last line.
    func reference(to selection: String) -> String? {
        // The selection has a blank line between blocks and puts ordered-list
        // numbers on a line of their own.
        let lines = selection.replacing(#/(?m)^(\d+[.)])\n/#) { "\($0.1) " }
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let url, !lines.isEmpty else { return nil }
        var location = url.path
        let source = text.components(separatedBy: "\n").map(Self.plain)
        let quoted = lines.map { Self.plain(String($0)) }.filter { !$0.isEmpty }
        if let first = quoted.first, let last = quoted.last,
           let start = source.firstIndex(where: { $0.contains(first) }),
           let end = source[start...].firstIndex(where: { $0.contains(last) }) {
            location += start == end ? ":\(start + 1)" : ":\(start + 1)-\(end + 1)"
        }
        return ([location] + lines.map { "> \($0)" }).joined(separator: "\n")
    }

    /// "1,240 words · ≈ 1.7k tokens" for the window subtitle. Words skip code
    /// blocks (charts and diagrams show as visuals); tokens cover the whole file,
    /// as an agent reads it, at a rough four characters per token.
    static func stats(for text: String) -> String {
        let prose = text.replacing(#/(?ms)^```.*?^```/#, with: "")
        let words = prose.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }.count
        let tokens = text.count / 4
        let tokenText = tokens < 1000 ? tokens.formatted()
            : (Double(tokens) / 1000).formatted(.number.precision(.fractionLength(tokens < 10_000 ? 0...1 : 0...0))) + "k"
        return "\(words.formatted()) \(words == 1 ? "word" : "words") · ≈ \(tokenText) tokens"
    }

    /// A line as it reads in the editor: link targets and markup characters
    /// dropped, whitespace collapsed.
    private static func plain(_ line: String) -> String {
        line.replacing(#/\]\([^)]*\)/#, with: "")
            .filter { !"*_`~#>[]|\\".contains($0) }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Called on every editor change; arms the autosave debounce.
    func textChanged(_ newText: String) {
        text = newText
        guard url != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Write pending changes to disk now. No-op for untitled or clean documents.
    /// Returns false when a write failed and the document is still dirty —
    /// callers gating destructive actions (quit, window close) must check this.
    @discardableResult
    func flush() -> Bool {
        saveTask?.cancel()
        saveTask = nil
        guard let url, isDirty else { return true }
        // Never write over a file that changed or vanished since we last saw it:
        // an agent's edit would be lost, and a renamed file would come back.
        guard let onDisk = Self.modificationDate(url) else {
            return reportFailure(CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path]))
        }
        if onDisk != diskDate {
            syncWithDisk()
            return !isDirty
        }
        do {
            try write(to: url)
            saveFailurePresented = false
            return true
        } catch {
            return reportFailure(error)
        }
    }

    /// Picks up changes made to the file outside the app. Clean documents
    /// reload silently; with unsaved edits the user decides.
    func syncWithDisk() {
        guard let url, !conflictPresented,
              let onDisk = Self.modificationDate(url), onDisk != diskDate else { return }
        if isDirty {
            resolveConflict(url, modified: onDisk)
        } else {
            reload(url, modified: onDisk)
        }
    }

    /// First save of an untitled document, or fallback after a failed write.
    /// Returns true if the document was saved.
    @discardableResult
    func saveAs(defaultDirectory: URL?) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdown]
        panel.directoryURL = defaultDirectory ?? url?.deletingLastPathComponent()
        panel.nameFieldStringValue = url?.lastPathComponent ?? "Untitled.md"
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        do {
            try write(to: destination)
            url = destination
            return true
        } catch {
            presentSaveFailure(error)
            return false
        }
    }

    private func write(to url: URL) throws {
        // Atomic, so a crash can't truncate the file and agents never read half a save.
        // Resolve symlinks first, or the atomic rename would replace the link itself.
        let target = url.resolvingSymlinksInPath()
        try Data(text.utf8).write(to: target, options: .atomic)
        lastSavedText = text
        diskDate = Self.modificationDate(target)
    }

    private func reload(_ url: URL, modified: Date) {
        // .html files are rendered from disk by their viewer, whatever the encoding;
        // there's no text to keep.
        if !isHTML {
            guard let disk = try? String(contentsOf: url, encoding: .utf8) else {
                // Keep our text, and don't re-read (or re-ask about) this version every second.
                diskDate = modified
                Self.presentReadFailure(url)
                return
            }
            text = disk
            lastSavedText = disk
        }
        diskDate = modified
        onReload?()
    }

    private func resolveConflict(_ url: URL, modified: Date) {
        conflictPresented = true
        defer { conflictPresented = false }
        let alert = NSAlert()
        alert.messageText = "\(displayName) was changed outside the app"
        alert.informativeText = "You have changes that aren't saved yet. Do you want the version on disk, or keep yours?"
        alert.addButton(withTitle: "Use Disk Version")
        alert.addButton(withTitle: "Keep Mine")
        if alert.runModal() == .alertFirstButtonReturn {
            reload(url, modified: modified)
        } else {
            diskDate = modified
            flush()
        }
    }

    private func reportFailure(_ error: Error) -> Bool {
        // Alert once per failure streak — autosave retries every debounce tick.
        if !saveFailurePresented {
            saveFailurePresented = true
            presentSaveFailure(error)
        }
        return false
    }

    static func presentReadFailure(_ url: URL) {
        let alert = NSAlert()
        alert.messageText = "Couldn't read \(url.lastPathComponent)"
        alert.informativeText = "The file couldn't be read as UTF-8 text."
        alert.runModal()
    }

    private func presentSaveFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't save \(displayName)"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Save As…")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            saveAs(defaultDirectory: nil)
        }
    }

    private static func modificationDate(_ url: URL) -> Date? {
        let path = url.resolvingSymlinksInPath().path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
}
