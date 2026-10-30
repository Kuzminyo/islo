// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Islo",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Islo",
            path: "Sources/Islo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
