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
            //
            // Disabled to test binary target
            // type: .dynamic,
            targets: ["GutenbergKit"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.5"),
        .package(url: "https://github.com/exyte/SVGView.git", from: "1.0.6"),
    ],
    targets: [
        // Hardcoded binary target to test distribution in a client.
        //
        .binaryTarget(
            name: "GutenbergKit",
            url: "https://cdn.a8c-ci.services/gutenberg-kit/xcframework/a4374acb25d8f31bc17e9664294ba392c6fb03cd51d39cc4681ba48694afccda/GutenbergKit.xcframework.zip",
            checksum: "a4374acb25d8f31bc17e9664294ba392c6fb03cd51d39cc4681ba48694afccda"
        )
        // Temporarily disabled just so we can try the binary distribution in a client.
        //
        // .target(
        //     name: "GutenbergKit",
        //     dependencies: ["SwiftSoup", "SVGView"],
        //     path: "ios/Sources/GutenbergKit",
        //     exclude: [],
        //     resources: [.copy("Gutenberg")]
        // ),
        // .testTarget(
        //     name: "GutenbergKitTests",
        //     dependencies: ["GutenbergKit"],
        //     path: "ios/Tests",
        //     exclude: [],
        //     resources: [
        //         .copy("GutenbergKitTests/Resources/manifest-test-case-1.json")
        //     ]
        // ),
    ]
)
