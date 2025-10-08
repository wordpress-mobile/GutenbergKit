// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: ["SwiftSoup"],
            path: "ios/Sources/GutenbergKit",
            exclude: [],
            resources: [.copy("Gutenberg")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"],
            path: "ios/Tests",
            exclude: [],
            resources: [
                .copy("GutenbergKitTests/Resources/manifest-test-case-1.json")
            ]
        ),
    ]
)
