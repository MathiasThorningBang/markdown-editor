import SwiftUI

@main
struct MarkdownEditorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Markdown Editor", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 1050, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Ny fil") { AppModel.shared.newDocument() }
                    .keyboardShortcut("n")
                Button("Åbn…") { AppModel.shared.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Gem") { AppModel.shared.saveActive() }
                    .keyboardShortcut("s")
            }
        }
    }
}
