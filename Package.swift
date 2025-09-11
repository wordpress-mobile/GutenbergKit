// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"]),
        .library(name: "GutenbergKitAssetManifestParser", targets: ["GutenbergKitAssetManifestParser"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: [],
            path: "ios/Sources/GutenbergKit",
            exclude: [],
            resources: [.copy("Gutenberg")]
        ),
        .target(
            name: "GutenbergKitAssetManifestParser",
            dependencies: ["GutenbergKit", "SwiftSoup"],
            path: "ios/Sources/GutenbergKitAssetManifestParser",
            exclude: [],
            resources: []
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"],
            path: "ios/Tests/GutenbergKitTests",
            exclude: [],
            resources: [
                .copy("Resources/manifest-test-case-1.json")
            ]
        ),
        .testTarget(
            name: "GutenbergKitAssetManifestParserTests",
            dependencies: ["GutenbergKitAssetManifestParser"],
            path: "ios/Tests/GutenbergKitAssetManifestParserTests",
            exclude: [],
            resources: [
                .copy("../GutenbergKitTests/Resources/manifest-test-case-1.json")
            ]
        )
    ]
)
