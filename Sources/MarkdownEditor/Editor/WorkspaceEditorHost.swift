import AppKit
import SwiftUI

/// Hosts the session's pool of per-file editor web views in one container,
/// showing the active document's view and hiding the rest. Views are created
/// lazily on first activation and kept alive for the app's lifetime so
/// switching back is instant and undo history survives.
struct WorkspaceEditorHost: NSViewRepresentable {
    @ObservedObject var session: SessionModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard let doc = session.activeDoc else {
            context.coordinator.controllers.values.forEach { $0.webView.isHidden = true }
            return
        }
        let controller = context.coordinator.controller(for: doc)
        if controller.webView.superview !== container {
            controller.webView.frame = container.bounds
            controller.webView.autoresizingMask = [.width, .height]
            container.addSubview(controller.webView)
        }
        for (id, pooled) in context.coordinator.controllers {
            pooled.webView.isHidden = id != doc.id
        }
    }

    @MainActor
    final class Coordinator {
        var controllers: [UUID: EditorController] = [:]

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
    }
}
