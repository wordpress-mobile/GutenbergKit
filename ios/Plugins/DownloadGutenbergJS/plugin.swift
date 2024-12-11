import PackagePlugin
import Foundation

extension PackagePlugin.PluginContext {
    var pluginWorkDirectoryURL: URL {
        URL(fileURLWithPath: pluginWorkDirectory.string)
    }
}

@main
struct DownloadGutenbergJSPlugin: CommandPlugin {
    @MainActor
    func performCommand(context: PackagePlugin.PluginContext, arguments: [String]) async throws {
        let gutenbergKitRoot = try gutenbergKitRoot(relativeTo: context.pluginWorkDirectoryURL)
        let currentHash = shell("git rev-parse HEAD", in: gutenbergKitRoot)
        let destination = try downloadDestination(relativeTo: context.pluginWorkDirectoryURL)
        try downloadFile(withHash: currentHash, to: destination)
    }

    private func gutenbergKitRoot(relativeTo path: URL) throws -> URL {
        let directory = path
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("checkouts")
            .appendingPathComponent("gutenbergkit")

        if try !directoryExists(at: directory) {
            print("GutenbergKit isn't a dependency of this project – unable to continue")
            exit(1)
        }

        return directory
    }

    private func downloadDestination(relativeTo root: URL) throws -> URL {
        let directory = root.appendingPathComponent("GutenbergKit")

        // Delete and re-create the directory each time to make sure we're working with a clean slate
        if try directoryExists(at: directory) {
            try FileManager.default.removeItem(at: directory)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        return directory.appendingPathComponent("GBKit.zip")
    }

    // (Mis)using a `Task` like this is a bad idea in a real program, but for this script it'll be fine
    @MainActor
    private func downloadFile(withHash hash: String, to destination: URL) throws {
        let url = URL(string: "https://cdn.a8c-ci.services/gutenberg-kit/gutenberg-kit-resources-\(hash).zip")!
        print("Downloading editor resources from \(url)")

        let semaphore = DispatchSemaphore(value: 0)

        var error: Error?

        Task {
            do {
                let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
                let (downloadedLocation, response) = try await session.download(from: url)
                let statusCode = (response as! HTTPURLResponse).statusCode

                if statusCode != 200 {
                    print("❌ Failed downloading editor resources (status code: \(statusCode), check your network connection and that the specified version exists)")
                    print("  - Version: \(hash)")
                    print("  - URL: \(url)")

                    await MainActor.run {
                        error = CocoaError(.fileNoSuchFile)
                    }
                }

                try FileManager.default.moveItem(at: downloadedLocation, to: destination)
            } catch let _error {
                await MainActor.run {
                    error = _error
                }
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error {
            throw error
        }

        print("Downloaded editor resources to \(destination.path)")

        shell("unzip '\(destination.path)' -d '\(destination.deletingLastPathComponent().path)'")

        print("✅ Editor resources downloaded to: \(destination.deletingLastPathComponent().path)")

        try FileManager.default.removeItem(at: destination)
    }

    private func directoryExists(at url: URL) throws -> Bool {
        var isDirectory : ObjCBool = true
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    @discardableResult
    private func shell(_ command: String, in directory: URL? = nil) -> String {
        let task = Process()
        let pipe = Pipe()

        print("Running: \(command)")

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/bash"
        task.standardInput = nil
        if let directory {
            task.currentDirectoryURL = directory
        }
        task.launch()
        task.waitUntilExit()


        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)

        output.enumerateLines { line, stop in
            print("\t" + line.trimmingCharacters(in: .whitespaces))
        }

        if task.terminationStatus != 0 {
            print("Task failed")
            exit(task.terminationStatus)
        }

        return output
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension XcodeProjectPlugin.XcodePluginContext {
    var pluginWorkDirectoryURL: URL {
        URL(fileURLWithPath: pluginWorkDirectory.string)
    }
}

extension XcodeProject {
    var directoryURL: URL {
        URL(fileURLWithPath: directory.string)
    }
}

extension DownloadGutenbergJSPlugin: @preconcurrency XcodeCommandPlugin {

    @MainActor
    func performCommand(context: XcodeProjectPlugin.XcodePluginContext, arguments: [String]) throws {
        let gutenbergKitRoot = try gutenbergKitRoot(relativeTo: context.pluginWorkDirectoryURL)
        let currentHash = shell("git rev-parse HEAD", in: gutenbergKitRoot)
        let destination = try downloadDestination(relativeTo: context.xcodeProject.directoryURL)
        try downloadFile(withHash: currentHash, to: destination)
    }
}
#endif
