// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Glide",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "GlideCore",
            path: "Sources/GlideCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Glide",
            dependencies: ["GlideCore"],
            path: "Sources/Glide",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // XCTest isn't bundled with Command Line Tools, so the core checks run
        // as a plain executable: `swift run GlideCoreCheck`.
        .executableTarget(
            name: "GlideCoreCheck",
            dependencies: ["GlideCore"],
            path: "Tests/GlideCoreCheck",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
