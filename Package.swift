// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"])
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            path: "Platforms/Apple/Library/Sources",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"],
            path: "Platforms/Apple/Library/Tests"
        )
    ]
)
