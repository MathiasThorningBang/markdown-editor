import AppKit
import SwiftUI

/// Root of the single main window: project sidebar + editor, or the empty
/// launch state before any project exists.
struct MainWindowView: View {
    @ObservedObject var session = AppModel.shared.session
    @ObservedObject var theme = ThemeSettings.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // The split view (and thereby the editor web views) stays mounted at
        // all times; empty/placeholder states are overlays. Swapping the
        // hierarchy itself would visibly rebuild the whole window.
        ZStack {
            NavigationSplitView {
                SidebarView(session: session)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 340)
            } detail: {
                ZStack {
                    WorkspaceEditorHost(session: session)
                        .ignoresSafeArea(edges: .bottom)
                    if session.activeDoc == nil {
                        Text("Vælg en fil i sidebaren")
                            .font(.system(size: 16))
                            .foregroundStyle(NMColors.secondaryForeground)
                    }
                    if session.showSettings {
                        SettingsView { session.showSettings = false }
                            .background(NMColors.background)
                    }
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            theme.appearance = colorScheme == .dark ? .light : .dark
                        } label: {
                            Label(
                                colorScheme == .dark ? "Lyst tema" : "Mørkt tema",
                                systemImage: colorScheme == .dark ? "sun.max" : "moon"
                            )
                        }
                        .help(colorScheme == .dark ? "Skift til lyst tema" : "Skift til mørkt tema")
                    }
                    ToolbarItem {
                        Button {
                            session.showSettings.toggle()
                        } label: {
                            Label("Indstillinger", systemImage: session.showSettings ? "gearshape.fill" : "gearshape")
                        }
                        .help("Indstillinger (⌘,)")
                    }
                    if let url = session.activeDoc?.url {
                        ToolbarItem {
                            Button {
                                AppModel.shared.copyPath(url)
                            } label: {
                                Label("Kopiér sti", systemImage: "doc.on.clipboard")
                            }
                            .help("Kopiér filens sti til udklipsholderen")
                        }
                    }
                }
            }
            if session.projects.isEmpty && session.openDocs.isEmpty {
                emptyState
                    .background(Color(nsColor: .windowBackgroundColor))
            }
            if let toast = session.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NMColors.background)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(NMColors.foreground.opacity(0.92)))
                        .padding(.bottom, 20)
                }
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .tint(theme.accent)
        .animation(.easeInOut(duration: 0.18), value: session.toast)
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
