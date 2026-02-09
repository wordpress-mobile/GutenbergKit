// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// When set, `GutenbergKitResources` is built from local source + resources.
/// When unset, it resolves to a pre-built XCFramework fetched from CDN.
let useLocalResources = Context.environment["GUTENBERGKIT_SWIFT_USE_LOCAL_RESOURCES"] != nil

// MARK: - Resources target

/// Pre-built XCFramework version for tagged releases.
/// Updated by the Fastlane `release` lane.
let resourcesVersion = "0.0.0"
let resourcesChecksum = "0000000000000000000000000000000000000000000000000000000000000000"

let gutenbergKitResources: Target = useLocalResources
    ? .target(
        name: "GutenbergKitResources",
        path: "ios/Sources/GutenbergKitResources",
        resources: [.copy("Resources")]
    )
    : .binaryTarget(
        name: "GutenbergKitResources",
        url: "https://cdn.a8c-ci.services/gutenbergkit/\(resourcesVersion)/GutenbergKitResources.xcframework.zip",
        checksum: resourcesChecksum
    )

// MARK: - Package

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/exyte/SVGView.git", from: "1.0.6"),
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: ["SwiftSoup", "SVGView", "GutenbergKitResources"],
            path: "ios/Sources/GutenbergKit",
            exclude: [],
            resources: [.copy("Gutenberg")],
            packageAccess: false
        ),
        gutenbergKitResources,
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"],
            path: "ios/Tests/GutenbergKitTests",
            exclude: [],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
