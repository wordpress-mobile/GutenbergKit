// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"])
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            resources: [.copy("Gutenberg")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"]),
    ]
)
