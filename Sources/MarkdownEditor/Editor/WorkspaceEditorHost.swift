import AppKit
import SwiftUI

/// Session-owned pool of per-file editor controllers. Lives outside the view
/// hierarchy so SwiftUI rebuilds never tear down loaded web views — switching
/// back to a file is instant and its undo history survives.
@MainActor
final class EditorPool {
    private(set) var controllers: [UUID: EditorController] = [:]

    func controller(for doc: OpenDocument) -> EditorController {
        if let existing = controllers[doc.id] { return existing }
        // Base resolves relative paths (images, links) against the
        // document's own folder — projects can live anywhere on disk.
        let controller = EditorController(
            document: doc,
            folderURL: doc.url?.deletingLastPathComponent()
        )
        controllers[doc.id] = controller
        return controller
    }

    /// Drop the controller for a closed document and take its web view down.
    func close(_ id: UUID) {
        controllers.removeValue(forKey: id)?.webView.removeFromSuperview()
    }

    /// Show exactly one document's web view; nil hides them all.
    func reveal(_ id: UUID?) {
        for (key, controller) in controllers {
            controller.webView.isHidden = key != id
        }
    }
}

/// Hosts the pool's web views in one container, showing the active document's
/// view. A newly opened document's view stays hidden (the previous document
/// remains visible) until Crepe reports it rendered — the swap then happens in
/// a single frame, with no blank flash.
struct WorkspaceEditorHost: NSViewRepresentable {
    @ObservedObject var session: SessionModel

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        let pool = session.editorPool
        guard let doc = session.activeDoc else {
            pool.reveal(nil)
            return
        }
        let controller = pool.controller(for: doc)
        if controller.webView.superview !== container {
            controller.webView.frame = container.bounds
            controller.webView.autoresizingMask = [.width, .height]
            controller.webView.isHidden = true
            container.addSubview(controller.webView)
        }
        if controller.isReady {
            pool.reveal(doc.id)
        } else {
            controller.onReady = { [weak session] in
                guard let session, session.activeDoc?.id == doc.id else { return }
                session.editorPool.reveal(doc.id)
            }
        }
    }
}
