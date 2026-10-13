import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
    static let jsonCanvas = UTType(importedAs: "org.jsoncanvas.canvas")
}

struct FileEntry: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }
}

enum FolderScanner {
    /// Matches the extensions declared in Info.plist's UTImportedTypeDeclarations.
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]
    /// Shown read-only (HTMLViewerController).
    static let htmlExtensions: Set<String> = ["html", "htm"]
    /// JSON Canvas files (jsoncanvas.org), shown on a pan/zoom canvas (CanvasController).
    static let canvasExtensions: Set<String> = ["canvas"]

    static func isHTML(_ url: URL) -> Bool {
        htmlExtensions.contains(url.pathExtension.lowercased())
    }

    static func isCanvas(_ url: URL) -> Bool {
        canvasExtensions.contains(url.pathExtension.lowercased())
    }

    static func scan(_ folder: URL) -> [FileEntry] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return contents
            .filter {
                let ext = $0.pathExtension.lowercased()
                return markdownExtensions.contains(ext) || htmlExtensions.contains(ext)
                    || canvasExtensions.contains(ext)
            }
            .map(FileEntry.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
