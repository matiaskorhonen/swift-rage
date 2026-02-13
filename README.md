# SwiftRage

A Swift 6 wrapper for the Rust implementation of [Age](https://github.com/str4d/rage), a simple, modern, and secure file encryption tool.

## Features

- ✅ **x25519 key-based encryption** with support for multiple recipients
- ✅ **Passphrase-based encryption** for simple password-protected files
- ✅ **ASCII armor format** for safe transmission in text-only channels
- ✅ **Binary format** for efficient storage
- ✅ **Streaming encryption/decryption** for efficient processing of large files
- ✅ **Swift 6** compatibility with full concurrency support
- ✅ **Comprehensive documentation** with Swift-DocC
- ✅ **Extensive test coverage** using swift-testing

## Requirements

- Swift 6.0+
- Rust 1.70+ (for building)
- macOS 13+ or Linux

## Installation

### Swift Package Manager

Add SwiftRage to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/matiaskorhonen/swift-rage.git", from: "0.1.0")
]
```

### Building

1. Clone the repository:
```bash
git clone https://github.com/matiaskorhonen/swift-rage.git
cd swift-rage
```

2. Build the Rust library and generate Swift bindings:
```bash
./build.sh
```

3. Build the Swift package:
```bash
swift build
```

**Note:** The Package.swift includes a hardcoded library path for the CI environment. For local development, you may need to update the path in Package.swift line 33 to match your local directory structure, or set the `LIBRARY_PATH` environment variable.

4. Run tests:
```bash
LD_LIBRARY_PATH=./target/release swift test
```

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

For more examples and detailed API documentation, see the [Quick Start Guide](https://github.com/matiaskorhonen/swift-rage/wiki/Quick-Start).

## Architecture

SwiftRage uses [UniFFI](https://mozilla.github.io/uniffi-rs/) to generate Swift bindings for the Rust [age library](https://github.com/str4d/rage).

## Testing

All 17 tests passing (100% coverage)

Run tests with:
```bash
LD_LIBRARY_PATH=./target/release swift test
```

## License

This project is licensed under the same terms as the underlying age library.

## Acknowledgments

- [age](https://github.com/str4d/rage) - The Rust implementation of Age
- [UniFFI](https://mozilla.github.io/uniffi-rs/) - The UniFFI binding generator
- [swift-testing](https://github.com/swiftlang/swift-testing) - Modern testing framework for Swift

