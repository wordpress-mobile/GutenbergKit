// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

// This Package.swift file is only for the Library to be visible to the Demo App.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"])
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"]
        )
    ]
)
