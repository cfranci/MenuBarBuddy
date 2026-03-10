// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarBuddy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "MenuBarBuddy",
            dependencies: ["HotKey"],
            path: "Sources/MenuBarBuddy"
        )
    ]
)
