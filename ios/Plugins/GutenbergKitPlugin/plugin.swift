import PackagePlugin
import Foundation

@main
struct GutebergKitPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let scriptPath = try context.tool(named: "GutenbergKitPluginExecutable")
            .path
            .removingLastComponent()
            .appending("GutenbergKit_GutenbergKitPluginExecutable.bundle/Contents/Resources/gbkit.sh")

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
