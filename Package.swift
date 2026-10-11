// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MarkdownEditor",
            path: "Sources/MarkdownEditor",
            resources: [.copy("Web")]
        )
    ]
)
