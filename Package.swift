// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GutenbergKit",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "GutenbergKit", targets: ["GutenbergKit"]),
        .plugin(name: "GutenbergKitDownloadJS", targets: ["Download Gutenberg JS"])
    ],
    targets: [
        .target(
            name: "GutenbergKit",
            dependencies: [],
            path: "ios/Sources/GutenbergKit",
            exclude: [],
            resources: [.copy("Gutenberg")]
        ),
        .testTarget(
            name: "GutenbergKitTests",
            dependencies: ["GutenbergKit"],
            path: "ios/Tests",
            exclude: []
        ),
        .plugin(
          name: "Download Gutenberg JS",
          capability: .command(
            intent: .custom(
              verb: "download-gutenberg-js",
              description: "Downloads the Gutenberg JS files."),
            permissions: [
              .writeToPackageDirectory(reason: "Downloads and unzips the Gutenberg JS files into your project directory."),
              .allowNetworkConnections(scope: .all(ports: []), reason: "Downloads the Gutenberg JS files from the GitHub Release.")
            ]),
          dependencies: [],
          path: "ios/Plugins/DownloadGutenbergJS"
        )
    ]
)
