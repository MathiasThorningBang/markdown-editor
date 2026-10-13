import AppKit
import Combine
import WebKit

/// Shows a JSON Canvas (.canvas) file on a pan/zoom surface: HTML file nodes are
/// live frames, .md and text nodes rendered cards. The canvas JSON is the
/// document's text, so autosave, disk reload and conflicts work as for markdown;
/// the page posts the updated JSON when a frame is moved or resized.
@MainActor
final class CanvasController: NSObject, DocumentViewController, WKNavigationDelegate, WKScriptMessageHandler {
    let webView: EditorWebView
    private let document: OpenDocument
    private let messageProxy = WeakMessageHandler()
    private var themeSubscription: AnyCancellable?
    private(set) var isReady = false
    var onReady: (() -> Void)?

    /// Nothing loads until the offline rules are installed.
    private var isOffline = false
    /// Modification dates of the files the nodes point at, as the page last got them.
    private var fileDates: [String: Date] = [:]

    private var folderURL: URL? { document.url?.deletingLastPathComponent() }

    init(document: OpenDocument) {
        self.document = document
        // Handlers before WKWebView(configuration:): the web view copies its configuration.
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: "mdfile")
        for name in ["canvasReady", "contentChanged", "openFile", "openLink", "toggleTask"] {
            config.userContentController.add(messageProxy, name: name)
        }
        webView = EditorWebView(frame: .zero, configuration: config)
        super.init()
        messageProxy.target = self
        webView.navigationDelegate = self
        webView.fileURL = { [document] in document.url }
        webView.copyReference = { [weak self] _ in self?.copyReference() }
        webView.fileDrop = { [weak self] files, point in self?.drop(files, at: point) ?? false }
        document.onReload = { [weak self] in self?.sendCanvas() }
        document.onDiskCheck = { [weak self] in self?.reloadChangedFiles() }

        // Accent and fonts are baked into the injected script: rebuild and reload.
        // The page keeps its pan/zoom across the reload.
        themeSubscription = ThemeSettings.shared.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.load() }

        PreviewRuntime.blockNetwork(config.userContentController) { [weak self] installed in
            guard let self else { return }
            isOffline = installed
            if installed {
                load()
            } else {
                // Fail closed: without the rules the frames could reach the network.
                webView.loadHTMLString(
                    "<meta name=color-scheme content='light dark'><p style='font: 16px system-ui; padding: 32px'>This canvas can't be shown because network blocking couldn't be turned on.</p>",
                    baseURL: nil
                )
                markReady()
            }
        }
    }

    private func load() {
        guard isOffline else { return }
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        // Into every frame: the canvas page gets the tokens, the frames tokens,
        // mdTheme and Chart.js, exactly like an opened .html file.
        controller.addUserScript(WKUserScript(
            source: PreviewRuntime.script(fragment: false, canvas: true),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let webDir = Bundle.module.url(forResource: "Web", withExtension: nil)!
        webView.loadFileURL(webDir.appendingPathComponent("canvas.html"), allowingReadAccessTo: webDir)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        load()
    }

    // MARK: - Page state

    /// The whole canvas, plus what the page can't read itself: file dates (to
    /// bust caches) and the text of .md nodes.
    private func sendCanvas() {
        guard let url = document.url, let folderURL else { return }
        fileDates = [:]
        var files: [String: Any] = [:]
        for path in referencedFiles() {
            let date = OpenDocument.modificationDate(URL(fileURLWithPath: path))
            fileDates[path] = date
            files[path] = fileInfo(path, date)
        }
        let payload: [String: Any] = [
            "text": document.text, "path": url.path, "folder": folderURL.path, "files": files,
        ]
        let json = String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        webView.evaluateJavaScript("window.setCanvas(\(json))") { [weak self] _, _ in
            self?.markReady()
        }
    }

    /// The host shows the web view only once it has something to show.
    private func markReady() {
        guard !isReady else { return }
        isReady = true
        onReady?()
        onReady = nil
    }

    /// Reloads only the frames whose file changed since the page got it.
    private func reloadChangedFiles() {
        guard isReady else { return }
        for path in referencedFiles() {
            let date = OpenDocument.modificationDate(URL(fileURLWithPath: path))
            guard date != fileDates[path] ?? nil else { continue }
            fileDates[path] = date
            let info = String(data: try! JSONSerialization.data(withJSONObject: fileInfo(path, date)), encoding: .utf8)!
            webView.evaluateJavaScript("window.reloadFile(\(jsonString(path)), \(info))")
        }
    }

    private func fileInfo(_ path: String, _ date: Date?) -> [String: Any] {
        var info: [String: Any] = ["version": date.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0]
        if path.lowercased().hasSuffix(".md"), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            info["text"] = text
        }
        return info
    }

    /// Absolute paths of the canvas's file nodes. Paths are relative to the
    /// .canvas file's folder (or absolute).
    private func referencedFiles() -> Set<String> {
        guard let folderURL,
              let data = document.text.data(using: .utf8),
              let canvas = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = canvas["nodes"] as? [[String: Any]] else { return [] }
        return Set(nodes.compactMap { node in
            guard node["type"] as? String == "file", let file = node["file"] as? String else { return nil }
            return resolve(file, in: folderURL).path
        })
    }

    /// Same rules as resolve() in canvas.js, so both sides agree on the path.
    private func resolve(_ path: String, in folder: URL) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path).standardizedFileURL
            : URL(fileURLWithPath: path, relativeTo: folder).standardizedFileURL
    }

    // MARK: - Messages

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Frames run the user's HTML; only the canvas page itself may talk to Swift.
        guard message.frameInfo.isMainFrame else { return }
        switch message.name {
        case "canvasReady":
            sendCanvas()
        case "contentChanged":
            guard let text = message.body as? String else { return }
            document.textChanged(text)
        case "openFile":
            guard let path = message.body as? String else { return }
            openFile(URL(fileURLWithPath: path))
        case "openLink":
            guard let raw = message.body as? String, let url = URL(string: raw),
                  ["http", "https", "mailto"].contains(url.scheme ?? "") else { return }
            NSWorkspace.shared.open(url)
        case "toggleTask":
            guard let body = message.body as? [String: Any], let path = body["path"] as? String,
                  let index = body["index"] as? Int, let checked = body["checked"] as? Bool else { return }
            toggleTask(in: path, index: index, checked: checked)
        default:
            break
        }
    }

    /// Ticks the index-th task item of a .md card's file. Only files the canvas
    /// points at; the card reloads from disk on the next check.
    private func toggleTask(in path: String, index: Int, checked: Bool) {
        guard path.lowercased().hasSuffix(".md"), referencedFiles().contains(path),
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              let updated = Self.settingTask(index, checked: checked, in: text) else {
            reloadChangedFiles()
            return
        }
        do {
            try updated.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            AppModel.shared.session.showToast("Couldn't save \((path as NSString).lastPathComponent)")
        }
        reloadChangedFiles()
    }

    /// `text` with the index-th task box (`- [ ]`, `* [x]`, `1. [ ]`, also in
    /// quotes) set, counting like marked: boxes in fenced code don't count.
    static func settingTask(_ index: Int, checked: Bool, in text: String) -> String? {
        let task = try! NSRegularExpression(pattern: #"^((?:>\s?)*\s*(?:[-*+]|\d+[.)])\s+)\[[ xX]\](?=\s|$)"#)
        var lines = text.components(separatedBy: "\n")
        var fence: String?
        var count = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.drop { $0 == " " }
            if let marker = fence {
                if trimmed.hasPrefix(marker) { fence = nil }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                continue
            }
            let range = NSRange(line.startIndex..., in: line)
            guard let match = task.firstMatch(in: line, range: range) else { continue }
            if count == index {
                let prefix = (line as NSString).substring(with: match.range(at: 1))
                let rest = (line as NSString).substring(from: match.range.upperBound)
                lines[i] = prefix + (checked ? "[x]" : "[ ]") + rest
                return lines.joined(separator: "\n")
            }
            count += 1
        }
        return nil
    }

    /// Documents the app shows open in a tab; anything else (images) in its own app.
    private func openFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        let shown = FolderScanner.markdownExtensions.union(FolderScanner.htmlExtensions)
            .union(FolderScanner.canvasExtensions)
        if shown.contains(ext) {
            AppModel.shared.session.select(url)
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    /// "path › node "id" (file)" for the selected node, for pasting to an agent.
    private func copyReference() {
        webView.evaluateJavaScript("window.selectedNode?.()") { [weak self] result, _ in
            guard let self, let url = document.url else { return }
            guard let node = result as? [String: Any], let id = node["id"] as? String else {
                AppModel.shared.session.showToast("Select a node first")
                return
            }
            var reference = "\(url.path) › node \"\(id)\""
            if let file = node["file"] as? String { reference += " (\(file))" }
            if let text = node["text"] as? String, !text.isEmpty {
                reference += "\n" + text.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")
            }
            AppModel.shared.copy(reference, toast: "Reference copied")
        }
    }

    // MARK: - Dropping files

    private static let droppable = ["html", "htm", "md", "png", "jpg", "jpeg", "gif", "webp", "svg", "avif"]

    /// Files dragged in from Finder are copied to assets/ next to the canvas (so
    /// the folder stays self-contained) and become nodes at the drop point.
    private func drop(_ files: [URL], at point: CGPoint) -> Bool {
        guard let folderURL else { return false }
        let assets = folderURL.appendingPathComponent("assets")
        var added: [[String: Any]] = []
        for source in files where Self.droppable.contains(source.pathExtension.lowercased()) {
            guard let target = copyIntoAssets(source, assets) else { continue }
            var node: [String: Any] = ["file": "assets/" + target.lastPathComponent]
            if let size = NSImage(contentsOf: target)?.size, size.width > 0, size.height > 0 {
                node["width"] = size.width
                node["height"] = size.height
            }
            added.append(node)
        }
        guard !added.isEmpty else { return false }
        let json = String(data: try! JSONSerialization.data(withJSONObject: added), encoding: .utf8)!
        webView.evaluateJavaScript("window.addFiles(\(json), \(point.x), \(point.y))")
        return true
    }

    /// Copies `source` into `assets`, with "-2", "-3"… on a name clash. A file
    /// already in assets/ is used as it is.
    private func copyIntoAssets(_ source: URL, _ assets: URL) -> URL? {
        let fm = FileManager.default
        if source.deletingLastPathComponent().standardizedFileURL == assets.standardizedFileURL { return source }
        do {
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            var target = assets.appendingPathComponent(source.lastPathComponent)
            var n = 2
            while fm.fileExists(atPath: target.path) {
                target = assets.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext)
                n += 1
            }
            try fm.copyItem(at: source, to: target)
            return target
        } catch {
            AppModel.shared.session.showToast("Couldn't copy \(source.lastPathComponent)")
            return nil
        }
    }

    // MARK: - Navigation

    // The canvas page never navigates. A link inside a frame may move that frame to
    // another local screen (a clickable prototype); web links open in the browser.
    // (Keep the handler @MainActor like WebKit's, or under Swift 6 this silently
    // stops matching the protocol.)
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let isMain = navigationAction.targetFrame?.isMainFrame ?? true
        guard navigationAction.navigationType == .linkActivated, let target = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if !isMain, target.scheme == "mdfile" {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if ["http", "https", "mailto"].contains(target.scheme ?? "") { NSWorkspace.shared.open(target) }
        }
    }
}
