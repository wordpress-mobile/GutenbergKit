// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"]),
        .plugin(name: "GutenbergKitPlugin", targets: ["GutenbergKitPlugin"])
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: [],
            path: "ios/Sources/GutenbergKit",
            exclude: [],
            resources: [.copy("Gutenberg")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"],
            path: "ios/Tests",
            exclude: []
        ),
        .plugin(
            name: "GutenbergKitPlugin",
            capability: .buildTool(),
            dependencies: ["GutenbergKitPluginExecutable"],
            path: "ios/Plugins/GutenbergKitPlugin"
        ),
        .executableTarget(
            name: "GutenbergKitPluginExecutable",
            dependencies: [],
            path: "ios/Sources/GutenbergKitPluginExecutable",
            exclude: [],
            resources: [.copy("gbkit.sh")]
        )
    ]
)
