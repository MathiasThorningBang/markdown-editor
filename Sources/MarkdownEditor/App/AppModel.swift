import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App-wide entry point: one session, one main window. Every "open" path —
/// Finder, ⌘O, drag — routes through `open(_:)`.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let session = SessionModel()

    /// Captured from the SwiftUI environment by the main window's root view;
    /// used to re-present the window after the user closed it.
    var showWindow: (() -> Void)?

    /// Open a markdown/HTML file or add a folder as a project.
    func open(_ url: URL) {
        open([url])
    }

    /// Open several items as one gesture — the window comes forward once.
    func open(_ urls: [URL]) {
        for url in urls {
            let url = url.standardizedFileURL
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                session.addProject(url)
                session.bumpProject(url)
            } else {
                session.select(url)
                session.bumpProject(url.deletingLastPathComponent())
            }
        }
        bringWindowFront()
    }

    func bringWindowFront() {
        if let window = session.window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
        } else {
            showWindow?()
        }
    }

    /// Puts a file's absolute path on the clipboard (for handing to AI
    /// agents) and confirms it with a toast.
    func copyPath(_ url: URL) {
        copy(url.path, toast: "Path copied")
    }

    func copy(_ string: String, toast: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        session.showToast(toast)
    }

    // MARK: - Menu commands

    func newDocument() {
        session.newDocument()
        bringWindowFront()
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.markdown, .html]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func saveActive() {
        session.saveActive()
    }

    func closeActive() {
        session.closeActive()
    }

    // MARK: - Termination

    /// Flushes everything; prompts once if content would be lost (unsaved
    /// drafts, failed writes). Returns false if the user cancelled quitting.
    func prepareToTerminate() -> Bool {
        session.flushAll()
        let unsaved = session.dirtyDocs
        return unsaved.isEmpty || session.confirmDiscard(unsaved)
    }
}
