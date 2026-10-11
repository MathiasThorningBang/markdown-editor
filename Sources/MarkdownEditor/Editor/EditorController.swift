import AppKit
import Combine
import UniformTypeIdentifiers
import WebKit

/// Owns one WKWebView running the Crepe editor for exactly one document.
/// Pooled per workspace so switching files never touches editor content
/// (each file keeps its own ProseMirror undo history).
@MainActor
final class EditorController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: EditorWebView
    private let document: OpenDocument
    private let messageProxy = WeakMessageHandler()
    private var subscriptions: Set<AnyCancellable> = []

    /// True once Crepe has rendered the document. The host keeps the web view
    /// hidden until then, so switching files never shows a blank editor.
    private(set) var isReady = false
    var onReady: (() -> Void)?

    /// Relative images and links resolve against the document's own folder —
    /// projects can live anywhere on disk.
    private var folderURL: URL? { document.url?.deletingLastPathComponent() }

    init(document: OpenDocument) {
        self.document = document

        // Handlers must be registered before WKWebView(configuration:) — the
        // web view copies its configuration. The weak proxy breaks the retain
        // cycle userContentController would otherwise create.
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: "mdfile")
        config.userContentController.add(messageProxy, name: "contentChanged")
        config.userContentController.add(messageProxy, name: "openLink")
        config.userContentController.add(messageProxy, name: "editorReady")
        webView = EditorWebView(frame: .zero, configuration: config)

        super.init()
        messageProxy.target = self
        webView.navigationDelegate = self
        webView.fileURL = { [document] in document.url }
        // Live accent and font changes from Settings, coalesced: a color-picker drag
        // fires dozens. Dark mode needs nothing here — the web view follows the app
        // appearance via prefers-color-scheme.
        ThemeSettings.shared.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applyTheme() }
            .store(in: &subscriptions)
        // "Save As" moves the document: point relative paths at the new folder.
        document.$url
            .dropFirst()
            .sink { [weak self] url in self?.applyBase(url) }
            .store(in: &subscriptions)
        document.onReload = { [weak self] in self?.showDiskVersion() }

        let webDir = Bundle.module.url(forResource: "Web", withExtension: nil)!
        webView.loadFileURL(webDir.appendingPathComponent("editor.html"), allowingReadAccessTo: webDir)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyTheme()
        let baseJSON = folderURL.map { jsonString(baseHref($0)) } ?? "null"
        webView.evaluateJavaScript("window.initEditor(\(jsonString(document.text)), \(baseJSON))")
    }

    // WebKit killed the page (crash or memory pressure): reload it with the current text.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    private func baseHref(_ folder: URL) -> String { "mdfile://\(folder.path)/" }

    private func applyBase(_ url: URL?) {
        guard let folder = url?.deletingLastPathComponent() else { return }
        webView.evaluateJavaScript("""
            (document.querySelector('base') ?? document.head.appendChild(document.createElement('base')))
                .href = \(jsonString(baseHref(folder)))
            """)
    }

    /// The file changed on disk and the document took the new text.
    private func showDiskVersion() {
        webView.evaluateJavaScript("window.setMarkdown(\(jsonString(document.text)))")
    }

    private func applyTheme() {
        let script = ThemeSettings.shared.cssVariables
            .map { "s.setProperty(\(jsonString($0.key)), \(jsonString($0.value)));" }
            .joined()
        // themeChanged redraws ```html/```mermaid previews with the new tokens.
        webView.evaluateJavaScript(
            "(s => { \(script) })(document.documentElement.style); window.themeChanged?.()"
        )
    }

    // Links must never navigate the editor web view itself; Cmd+clicks are opened
    // externally via the openLink message instead. (Keep the handler @MainActor like
    // WebKit's, or under Swift 6 this silently stops matching the protocol.)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // ```html previews run in iframes; only the editor page itself may talk to Swift.
        guard message.frameInfo.isMainFrame else { return }
        switch message.name {
        case "contentChanged":
            guard let markdown = message.body as? String else { return }
            document.textChanged(markdown)
        case "openLink":
            guard let target = message.body as? String else { return }
            openLink(target)
        case "editorReady":
            isReady = true
            onReady?()
            onReady = nil
        default:
            break
        }
    }

    private func openLink(_ raw: String) {
        if raw.hasPrefix("#") { return } // in-document anchor, nothing to open
        if let url = URL(string: raw), let scheme = url.scheme {
            if scheme == "file" {
                openLocalPath(url.path)
            } else {
                NSWorkspace.shared.open(url) // http(s) -> browser, mailto -> Mail, etc.
            }
            return
        }
        // Strip an anchor suffix (notes.md#heading) — it isn't part of the file path.
        let pathOnly = raw.split(separator: "#", maxSplits: 1).first.map(String.init) ?? raw
        openLocalPath(pathOnly)
    }

    private func openLocalPath(_ raw: String) {
        let decoded = raw.removingPercentEncoding ?? raw
        let expanded = (decoded as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else if let folderURL {
            url = URL(fileURLWithPath: expanded, relativeTo: folderURL).standardizedFileURL
        } else {
            return // relative path in an unsaved document — nothing to resolve against
        }
        NSWorkspace.shared.open(url)
    }

    private func jsonString(_ string: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [string])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }
}

/// Web view whose context menu starts with "Copy Path" for saved documents —
/// the quickest way to hand the file's path to an AI agent.
final class EditorWebView: WKWebView {
    var fileURL: () -> URL? = { nil }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let url = fileURL() else { return }
        let item = NSMenuItem(title: "Copy Path", action: #selector(copyPath(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = url
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        AppModel.shared.copyPath(url)
    }
}

/// WKUserContentController retains its message handlers; this proxy keeps the
/// EditorController (and thereby the whole web view graph) deallocatable.
final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

/// Serves local files (images next to the .md document) to the web view via mdfile:///absolute/path.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else { return }
        let fileURL = URL(fileURLWithPath: url.path)
        do {
            let data = try Data(contentsOf: fileURL)
            let mime = UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                ?? "application/octet-stream"
            let response = URLResponse(
                url: url,
                mimeType: mime,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
