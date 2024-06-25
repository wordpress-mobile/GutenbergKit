// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/envoy/Embassy.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: [.product(name: "Embassy", package: "Embassy")],
            resources: [.copy("Gutenberg")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"]
        )
    ]
)
