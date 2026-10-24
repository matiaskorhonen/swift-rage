# SwiftRage

A Swift 6 wrapper for the Rust implementation of [Age](https://github.com/str4d/rage), a simple, modern, and secure file encryption tool.

## Features

- **x25519 key-based encryption** with support for multiple recipients
- **Passphrase-based encryption** for simple password-protected files
- **ASCII armor format** for safe transmission in text-only channels
- **Binary format** for efficient storage
- **Streamed file processing** in Rust, so large files are never loaded into memory
- **Swift 6** compatibility with full concurrency support
- **Comprehensive documentation** with Swift-DocC
- **Test suite** using Swift Testing

## Requirements

- Swift 6.0+
- Rust (stable, installed with [rustup](https://rustup.rs)) and `cargo` on your `PATH`
- macOS 13+ or Linux

## Installation

> [!WARNING]
> SwiftRage can currently only be built from a checkout of this repository. It does not yet work as a dependency of another package. The Rust library is linked with an unsafe linker flag, which SwiftPM does not allow for versioned dependencies, and the flag's path only matches when this package is the root package. There is no tagged release yet. Distributing a prebuilt binary target would fix both problems.

### Building

SwiftRage uses a Swift Package Manager Build Tool Plugin to automatically build the Rust FFI library and generate Swift bindings during the build process.

1. Clone the repository:
```bash
git clone https://github.com/matiaskorhonen/swift-rage.git
cd swift-rage
```

2. Download the Rust dependencies (needed once, and again after the Rust dependencies change):
```bash
cargo fetch
```

The SwiftPM sandbox blocks network access during builds, so the build plugin can only use crates that are already in the cargo cache.

3. Build the Swift package (this will automatically build Rust and generate bindings):
```bash
swift build
```

4. Run tests:
```bash
swift test
```

The first build compiles the Rust crates and takes a minute or two; later builds reuse them.

If you build with a custom `--scratch-path`, set `SWIFT_RAGE_LIB_DIR` to `<scratch-path>/plugins/outputs/<package-directory-name>/SwiftRage/destination/RustBuildPlugin/cargo/release` so the linker can find the Rust library.

## Quick Start

### Encrypting and Decrypting with Keys

```swift
import SwiftRage

// Generate a new identity (private key)
let identity = try AgeIdentity.generate()
print("Identity (keep secret): \(identity.keyData)")

// Get the corresponding recipient (public key)
let recipient = try identity.toRecipient()
print("Recipient (share this): \(recipient.keyData)")

// Encrypt a file
try AgeEncryption.encryptFile(
    inputPath: "/path/to/secret.txt",
    outputPath: "/path/to/secret.age",
    recipients: [recipient],
    armor: true  // Use ASCII armor format
)

// Decrypt the file
let decryptedPath = try AgeDecryption.decryptFile(
    inputPath: "/path/to/secret.age",
    identities: [identity]
)

// Read the decrypted content
let content = try String(contentsOfFile: decryptedPath, encoding: .utf8)
print("Decrypted content: \(content)")

// Clean up the temporary file
try FileManager.default.removeItem(atPath: decryptedPath)
```

### Encrypting and Decrypting with Passphrases

```swift
import SwiftRage

let passphrase = "correct horse battery staple"

// Encrypt with a passphrase
try AgeEncryption.encryptFile(
    inputPath: "/path/to/secret.txt",
    outputPath: "/path/to/secret.age",
    passphrase: passphrase,
    armor: false  // Use binary format
)

// Decrypt with the same passphrase
let decryptedPath = try AgeDecryption.decryptFile(
    inputPath: "/path/to/secret.age",
    passphrase: passphrase
)

// Use the decrypted file...
let content = try String(contentsOfFile: decryptedPath, encoding: .utf8)

// Clean up
try FileManager.default.removeItem(atPath: decryptedPath)
```

### Multiple Recipients

```swift
import SwiftRage

// Generate identities for three people
let alice = try AgeIdentity.generate()
let bob = try AgeIdentity.generate()
let charlie = try AgeIdentity.generate()

// Get their recipients
let aliceRecipient = try alice.toRecipient()
let bobRecipient = try bob.toRecipient()
let charlieRecipient = try charlie.toRecipient()

// Encrypt for all three recipients
try AgeEncryption.encryptFile(
    inputPath: "/path/to/secret.txt",
    outputPath: "/path/to/secret.age",
    recipients: [aliceRecipient, bobRecipient, charlieRecipient],
    armor: true
)

// Any of them can decrypt the file
let decryptedPath = try AgeDecryption.decryptFile(
    inputPath: "/path/to/secret.age",
    identities: [bob]  // Bob can decrypt it
)
```

## Architecture

SwiftRage uses [UniFFI](https://mozilla.github.io/uniffi-rs/) to generate Swift bindings for the Rust [age library](https://github.com/str4d/rage).

### Build System

The project uses a Swift Package Manager Build Tool Plugin (`Plugins/RustBuildPlugin`) that automatically:
1. Builds the Rust FFI library (`swift-rage-ffi`) as a static library using Cargo
2. Generates Swift bindings from the UniFFI definition (`swift_rage.udl`)
3. Integrates the generated code into the Swift build process

All of the plugin's output, including Cargo's target directory, goes into the plugin work directory under `.build/plugins/outputs/`, which is the only place a build tool plugin may write to under the SwiftPM sandbox. `Package.swift` adds that directory to the linker search path, because plugins cannot pass libraries to the linker themselves.

The plugin runs Cargo with a minimal environment (`PATH`, `HOME` and any `CARGO_HOME`, `RUSTUP_HOME` or `RUSTUP_TOOLCHAIN`). SwiftPM exports its build settings to plugin commands, and `MACOSX_DEPLOYMENT_TARGET` in particular stops rustc from loading proc-macro crates on macOS.

## Testing

Run the tests with:
```bash
swift test
```

## License

This project is licensed under the same terms as the underlying age library.

## Acknowledgments

- [age](https://github.com/str4d/rage) - The Rust implementation of Age
- [UniFFI](https://mozilla.github.io/uniffi-rs/) - The UniFFI binding generator
- [swift-testing](https://github.com/swiftlang/swift-testing) - Modern testing framework for Swift

