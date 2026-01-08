// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"]),
        // Required to be defined here even though it's not meant for
        // standalone use so that xcodebuild can generate a scheme for it to use to
        // generate the XCFramework
        .library(
            name: "GutenbergKitResources",
            // Required for XCFramework generation
            type: .dynamic,
            targets: ["GutenbergKitResources"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/exyte/SVGView.git", from: "1.0.6"),
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: [
                "SwiftSoup",
                "SVGView",
                .target(name: "GutenbergKitResources")
            ],
            path: "ios/Sources/GutenbergKit",
            exclude: [],
            resources: [.copy("Gutenberg")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"],
            path: "ios/Tests/GutenbergKitTests",
            exclude: [],
            resources: [
                .process("Resources")
            ]
        ),

        .target(
            name: "GutenbergKitResources",
            path: "ios/Sources/GutenbergKitResources",
            resources: [.copy("Resources")]
        )
    ]
)
