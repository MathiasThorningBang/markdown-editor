import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
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

    static func scan(_ folder: URL) -> [FileEntry] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return contents
            .filter {
                let ext = $0.pathExtension.lowercased()
                return markdownExtensions.contains(ext) || htmlExtensions.contains(ext)
            }
            .map(FileEntry.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
