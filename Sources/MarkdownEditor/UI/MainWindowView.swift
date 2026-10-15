import AppKit
import SwiftUI

/// Root of the single main window: project sidebar + editor, or the empty
/// launch state before any project exists.
struct MainWindowView: View {
    @ObservedObject var session = AppModel.shared.session
    @ObservedObject var theme = ThemeSettings.shared
    @ObservedObject var reader = ReadAloud.shared
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
                        Text("Select a file in the sidebar")
                            .font(.system(size: 16))
                            .foregroundStyle(NMColors.secondaryForeground)
                    }
                    if session.showSettings {
                        SettingsView { session.showSettings = false }
                            .background(NMColors.background)
                    }
                }
                // SwiftUI owns this title bar; NSWindow.subtitle set directly doesn't show.
                .navigationSubtitle(session.stats)
                .toolbar {
                    ToolbarItem {
                        Button {
                            theme.appearance = colorScheme == .dark ? .light : .dark
                        } label: {
                            Label(
                                colorScheme == .dark ? "Light Mode" : "Dark Mode",
                                systemImage: colorScheme == .dark ? "sun.max" : "moon"
                            )
                        }
                        .help(colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode")
                    }
                    ToolbarItem {
                        Button {
                            session.showSettings.toggle()
                        } label: {
                            Label("Settings", systemImage: session.showSettings ? "gearshape.fill" : "gearshape")
                        }
                        .help("Settings (⌘,)")
                    }
                    if let doc = session.activeDoc, !doc.isHTML, !doc.isCanvas {
                        ToolbarItem {
                            Button {
                                switch reader.state {
                                case .idle:
                                    // Highlight in this document's editor, even if another becomes active.
                                    let id = doc.id
                                    reader.onSentence = { [weak session] sentence in
                                        session?.editorPool.controllers[id]?.webView.evaluateJavaScript(
                                            "window.readAloudHighlight(\(sentence.map(jsonString) ?? "null"))"
                                        )
                                    }
                                    // Read from the sentence the cursor is in; the editor finds it.
                                    let text = doc.text
                                    let sentences = ReadAloud.sentences(of: text).map { jsonString($0.text) }.joined(separator: ",")
                                    guard let webView = session.editorPool.controllers[id]?.webView else {
                                        reader.start(text)
                                        return
                                    }
                                    webView.evaluateJavaScript("window.readAloudStart([\(sentences)])") { first, _ in
                                        reader.start(text, from: (first as? Int) ?? 0)
                                    }
                                case .speaking: reader.pause()
                                case .paused: reader.resume()
                                }
                            } label: {
                                switch reader.state {
                                case .idle: Label("Read Aloud", systemImage: "speaker.wave.2")
                                case .speaking: Label("Pause", systemImage: "pause")
                                case .paused: Label("Resume", systemImage: "play")
                                }
                            }
                            .help(readAloudHelp(doc.text))
                        }
                    }
                    if reader.state != .idle {
                        ToolbarItem {
                            Button {
                                reader.stop()
                            } label: {
                                Label("Stop Reading", systemImage: "stop")
                            }
                            .help("Stop reading aloud")
                        }
                    }
                    if let url = session.activeDoc?.url {
                        ToolbarItem {
                            Button {
                                AppModel.shared.copyPath(url)
                            } label: {
                                Label("Copy Path", systemImage: "doc.on.clipboard")
                            }
                            .help("Copy the file's path to the clipboard")
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
            reader.onError = { session.showToast($0) }
            session.refreshFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            // External renames/deletes become visible when the window regains focus.
            if (note.object as? NSWindow) === session.window {
                session.refreshFiles()
            }
        }
    }

    private func readAloudHelp(_ text: String) -> String {
        guard reader.state == .idle else { return reader.state == .speaking ? "Pause reading" : "Resume reading" }
        let language = ReadAloud.language(of: text)
        let name = reader.voiceName(for: language)
        #if Kokoro
        if reader.kokoroVoice(for: language) == nil && reader.plapreVoice(for: language) == nil {
            let voices = language == "da" ? "Danish" : "English"
            return "Read aloud from the cursor with \(name). For a more natural voice, download the \(voices) voices in Settings."
        }
        #endif
        return "Read aloud from the cursor with \(name)"
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("Open a .md file or a folder")
                .font(.system(size: 16))
                .foregroundStyle(NMColors.secondaryForeground)
            Button("Open…") { AppModel.shared.openPanel() }
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
