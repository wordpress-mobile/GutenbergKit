import PackagePlugin
import Foundation

@main
struct GutebergKitPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let scriptPath = context.package.directory.appending(subpath: "ios/Plugins/gbkit.sh")

        return [
            .buildCommand(
                displayName: "Running GutebergKit Script",
                executable: try context.tool(named: "GutenbergKitPluginExecutable").path,
                arguments: [scriptPath.string],
                environment: [:],
                inputFiles: [scriptPath],
                outputFiles: []
            )
        ]
    }
}
