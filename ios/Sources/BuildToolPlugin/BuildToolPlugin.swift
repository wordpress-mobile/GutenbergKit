import Foundation
import PackagePlugin

@main
struct MyBuildToolPlugin: BuildToolPlugin {

  func createBuildCommands(
      context: PluginContext,
      target: Target
  ) throws -> [Command] {
    // defaults write com.apple.dt.Xcode IDEPackageSupportDisablePluginExecutionSandbox -bool YES
    let url = URL(string: context.package.directory.string)!
    let outputFilesDir = url
      .appendingPathComponent("dist")
      .path()

    print(outputFilesDir)

    return [
        .prebuildCommand(
            displayName: "Running make build",
            executable: try context.tool(named: "make").path,
            arguments: [
              "-C",
              context.package.directory,
              "build"
            ],
            outputFilesDirectory: context.package.directory
        )
    ]
  }
}
