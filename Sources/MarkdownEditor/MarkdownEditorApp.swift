import SwiftUI

@main
struct MarkdownEditorApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { config in
            EditorWebView(text: config.$document.text, fileURL: config.fileURL)
                .frame(minWidth: 480, minHeight: 400)
        }
    }
}
