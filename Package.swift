// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let resourcesMode: DependencyMode = .release(
    version: "dae10dfdf30d1f4f5bfe05ae51aa2030042227a3",
    checksum: "910c29455fe31e1feba774a8d4fd6a511ac249c5b8f7530ae14029e553e52776"
)

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
///
/// Always `.local` at this point, but useful to have the infrastructure to switch already in place.
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
