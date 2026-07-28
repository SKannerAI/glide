// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Glide",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Glide",
            path: "Sources/Glide",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
