// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "GutenbergKit",
            // Seems like to build for XCFrameworks, we need dynamic libraries
            // https://forums.swift.org/t/how-to-build-swift-package-as-xcframework/41414/57
            //
            // TODO: Use env var to switch between static by default and dynamic opt-in
            type: .dynamic,
            targets: ["GutenbergKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/exyte/SVGView.git", from: "1.0.6"),
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: ["SwiftSoup", "SVGView"],
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
