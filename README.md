# SwiftRage

A Swift 6 wrapper for the Rust implementation of [Age](https://github.com/str4d/rage), a simple, modern, and secure file encryption tool.

## Features

- **x25519 key-based encryption** with support for multiple recipients
- **SSH keys**: encrypt to `ssh-ed25519` and `ssh-rsa` public keys, and decrypt with OpenSSH private keys, including passphrase-protected ones
- **Passphrase-based encryption**, with a configurable scrypt work factor limit
- **ASCII armor format** for safe transmission in text-only channels, and **binary format** for efficient storage
- **Header inspection**: read a file's recipient types and scrypt work factor without decrypting it
- **Distinct errors** for wrong passphrases, missing identities, malformed input and more
- **Streamed file processing** in Rust, so large files are never loaded into memory
- **Swift 6** language mode with strict concurrency; all public types are `Sendable`
- **Documentation** with Swift-DocC
- **Test suite** using Swift Testing

## Requirements

- Swift 6.2+
- macOS 26+ or iOS 26+ (Linux is supported for building and testing)
- Rust (stable, installed with [rustup](https://rustup.rs)) and `cargo` on your `PATH`

## Installation

> [!WARNING]
> SwiftRage can currently only be built from a checkout of this repository, with `swift build` and `swift test`. The Rust library is linked with an unsafe linker flag whose path only matches SwiftPM's own build directory for this package. It is not found when SwiftRage is a dependency of another package or an Xcode project, including as a local package, and SwiftPM doesn't allow unsafe flags in versioned dependencies. The build plugin also only builds the Rust library for the host Mac, not for iOS. There is no tagged release yet. Distributing a prebuilt XCFramework as a binary target would fix all of these.

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

### Building the Rust library for iOS

The Rust FFI library builds for iOS devices and the iOS Simulator:

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

```bash
IPHONEOS_DEPLOYMENT_TARGET=26.0 cargo build --release -p swift-rage-ffi --target aarch64-apple-ios
```

```bash
IPHONEOS_DEPLOYMENT_TARGET=26.0 cargo build --release -p swift-rage-ffi --target aarch64-apple-ios-sim
```

The static libraries are written to `target/<target>/release/libswift_rage_ffi.a`.

## Quick Start

### Encrypting and Decrypting with Keys

```swift
import SwiftRage

// Generate a new identity (private key)
let identity = try AgeIdentity.generate()
print("Identity (keep secret): \(identity.keyData)")

// Get the corresponding recipient (public key)
let info = try identity.info()
print("Recipient (share this): \(info.recipient)") // "age1..."
print("Key type: \(info.keyType)")                 // "age-x25519"

// Encrypt a file
try AgeEncryption.encryptFile(
    inputURL: plaintextURL,
    outputURL: encryptedURL,
    recipients: [identity.toRecipient()],
    armor: true  // Use ASCII armor format
)

// Decrypt the file into a directory of your choice
let decryptedURL = try AgeDecryption.decryptFile(
    inputURL: encryptedURL,
    identities: [identity],
    outputDirectory: destinationDirectory
)
```

Every encryption and decryption method also has a `String` path variant (`inputPath:`, `outputPath:`).

Without an `outputDirectory`, decryption writes to a new file in the temporary directory, which you must delete when done. With one, the plaintext is written to `<outputDirectory>/<input file name>` with a trailing `.age` extension removed, and an existing file there is never overwritten. Decrypted files are readable only by their owner, and partial output is removed if decryption fails.

### Encrypting and Decrypting with Passphrases

```swift
import SwiftRage

let passphrase = "correct horse battery staple"

// Encrypt with a passphrase
try AgeEncryption.encryptFile(
    inputURL: plaintextURL,
    outputURL: encryptedURL,
    passphrase: passphrase,
    armor: false  // Use binary format
)

// Decrypt with the same passphrase
let decryptedURL = try AgeDecryption.decryptFile(
    inputURL: encryptedURL,
    passphrase: passphrase,
    maxWorkFactor: 64  // Optional: accept any scrypt work factor
)
```

By default, age rejects files whose scrypt work factor would take more than about 16 times the work the device does in one second. Use `maxWorkFactor` to set the limit yourself.

### SSH Keys

```swift
import SwiftRage

// Parse an OpenSSH private key (ed25519 or RSA up to 4096 bits)
let sshIdentity = try AgeSSHIdentity.parse(keyText, passphrase: keyPassphrase)
print(sshIdentity.algorithm)   // .ed25519 or .rsa
print(sshIdentity.publicKey)   // "ssh-ed25519 AAAA..."
print(sshIdentity.fingerprint) // "SHA256:..."
// sshIdentity.privateKey is the unencrypted key, with LF line endings

// Encrypt to an SSH public key
try AgeEncryption.encryptFile(
    inputURL: plaintextURL,
    outputURL: encryptedURL,
    recipients: [AgeRecipient.parse(sshIdentity.publicKey)]
)

// Decrypt with any mix of SSH and x25519 identities
let decryptedURL = try AgeDecryption.decryptFile(
    inputURL: encryptedURL,
    identities: [x25519Identity, sshIdentity]
)
```

### Multiple Recipients

```swift
import SwiftRage

let alice = try AgeIdentity.generate()
let bob = try AgeIdentity.generate()

// Encrypt for both recipients
try AgeEncryption.encryptFile(
    inputURL: plaintextURL,
    outputURL: encryptedURL,
    recipients: [alice.toRecipient(), bob.toRecipient()],
    armor: true
)

// Either of them can decrypt the file
let decryptedURL = try AgeDecryption.decryptFile(inputURL: encryptedURL, identities: [bob])
```

### Inspecting Files

```swift
import SwiftRage

let metadata = try AgeFileMetadata.parse(fileURL: encryptedURL)
print(metadata.isArmored)        // true for ASCII-armored files
print(metadata.stanzaTypes)      // e.g. ["X25519"], ["scrypt"], ["ssh-ed25519", "ssh-rsa"]
print(metadata.scryptWorkFactor) // e.g. 18 for passphrase-encrypted files, otherwise nil
```

Parsing reads only the header, and handles binary files and armored files with LF or CRLF line endings.

### Handling Errors

All APIs throw `AgeError`. Its `code` tells failures apart, and its `message` holds the underlying error for logging:

```swift
do {
    let decryptedURL = try AgeDecryption.decryptFile(inputURL: encryptedURL, passphrase: passphrase)
} catch let error as AgeError {
    switch error.code {
    case .wrongPassphrase: askForPassphraseAgain()
    case .encryptedToRecipients: askForIdentity()
    default: logger.error("Decryption failed: \(error.message)")
    }
}
```

| Code | Meaning |
| --- | --- |
| `wrongPassphrase` | The passphrase did not decrypt the file |
| `noMatchingIdentity` | None of the identities could decrypt the file |
| `encryptedWithPassphrase` | The file uses a passphrase, but identities were given |
| `encryptedToRecipients` | The file uses recipients, but a passphrase was given |
| `invalidKey` | A key is invalid or of an unsupported type |
| `invalidRecipient` | A recipient is invalid or of an unsupported type |
| `malformedInput` | The input is not a well-formed age file, binary or armored |
| `excessiveWorkFactor` | The scrypt work factor is above `maxWorkFactor` (or age's default limit) |
| `io` | Reading or writing a file failed, or the output file already exists |
| `encryptionFailed` | Encryption failed for another reason, such as no recipients |
| `sshPassphraseRequired` | The SSH key is encrypted and no passphrase was given |
| `sshWrongPassphrase` | The SSH key's passphrase is wrong |
| `sshUnsupportedAlgorithm` | The SSH key is neither ed25519 nor RSA |
| `sshKeyTooLarge` | The SSH RSA key is larger than 4096 bits |

## Architecture

SwiftRage uses [UniFFI](https://mozilla.github.io/uniffi-rs/) to generate Swift bindings for the Rust [age library](https://github.com/str4d/rage). The FFI interface is defined in `swift-rage-ffi/src/swift_rage.udl` and implemented in `swift-rage-ffi/src/lib.rs`; the public Swift API in `Sources/SwiftRage/SwiftRage.swift` wraps it. The generated bindings are internal to the module.

### Build System

The project uses a Swift Package Manager Build Tool Plugin (`Plugins/RustBuildPlugin`) that automatically:
1. Builds the Rust FFI library (`swift-rage-ffi`) as a static library using Cargo
2. Generates Swift bindings from the UniFFI definition (`swift_rage.udl`)
3. Integrates the generated code into the Swift build process

All of the plugin's output, including Cargo's target directory, goes into the plugin work directory under `.build/plugins/outputs/`, which is the only place a build tool plugin may write to under the SwiftPM sandbox. `Package.swift` adds that directory to the linker search path, because plugins cannot pass libraries to the linker themselves.

The C header for the FFI, `swift-rage-ffi/swift_rageFFI.h`, is checked in because the `SwiftRageFFI` system library target needs it. When the UDL changes, the build fails and prints the path of the regenerated header to copy over the checked-in one.

The plugin runs Cargo with a minimal environment (`PATH`, `HOME` and any `CARGO_HOME`, `RUSTUP_HOME` or `RUSTUP_TOOLCHAIN`). SwiftPM exports its build settings to plugin commands, and `MACOSX_DEPLOYMENT_TARGET` in particular stops rustc from loading proc-macro crates on macOS.

## Testing

Run the tests with:
```bash
swift test
```

The SSH key fixtures and some encrypted files in `Tests/SwiftRageTests/Fixtures` were created with OpenSSH and the [Go age CLI](https://github.com/FiloSottile/age), to test interoperability. The SSH keys' passphrase is `snakeoil`.

## License

This project is licensed under the same terms as the underlying age library.

## Acknowledgments

- [age](https://github.com/str4d/rage) - The Rust implementation of Age
- [UniFFI](https://mozilla.github.io/uniffi-rs/) - The UniFFI binding generator
- [ssh-key](https://github.com/RustCrypto/SSH) - OpenSSH key parsing
- [Swift Testing](https://github.com/swiftlang/swift-testing) - Modern testing framework for Swift
