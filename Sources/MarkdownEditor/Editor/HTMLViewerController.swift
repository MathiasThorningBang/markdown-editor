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
/// disk, so an agent writing the file can be followed live.
@MainActor
final class HTMLViewerController: NSObject, DocumentViewController, WKNavigationDelegate {
    let webView: EditorWebView
    private let url: URL
    private(set) var isReady = false
    var onReady: (() -> Void)?

    private var lastModified: Date?
    private var pollTimer: Timer?
    private var themeSubscription: AnyCancellable?

    init(url: URL) {
        self.url = url
        webView = EditorWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.fileURL = { [url] in url }

        // Accent and fonts are baked into the injected script: rebuild and reload.
        themeSubscription = ThemeSettings.shared.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reload() }
            }

        PreviewRuntime.blockNetwork(webView.configuration.userContentController) { [weak self] in
            self?.reload()
            self?.startPolling()
        }
    }

    private func reload() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(WKUserScript(
            source: PreviewRuntime.script(fragment: false),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        lastModified = modificationDate()
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    // Polling survives atomic saves (write to temp + rename), which break file descriptors.
    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if let date = self.modificationDate(), date != self.lastModified {
                    self.reload()
                }
            }
        }
    }

    private func modificationDate() -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !isReady else { return }
        isReady = true
        onReady?()
        onReady = nil
    }

    // Clicked links open outside the app; the viewer itself never navigates away.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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
    static func blockNetwork(_ controller: WKUserContentController, then done: @escaping () -> Void) {
        if let networkRules {
            controller.add(networkRules)
            return done()
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
                done()
            }
        }
    }
}
