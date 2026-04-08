// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BTalk",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "BTalk",
            path: "Sources/BTalk"
        )
    ]
)
