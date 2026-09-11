// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDuo",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacDuo", targets: ["MacDuo"]),
        .executable(name: "lidprobe", targets: ["lidprobe"]),
        .library(name: "DuoCore", targets: ["DuoCore"]),
        .library(name: "LidAngle", targets: ["LidAngle"]),
        .library(name: "DuoRender", targets: ["DuoRender"]),
        .executable(name: "duofold", targets: ["duofold"]),
    ],
    targets: [
        // Pure maths and logic: geometry, curves, springs, the fold state machine.
        .target(
            name: "DuoCore",
            path: "Sources/DuoCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Reads the hinge angle from the MacBook's lid angle sensor over HID.
        .target(
            name: "LidAngle",
            path: "Sources/LidAngle",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The Metal renderer: shader, pyramid, still and live pictures.
        .target(
            name: "DuoRender",
            dependencies: ["DuoCore"],
            path: "Sources/DuoRender",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Renders the fold on an image file, for QA and marketing frames.
        .executableTarget(
            name: "duofold",
            dependencies: ["DuoCore", "DuoRender"],
            path: "Sources/RenderTool",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MacDuo",
            dependencies: ["DuoCore", "LidAngle", "DuoRender"],
            path: "Sources/MacDuo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "lidprobe",
            dependencies: ["LidAngle"],
            path: "Sources/lidprobe",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DuoCoreTests",
            dependencies: ["DuoCore"],
            path: "Tests/DuoCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
