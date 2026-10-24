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
- macOS 26+ or iOS 26+

The Rust library ships as a prebuilt XCFramework, so you don't need Rust to use SwiftRage.

## Installation

Add SwiftRage to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/matiaskorhonen/swift-rage.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [.product(name: "SwiftRage", package: "swift-rage")]
    ),
]
```

In Xcode, choose **File > Add Package Dependencies…** and enter `https://github.com/matiaskorhonen/swift-rage.git`.

SwiftPM downloads the XCFramework (about 30 MB) from the GitHub release that matches the version.

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

SwiftRage uses [UniFFI](https://mozilla.github.io/uniffi-rs/) to generate Swift bindings for the Rust [age library](https://github.com/str4d/rage). The FFI interface is defined in `swift-rage-ffi/src/swift_rage.udl` and implemented in `swift-rage-ffi/src/lib.rs`; the public Swift API in `Sources/SwiftRage/SwiftRage.swift` wraps it.

The UniFFI bindings in `Sources/SwiftRage/Generated/swift_rage.swift` are generated, and checked in so that SwiftRage builds without Rust. Their declarations are made `internal` so that they stay out of SwiftRage's public API.

## Development

Working on SwiftRage itself needs Rust (stable, installed with [rustup](https://rustup.rs)) and Xcode.

### Building the XCFramework

```bash
scripts/build-xcframework.sh
```

The script:
1. Builds `swift-rage-ffi` as a static library for macOS (arm64 and x86_64), iOS (arm64) and the iOS Simulator (arm64 and x86_64), installing missing Rust targets with rustup
2. Regenerates the Swift bindings in `Sources/SwiftRage/Generated`
3. Combines the libraries, with the C header and modulemap, into `build/SwiftRageFFI.xcframework`
4. Zips it into `build/SwiftRageFFI.xcframework.zip` and prints the zip's checksum

Cargo runs with a minimal environment (`PATH`, `HOME` and any `CARGO_HOME`, `RUSTUP_HOME` or `RUSTUP_TOOLCHAIN`), because build settings like `MACOSX_DEPLOYMENT_TARGET` stop rustc from loading proc-macro crates on macOS.

By default, `Package.swift` uses the XCFramework from the release in `ffiReleaseURL`. Set `SWIFT_RAGE_LOCAL_FFI` to use the one in `build/` instead:

```bash
SWIFT_RAGE_LOCAL_FFI=1 swift test
```

Do this after any change to the Rust code or the UDL, and commit the regenerated bindings with it: UniFFI checks at runtime that the bindings match the library. CI fails if the committed bindings are out of date.

### Releasing

`Package.swift` must contain the checksum of the release's XCFramework zip before the release is tagged, so releasing takes two steps:

1. Run the **Release** workflow from the Actions tab (or `gh workflow run release.yml -f version=0.2.0`). It builds the XCFramework, runs the tests, attaches the zip to a draft release for that version, and prints the `ffiReleaseURL` and `ffiReleaseChecksum` lines for `Package.swift` in the run summary.
2. Update those two lines in `Package.swift`, commit, and push a tag with the version (e.g. `0.2.0`). The tag build checks that the URL and checksum match the draft release's zip, publishes the release, and runs the tests against the published XCFramework.

If the Rust code changes after step 1, run the workflow again: it replaces the draft's zip.

## Testing

Run the tests with:
```bash
swift test
```

Add `SWIFT_RAGE_LOCAL_FFI=1` to test against a local build of the XCFramework.

The SSH key fixtures and some encrypted files in `Tests/SwiftRageTests/Fixtures` were created with OpenSSH and the [Go age CLI](https://github.com/FiloSottile/age), to test interoperability. The SSH keys' passphrase is `snakeoil`.

## License

This project is licensed under the same terms as the underlying age library.

## Acknowledgments

- [age](https://github.com/str4d/rage) - The Rust implementation of Age
- [UniFFI](https://mozilla.github.io/uniffi-rs/) - The UniFFI binding generator
- [ssh-key](https://github.com/RustCrypto/SSH) - OpenSSH key parsing
- [Swift Testing](https://github.com/swiftlang/swift-testing) - Modern testing framework for Swift
