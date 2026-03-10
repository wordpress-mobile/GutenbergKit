// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// How releases work:
//
// On trunk, this is always `.local` — developers build from source.
// To cut a release, run `make release-on-ci NEW_VERSION=X.Y.Z`.
// That triggers a Buildkite build which:
//   1. Builds the XCFramework and computes its checksum
//   2. Runs `fastlane update_swift_package`, which rewrites this line to
//      `.release(version: "X.Y.Z", checksum: "<sha256>")`
//   3. Commits the rewritten Package.swift, tags the commit, and pushes the tag
//   4. Uploads the XCFramework to S3
//
// Consumers pulling a tagged version get the `.release` binary target.
// The tag is an *output* of the release — never a trigger.
let resourcesMode: DependencyMode = .local

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
