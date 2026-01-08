// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Set GUTENBERGKIT_SWIFT_USE_LOCAL_RESOURCES=1 to build resources from source instead of using the pre-built XCFramework
let useLocalResources = ProcessInfo.processInfo.environment["GUTENBERGKIT_SWIFT_USE_LOCAL_RESOURCES"] != nil

// TODO: This has been manually uploaded, we'll need automation to both upload and update the URL and checksum
let revision = "e0c9c4d8df3d6fc607e5011f1fbdf1791159c5b3"
let xcframeworkURL = "https://cdn.a8c-ci.services/gutenbergkit/GutenbergKitResources-\(revision).xcframework.zip"

let xcframeworkChecksum = "270fb3f8a4b1db7be8a29f5c7a28dd5ce2127a2072c0e1bf95b7ddae7e8d7f9c"

// Only expose GutenbergKitResources as a product when building from source (needed for XCFramework generation)
let resourcesProducts: [Product] = useLocalResources
    ? [
        .library(
            name: "GutenbergKitResources",
            // Required for XCFramework generation
            type: .dynamic,
            targets: ["GutenbergKitResources"]
        )
    ]
    : []

let resourcesTargets: [Target] = useLocalResources
    ? [
        .target(
            name: "GutenbergKitResources",
            path: "ios/Sources/GutenbergKitResources",
            resources: [.copy("Resources")]
        )
    ]
    : [
        .binaryTarget(
            name: "GutenbergKitResources",
            url: xcframeworkURL,
            checksum: xcframeworkChecksum
        )
    ]

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"]),
    ] + resourcesProducts,
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
                "GutenbergKitResources"
            ],
            path: "ios/Sources/GutenbergKit",
            exclude: [],
            resources: [.copy("Gutenberg")],
            // Required to allow importing GutenbergKitResources when it's a binary target (XCFramework).
            // Without this, Swift fails with "module was built from a non-package interface" because
            // it treats both targets as same-package but the XCFramework was built for distribution.
            // Note: This means GutenbergKit source cannot use the `package` access modifier.
            // See: https://developer.apple.com/documentation/packagedescription/target/packageaccess
            packageAccess: false
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
    ] + resourcesTargets
)
