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
let resourcesVersion = "test-s3-xcframework-008"
let resourcesChecksum = "7397e700129326fb8c2ab228ac711fb15d1f046212e3f5b37c8708c5bf431166"

let gutenbergKitResources: Target = useLocalResources
    ? .target(
        name: "GutenbergKitResources",
        path: "ios/Sources/GutenbergKitResources",
        // The directory is named "Gutenberg" instead of "Resources" because
        // a directory named "Resources" inside a flat .bundle confuses codesign:
        // it can't distinguish iOS flat layout from macOS deep layout.
        resources: [.copy("Gutenberg")]
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
        .library(name: "GutenbergKit", targets: ["GutenbergKit"]),
        .library(name: "GutenbergKitResources", targets: ["GutenbergKitResources"]),
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
            exclude: ["Gutenberg"],
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
