import Foundation

guard CommandLine.arguments.count > 1 else {
    fatalError("Script path not provided")
}

let scriptPath = CommandLine.arguments[1]

let process = Process()
process.executableURL = URL(fileURLWithPath: "/bin/bash")
process.arguments = [scriptPath]

do {
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        fatalError("Script execution failed with status \(process.terminationStatus)")
    }
} catch {
    fatalError("Failed to execute script: \(error.localizedDescription)")
}
