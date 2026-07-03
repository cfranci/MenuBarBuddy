// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarBuddy",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.0")
    ],
    targets: [
        // ObjC shim: Swift can't catch NSException, and NSStatusItem.length
        // throws one on macOS 26 when the value exceeds the system cap.
        .target(
            name: "ExceptionShield",
            path: "Sources/ExceptionShield"
        ),
        .executableTarget(
            name: "MenuBarBuddy",
            dependencies: ["HotKey", "ExceptionShield"],
            path: "Sources/MenuBarBuddy"
        )
    ]
)
