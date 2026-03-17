// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"]),
        .library(name: "GutenbergKitHTTP", targets: ["GutenbergKitHTTP"]),
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
        .target(
            name: "GutenbergKitHTTP",
            path: "ios/Sources/GutenbergKitHTTP",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "GutenbergKitDebugServer",
            dependencies: ["GutenbergKitHTTP"],
            path: "ios/Sources/GutenbergKitDebugServer",
            exclude: ["README.md"]
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
        .testTarget(
            name: "GutenbergKitHTTPTests",
            dependencies: ["GutenbergKitHTTP"],
            path: "ios/Tests/GutenbergKitHTTPTests",
            resources: [
                .copy("../../../test-fixtures/http")
            ]
        ),
    ]
)
