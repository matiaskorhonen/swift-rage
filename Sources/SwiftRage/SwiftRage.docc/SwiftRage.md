# ``SwiftRage``

Encrypt and decrypt files in the age format, with x25519 keys, SSH keys or passphrases.

## Overview

SwiftRage wraps the Rust implementation of [age](https://age-encryption.org), a simple, modern
and secure file encryption format. It reads and writes both binary and ASCII-armored age files,
and streams file contents, so large files are never loaded into memory.

```swift
import SwiftRage

let identity = try AgeIdentity.generate()

try AgeEncryption.encryptFile(
    inputURL: plaintextURL,
    outputURL: encryptedURL,
    recipients: [identity.toRecipient()],
    armor: true
)

let decryptedURL = try AgeDecryption.decryptFile(
    inputURL: encryptedURL,
    identities: [identity],
    outputDirectory: destinationDirectory
)
```

All APIs throw ``AgeError``. Its ``AgeError/code`` tells failures apart, such as a wrong
passphrase or a file that is not an age file, and its ``AgeError/message`` holds the underlying
error message for logging.

All public types are `Sendable`.

## Topics

### Essentials

- <doc:DecryptingFiles>
- <doc:UsingSSHKeys>

### Keys

- ``AgeIdentity``
- ``AgeIdentityInfo``
- ``AgeSSHIdentity``
- ``AgeDecryptionIdentity``
- ``AgeRecipient``

### Encrypting and Decrypting

- ``AgeEncryption``
- ``AgeDecryption``
- ``EncryptionOptions``

### Inspecting Files

- ``AgeFileMetadata``

### Errors

- ``AgeError``
