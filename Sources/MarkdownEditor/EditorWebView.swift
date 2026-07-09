import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct EditorWebView: NSViewRepresentable {
    @Binding var text: String
    let fileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: "mdfile")
        config.userContentController.add(context.coordinator, name: "contentChanged")
        config.userContentController.add(context.coordinator, name: "openLink")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        let webDir = Bundle.module.url(forResource: "Web", withExtension: nil)!
        let html = webDir.appendingPathComponent("editor.html")
        webView.loadFileURL(html, allowingReadAccessTo: webDir)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Push external changes (e.g. Revert) into the editor; skip echoes of the editor's own edits.
        if context.coordinator.isLoaded && text != context.coordinator.lastText {
            context.coordinator.lastText = text
            context.coordinator.callSetMarkdown(text)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: EditorWebView
        weak var webView: WKWebView?
        var isLoaded = false
        var lastText: String

        init(_ parent: EditorWebView) {
            self.parent = parent
            self.lastText = parent.text
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoaded = true
            lastText = parent.text
            var baseJSON = "null"
            if let dir = parent.fileURL?.deletingLastPathComponent() {
                baseJSON = jsonString("mdfile://\(dir.path)/")
            }
            webView.evaluateJavaScript("window.initEditor(\(jsonString(parent.text)), \(baseJSON))")
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "contentChanged":
                guard let markdown = message.body as? String else { return }
                lastText = markdown
                parent.text = markdown
            case "openLink":
                guard let target = message.body as? String else { return }
                openLink(target)
            default:
                break
            }
        }

        // Links must never navigate the editor web view itself; Cmd+clicks are opened
        // externally via the openLink message instead.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .linkActivated ? .cancel : .allow)
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
            } else if let docDir = parent.fileURL?.deletingLastPathComponent() {
                url = URL(fileURLWithPath: expanded, relativeTo: docDir).standardizedFileURL
            } else {
                return // relative path in an unsaved document — nothing to resolve against
            }
            NSWorkspace.shared.open(url)
        }

        func callSetMarkdown(_ text: String) {
            webView?.evaluateJavaScript("window.setMarkdown(\(jsonString(text)))")
        }

        private func jsonString(_ string: String) -> String {
            let data = try! JSONSerialization.data(withJSONObject: [string])
            let array = String(data: data, encoding: .utf8)!
            return String(array.dropFirst().dropLast())
        }
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
