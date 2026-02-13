import PackagePlugin
import Foundation

@main
struct RustBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let packageDirectory = context.package.directoryURL
        let outputDirectory = context.pluginWorkDirectoryURL
        
        // Paths for generated files
        let generatedSwiftFile = outputDirectory.appending(path: "swift_rage.swift")
        let staticLibrary = packageDirectory.appending(path: "target/release/libswift_rage_ffi.a")
        
        // Find cargo executable
        let cargoPath = try findCargo()
        
        // Input files for dependency tracking
        let udlFile = packageDirectory.appending(path: "swift-rage-ffi/src/swift_rage.udl")
        let rustLib = packageDirectory.appending(path: "swift-rage-ffi/src/lib.rs")
        let cargoToml = packageDirectory.appending(path: "swift-rage-ffi/Cargo.toml")
        let bindingsCargoToml = packageDirectory.appending(path: "bindings-gen/Cargo.toml")
        
        // Create a build script
        let buildScript = outputDirectory.appending(path: "build-rust.sh")
        
        let scriptContent = """
            #!/bin/bash
            set -e
            
            echo "Building Rust FFI Library..."
            "\(cargoPath)" build --release --manifest-path "\(packageDirectory.path)/swift-rage-ffi/Cargo.toml"
            
            echo "Generating Swift Bindings..."
            "\(cargoPath)" run --manifest-path "\(packageDirectory.path)/bindings-gen/Cargo.toml" -- \\
                "\(udlFile.path)" \\
                "\(outputDirectory.path)"
            
            echo "Rust build complete!"
            """
        
        try scriptContent.write(to: buildScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: buildScript.path)
        
        return [
            .buildCommand(
                displayName: "Building Rust FFI and Generating Swift Bindings",
                executable: Path("/bin/bash"),
                arguments: [buildScript.path],
                inputFiles: [
                    Path(cargoToml.path),
                    Path(rustLib.path),
                    Path(udlFile.path),
                    Path(bindingsCargoToml.path)
                ],
                outputFiles: [
                    Path(generatedSwiftFile.path),
                    Path(staticLibrary.path)
                ]
            )
        ]
    }
    
    private func findCargo() throws -> String {
        // Check if cargo is in PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "cargo"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return path
        }
        
        // Try common cargo locations
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(homeDirectory)/.cargo/bin/cargo",
            "/usr/local/bin/cargo",
            "/usr/bin/cargo",
            "/opt/homebrew/bin/cargo"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        throw PluginError.cargoNotFound
    }
}

enum PluginError: Error {
    case cargoNotFound
}
