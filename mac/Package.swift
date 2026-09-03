// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Omnipen",
    platforms: [.macOS(.v14)],
    targets: [
        // Stroke model, smoothing, geometry. No graphics, no windowing.
        .target(
            name: "OmnipenCore",
            path: "Sources/OmnipenCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Core Graphics rendering, kept out of the app target so the ink engine
        // can be tested against real pixels without a window.
        .target(
            name: "OmnipenRender",
            dependencies: ["OmnipenCore"],
            path: "Sources/OmnipenRender",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The AppKit shell: menu bar, overlay panels, palette, tools.
        .executableTarget(
            name: "Omnipen",
            dependencies: ["OmnipenCore", "OmnipenRender"],
            path: "Sources/Omnipen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OmnipenCoreTests",
            dependencies: ["OmnipenCore"],
            path: "Tests/OmnipenCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "OmnipenRenderTests",
            dependencies: ["OmnipenRender"],
            path: "Tests/OmnipenRenderTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
