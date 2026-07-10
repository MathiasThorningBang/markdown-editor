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

    private var saveTask: Task<Void, Never>?
    private var saveFailurePresented = false

    init(url: URL, text: String) {
        self.url = url
        self.text = text
        self.lastSavedText = text
    }

    init() {
        self.url = nil
        self.text = ""
        self.lastSavedText = ""
    }

    var isDirty: Bool { text != lastSavedText }
    var displayName: String { url?.lastPathComponent ?? "Uden titel" }

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
        do {
            try Data(text.utf8).write(to: url)
            lastSavedText = text
            saveFailurePresented = false
            return true
        } catch {
            // Alert once per failure streak — autosave retries every debounce tick.
            if !saveFailurePresented {
                saveFailurePresented = true
                presentSaveFailure(error)
            }
            return !isDirty
        }
    }

    /// First save of an untitled document, or fallback after a failed write.
    /// Returns true if the document was saved.
    @discardableResult
    func saveAs(defaultDirectory: URL?) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdown]
        panel.directoryURL = defaultDirectory ?? url?.deletingLastPathComponent()
        panel.nameFieldStringValue = url?.lastPathComponent ?? "Uden titel.md"
        guard panel.runModal() == .OK, let destination = panel.url else { return false }
        do {
            try Data(text.utf8).write(to: destination)
            url = destination
            lastSavedText = text
            return true
        } catch {
            presentSaveFailure(error)
            return false
        }
    }

    private func presentSaveFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Kunne ikke gemme \(displayName)"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Gem som…")
        alert.addButton(withTitle: "Annullér")
        if alert.runModal() == .alertFirstButtonReturn {
            saveAs(defaultDirectory: nil)
        }
    }
}
