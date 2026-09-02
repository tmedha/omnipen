// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Omnipen",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: stroke model, smoothing, geometry. No windowing, so it is
        // unit-testable and is the piece the Tauri port mirrors most closely.
        .target(
            name: "OmnipenCore",
            path: "Sources/OmnipenCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app shell: menu bar, overlay panels, palette, tools.
        .executableTarget(
            name: "Omnipen",
            dependencies: ["OmnipenCore"],
            path: "Sources/Omnipen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OmnipenCoreTests",
            dependencies: ["OmnipenCore"],
            path: "Tests/OmnipenCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
