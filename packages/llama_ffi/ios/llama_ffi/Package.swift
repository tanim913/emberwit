// swift-tools-version: 5.9
// iOS build of llama_ffi for Swift Package Manager (Flutter's default).
//
// Links the official llama.cpp xcframework release (CPU + Metal) matching
// the pinned submodule tag. Dart opens it as `llama.framework/llama`.
// To bump llama.cpp: update the tag in the URL and the checksum, which is the
// sha256 digest listed on the GitHub release page.
import PackageDescription

let package = Package(
    name: "llama_ffi",
    platforms: [
        .iOS("15.0"),
    ],
    products: [
        .library(name: "llama-ffi", targets: ["llama_ffi"]),
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11155/llama-b11155-xcframework.zip",
            checksum: "1f157b625fe298aba099572a90aade102a1de31769ddfeff0e08330fb1296979"
        ),
        .target(
            name: "llama_ffi",
            dependencies: ["llama"],
            path: "Sources/llama_ffi"
        ),
    ]
)
