import AppKit
import Combine
import WebKit

/// What the editor pool hosts per document: a Crepe editor for markdown, or a
/// read-only viewer for .html files.
@MainActor
protocol DocumentViewController: AnyObject {
    var webView: EditorWebView { get }
    var isReady: Bool { get }
    var onReady: (() -> Void)? { get set }
}

extension EditorController: DocumentViewController {}

/// Renders an .html file read-only, with the theme runtime and Chart.js
/// injected and all network access blocked. Reloads when the file changes on
/// disk (the session's disk check), so an agent writing the file can be followed live.
@MainActor
final class HTMLViewerController: NSObject, DocumentViewController, WKNavigationDelegate {
    let webView: EditorWebView
    private let url: URL
    private(set) var isReady = false
    var onReady: (() -> Void)?

    /// Nothing loads until the offline rules are installed.
    private var isOffline = false
    private var themeSubscription: AnyCancellable?

    init(document: OpenDocument, url: URL) {
        self.url = url
        webView = EditorWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.fileURL = { [url] in url }
        document.onReload = { [weak self] in self?.reload() }

        // Accent and fonts are baked into the injected script: rebuild and reload,
        // once per burst of changes.
        themeSubscription = ThemeSettings.shared.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }

        PreviewRuntime.blockNetwork(webView.configuration.userContentController) { [weak self] installed in
            guard let self else { return }
            isOffline = installed
            if installed {
                reload()
            } else {
                // Fail closed: without the rules the page could reach the network.
                webView.loadHTMLString(
                    "<meta name=color-scheme content='light dark'><p style='font: 16px system-ui; padding: 32px'>This file can't be shown because network blocking couldn't be turned on.</p>",
                    baseURL: nil
                )
            }
        }
    }

    private func reload() {
        guard isOffline else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: PreviewRuntime.script(fragment: false),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        reload()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isReady else { return }
        isReady = true
        onReady?()
        onReady = nil
    }

    // Clicked links open outside the app; the viewer itself never navigates away.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let target = navigationAction.request.url {
            decisionHandler(.cancel)
            NSWorkspace.shared.open(target)
        } else {
            decisionHandler(.allow)
        }
    }
}

/// The theme runtime + Chart.js bundle shared with ```html previews.
@MainActor
enum PreviewRuntime {
    private static let webDir = Bundle.module.url(forResource: "Web", withExtension: nil)!
    private static let chart = (try? String(contentsOf: webDir.appendingPathComponent("vendor/chart.umd.min.js"), encoding: .utf8)) ?? ""
    private static let runtime = (try? String(contentsOf: webDir.appendingPathComponent("preview-runtime.js"), encoding: .utf8)) ?? ""

    static func script(fragment: Bool) -> String {
        let vars = ThemeSettings.shared.cssVariables
        let theme: [String: Any] = [
            "primary": vars["--color-primary"] ?? "",
            "fontBody": vars["--font-body"] ?? "",
            "fontMono": vars["--font-mono"] ?? "",
            "fragment": fragment,
        ]
        let json = String(data: try! JSONSerialization.data(withJSONObject: theme), encoding: .utf8)!
        return "window.__mdTheme = \(json);\n\(chart)\n\(runtime)"
    }

    private static var networkRules: WKContentRuleList?

    /// Blocks every http(s)/ws request: rendered HTML stays offline, like the editor.
    /// Calls `done(false)` if the rules couldn't be compiled.
    static func blockNetwork(_ controller: WKUserContentController, then done: @escaping (Bool) -> Void) {
        if let networkRules {
            controller.add(networkRules)
            return done(true)
        }
        let rules = #"[{"trigger":{"url-filter":"^(https?|wss?)://"},"action":{"type":"block"}}]"#
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "md-offline", encodedContentRuleList: rules
        ) { list, _ in
            MainActor.assumeIsolated {
                if let list {
                    networkRules = list
                    controller.add(list)
                }
                done(list != nil)
            }
        }
    }
}
