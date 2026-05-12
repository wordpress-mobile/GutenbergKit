import Foundation
import PackagePlugin

/// Generates `SupportedLocales.swift` from the JS-emitted manifest before
/// `GutenbergKit` is compiled.
///
/// The Vite build writes `dist/supported-locales.json` and `make
/// copy-dist-ios` copies it to
/// `ios/Sources/GutenbergKitResources/Gutenberg/supported-locales.json`.
/// This plugin reads that file at build time and emits an
/// `internal enum SupportedLocales { static let all: Set<String> }`
/// constant the resolver can use without runtime IO.
///
/// A missing manifest fails the build with a message pointing at `make
/// build`, so the silent-fall-through-to-English failure mode is unreachable
/// in shipped artifacts.
@main
struct SupportedLocalesPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let manifestURL = context.package.directoryURL
            .appending(path: "ios/Sources/GutenbergKitResources/Gutenberg/supported-locales.json")
        let outputURL = context.pluginWorkDirectoryURL
            .appending(path: "SupportedLocales.swift")
        let tool = try context.tool(named: "GenerateSupportedLocales")

        return [
            .buildCommand(
                displayName: "Generate SupportedLocales.swift",
                executable: tool.url,
                arguments: [
                    manifestURL.path(percentEncoded: false),
                    outputURL.path(percentEncoded: false),
                ],
                inputFiles: [manifestURL],
                outputFiles: [outputURL]
            )
        ]
    }
}
