// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "MarkdownEditor",
    platforms: [.macOS(.v14)],
    // Neural read-aloud voices (Kokoro for English, Plapre for Danish) are opt-in:
    // `swift build --traits Kokoro`, or `KOKORO=1 ./build.sh`. They need
    // `brew install espeak-ng llama.cpp` and macOS 27.
    traits: [.trait(name: "Kokoro")],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.19.2"),
    ],
    targets: [
        .systemLibrary(name: "CEspeakNG", path: "Sources/CEspeakNG"),
        .systemLibrary(name: "CLlama", path: "Sources/CLlama"),
        .executableTarget(
            name: "MarkdownEditor",
            dependencies: [
                .target(name: "CEspeakNG", condition: .when(traits: ["Kokoro"])),
                .target(name: "CLlama", condition: .when(traits: ["Kokoro"])),
                .product(
                    name: "onnxruntime",
                    package: "onnxruntime-swift-package-manager",
                    condition: .when(traits: ["Kokoro"])
                ),
            ],
            path: "Sources/MarkdownEditor",
            resources: [.copy("Web"), .copy("Speech/PlapreSpeakers.json")],
            linkerSettings: [.unsafeFlags(
                ["-L/opt/homebrew/opt/espeak-ng/lib", "-L/opt/homebrew/opt/llama.cpp/lib", "-L/opt/homebrew/opt/ggml/lib"],
                .when(traits: ["Kokoro"])
            )]
        )
    ]
)
