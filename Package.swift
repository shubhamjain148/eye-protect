// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EyeProtect",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure scheduling logic: no AppKit, fully unit-tested.
        .target(
            name: "EyeProtectCore",
            path: "Sources/EyeProtectCore"
        ),
        // The menu-bar app: AppKit/SwiftUI adapters around the core.
        .executableTarget(
            name: "EyeProtect",
            dependencies: ["EyeProtectCore"],
            path: "Sources/EyeProtect"
        ),
        .testTarget(
            name: "EyeProtectCoreTests",
            dependencies: ["EyeProtectCore"],
            path: "Tests/EyeProtectCoreTests"
        ),
    ]
)
