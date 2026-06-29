// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DevToolbox",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DevToolbox",
            path: "Sources/DevToolbox"
        )
    ]
)
