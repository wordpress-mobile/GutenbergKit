// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

// Set GUTENBERGKIT_SWIFT_USE_LOCAL_RESOURCES=1 to build resources from source instead of using the pre-built XCFramework
let useLocalResources = ProcessInfo.processInfo.environment["GUTENBERGKIT_SWIFT_USE_LOCAL_RESOURCES"] != nil

// TODO: This has been manually uploaded, we'll need automation to both upload and update the URL and checksum
let revision = "ce2527a6b79cbf55f3878fc96636452174e6942b"
let xcframeworkChecksum = "f5d1d1d92578cba8a9a6a58c5e23238ce8391c7662e2881243d41af0001adedc"
let xcframeworkURL = "https://cdn.a8c-ci.services/gutenbergkit/GutenbergKitResources-\(revision).xcframework.zip"

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
                .copy("Resources/manifest-test-case-1.json")
            ]
        ),
        .testTarget(
            name: "GutenbergKitResourcesTests",
            dependencies: ["GutenbergKitResources"],
            path: "ios/Tests/GutenbergKitResourcesTests",
        ),
    ] + resourcesTargets
)
