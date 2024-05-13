// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"])
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            resources: [
                .copy("Gutenberg"),
                .process("Resources/screenshot-editor.png"),
                .process("Resources/screenshot-editor-2.png"),
                .process("Resources/screenshot-settings.png"),
                .process("Resources/screenshot-settings-2.png"),
            ]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"]),
    ]
)
