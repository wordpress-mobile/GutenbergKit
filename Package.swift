// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

/// Updated by the Fastlane `release` lane.
let resourcesMode: DependencyMode = .release(version: "test-s3-xcframework-009", checksum: "c6a339ec3d8f78b24cf3294f98b9e74ab5322149d771f5179eb35ae20bd6dc5f")

let gutenbergKitResources: Target = resourcesMode.target

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

// MARK: - Helpers

/// Controls whether `GutenbergKitResources` resolves to a local source target
/// or a pre-built XCFramework fetched from CDN.
///
/// - `.local`: Builds from local source and resources. Use during development.
/// - `.release(version:checksum:)`: Fetches a pre-built XCFramework from CDN.
///   The version and checksum are updated by CI during the release process.
enum DependencyMode {
    case local
    case release(version: String, checksum: String)

    var target: Target {
        switch self {
        case .local:
            return .target(
                name: "GutenbergKitResources",
                path: "ios/Sources/GutenbergKitResources",
                // The directory is named "Gutenberg" instead of "Resources" because
                // a directory named "Resources" inside a flat .bundle confuses codesign:
                // it can't distinguish iOS flat layout from macOS deep layout.
                resources: [.copy("Gutenberg")]
            )
        case let .release(version, checksum):
            return .binaryTarget(
                name: "GutenbergKitResources",
                url: "https://cdn.a8c-ci.services/gutenbergkit/\(version)/GutenbergKitResources.xcframework.zip",
                checksum: checksum
            )
        }
    }
}
