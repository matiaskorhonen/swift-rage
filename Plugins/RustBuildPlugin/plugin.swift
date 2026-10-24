import PackagePlugin
import Foundation

/// Builds the Rust FFI crate and generates the UniFFI Swift bindings.
///
/// Everything is written to the plugin work directory, which is the only location
/// a build tool plugin may write to under the SwiftPM sandbox. The static library
/// ends up in `cargo/release` there; `Package.swift` adds that directory to the
/// linker search path.
@main
struct RustBuildPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let packageDirectory = context.package.directoryURL
        let outputDirectory = context.pluginWorkDirectoryURL
        let cargoTargetDirectory = outputDirectory.appending(path: "cargo")

        // Paths for generated files
        let generatedSwiftFile = outputDirectory.appending(path: "swift_rage.swift")
        let staticLibrary = cargoTargetDirectory.appending(path: "release/libswift_rage_ffi.a")

        // Find cargo executable
        let cargoPath = try findCargo()
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path()

        // Input files for dependency tracking
        let udlFile = packageDirectory.appending(path: "swift-rage-ffi/src/swift_rage.udl")
        let inputFiles = [
            "Cargo.toml",
            "Cargo.lock",
            "swift-rage-ffi/Cargo.toml",
            "swift-rage-ffi/build.rs",
            "swift-rage-ffi/src/lib.rs",
            "swift-rage-ffi/src/swift_rage.udl",
            "bindings-gen/Cargo.toml",
            "bindings-gen/src/main.rs",
            "swift-rage-ffi/swift_rageFFI.h",
        ].map { packageDirectory.appending(path: $0) }

        // Create a build script
        let buildScript = outputDirectory.appending(path: "build-rust.sh")

        // The build runs with a minimal environment: SwiftPM exports its build
        // settings (e.g. MACOSX_DEPLOYMENT_TARGET), which break rustc's loading
        // of proc-macro crates on macOS.
        let scriptContent = """
            #!/bin/bash
            set -e

            # SwiftPM does not pass HOME through, which rustup and cargo need
            export HOME="${HOME:-\(homeDirectory)}"
            export CARGO_TARGET_DIR="\(cargoTargetDirectory.path)"
            CARGO="\(cargoPath)"

            run_cargo() {
                env -i PATH="$PATH" HOME="$HOME" \\
                    ${CARGO_HOME:+CARGO_HOME="$CARGO_HOME"} \\
                    ${RUSTUP_HOME:+RUSTUP_HOME="$RUSTUP_HOME"} \\
                    ${RUSTUP_TOOLCHAIN:+RUSTUP_TOOLCHAIN="$RUSTUP_TOOLCHAIN"} \\
                    CARGO_TARGET_DIR="$CARGO_TARGET_DIR" \\
                    "$CARGO" "$@" || {
                    echo "error: cargo failed. If crates could not be downloaded, run 'cargo fetch' in \(packageDirectory.path) first: the SwiftPM sandbox blocks network access during builds." >&2
                    exit 1
                }
            }

            echo "Building Rust FFI Library..."
            run_cargo build --release --locked --manifest-path "\(packageDirectory.path)/swift-rage-ffi/Cargo.toml"

            echo "Generating Swift Bindings..."
            run_cargo run --release --locked --manifest-path "\(packageDirectory.path)/bindings-gen/Cargo.toml" -- \\
                "\(udlFile.path)" \\
                "\(outputDirectory.path)"

            # Keep the generated FFI layer out of SwiftRage's public API
            sed -E 's/^public /internal /' "\(generatedSwiftFile.path)" > "\(generatedSwiftFile.path).tmp"
            mv "\(generatedSwiftFile.path).tmp" "\(generatedSwiftFile.path)"

            # The SwiftRageFFI system library uses the checked-in copy of the header
            if ! cmp -s "\(outputDirectory.path)/swift_rageFFI.h" "\(packageDirectory.path)/swift-rage-ffi/swift_rageFFI.h"; then
                echo "error: swift-rage-ffi/swift_rageFFI.h is out of date. Replace it with \(outputDirectory.path)/swift_rageFFI.h" >&2
                exit 1
            fi

            echo "Rust build complete!"
            """

        try scriptContent.write(to: buildScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: buildScript.path)

        return [
            .buildCommand(
                displayName: "Building Rust FFI and Generating Swift Bindings",
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: [buildScript.path],
                inputFiles: inputFiles,
                outputFiles: [
                    generatedSwiftFile,
                    staticLibrary,
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
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path()

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

enum PluginError: Error, CustomStringConvertible {
    case cargoNotFound

    var description: String {
        switch self {
        case .cargoNotFound:
            return "cargo not found. Install Rust from https://rustup.rs to build SwiftRage."
        }
    }
}
