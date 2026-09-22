// swift-tools-version: 6.0
import PackageDescription

// Pure logic shared by the app and its tests: no AppKit, no WhisperKit, no
// default actor isolation. Tests run with `swift test`, without an app host.
let package = Package(
    name: "WritelessCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WritelessCore", targets: ["WritelessCore"])
    ],
    targets: [
        .target(name: "WritelessCore"),
        .testTarget(name: "WritelessCoreTests", dependencies: ["WritelessCore"]),
    ]
)
