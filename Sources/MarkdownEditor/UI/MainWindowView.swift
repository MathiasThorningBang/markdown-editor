import AppKit
import SwiftUI

/// Root of the single main window: project sidebar + editor, or the empty
/// launch state before any project exists.
struct MainWindowView: View {
    @ObservedObject var session = AppModel.shared.session
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if session.projects.isEmpty && session.openDocs.isEmpty {
                emptyState
            } else {
                NavigationSplitView {
                    SidebarView(session: session)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
                } detail: {
                    if session.activeDoc != nil {
                        WorkspaceEditorHost(session: session)
                            .ignoresSafeArea(edges: .bottom)
                    } else {
                        Text("Vælg en fil i sidebaren")
                            .font(.system(size: 16))
                            .foregroundStyle(NMColors.secondaryForeground)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .background(WindowAccessor { window in
            if session.window !== window { session.window = window }
        })
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            urls.forEach { AppModel.shared.open($0) }
            return true
        }
        .onAppear {
            AppModel.shared.showWindow = { openWindow(id: "main") }
            session.refreshFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // External renames/deletes become visible when the window regains focus.
            if (note.object as? NSWindow) === session.window {
                session.refreshFiles()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Åbn en .md-fil eller en mappe")
                .font(.system(size: 16))
                .foregroundStyle(NMColors.secondaryForeground)
            Button("Åbn…") { AppModel.shared.openPanel() }
                .keyboardShortcut("o")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Reports the hosting NSWindow once it exists — used to disallow native
/// tabbing and to drive window title/proxy icon from the session.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}
