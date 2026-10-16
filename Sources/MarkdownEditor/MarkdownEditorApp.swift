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
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    AppModel.shared.session.showSettings = true
                    AppModel.shared.bringWindowFront()
                    Updater.shared.check()
                }
                .disabled(!Updater.shared.canUpdate)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppModel.shared.session.showSettings = true
                    AppModel.shared.bringWindowFront()
                }
                .keyboardShortcut(",")
            }
            CommandGroup(replacing: .newItem) {
                Button("New File") { AppModel.shared.newDocument() }
                    .keyboardShortcut("n")
                Button("Open…") { AppModel.shared.openPanel() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { AppModel.shared.saveActive() }
                    .keyboardShortcut("s")
                Button("Close File") { AppModel.shared.closeActive() }
                    .keyboardShortcut("w")
            }
        }
    }
}
