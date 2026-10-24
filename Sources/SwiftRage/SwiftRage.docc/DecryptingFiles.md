# Decrypting Files

Choose where plaintext is written, handle passphrase work factors, and tell failures apart.

## Overview

``AgeDecryption`` decrypts files with identities or a passphrase. Every method has a `String`
path variant and a `URL` variant, and accepts binary and ASCII-armored files.

### Choose where plaintext is written

By default, decryption writes the plaintext to a new file in the temporary directory and returns
its location. The caller is responsible for deleting it:

```swift
let path = try AgeDecryption.decryptFile(inputPath: encryptedPath, identities: [identity])
defer { try? FileManager.default.removeItem(atPath: path) }
```

Pass an `outputDirectory` to write the plaintext there instead, for example into a directory the
app has security-scoped access to. The file is named after the input file, with a trailing `.age`
extension removed, so `report.pdf.age` decrypts to `report.pdf`:

```swift
let didAccess = destinationDirectory.startAccessingSecurityScopedResource()
defer { if didAccess { destinationDirectory.stopAccessingSecurityScopedResource() } }

let plaintextURL = try AgeDecryption.decryptFile(
    inputURL: encryptedURL,
    identities: [identity],
    outputDirectory: destinationDirectory
)
```

Decryption never overwrites an existing file: if the output file already exists, it fails with
``AgeError/Code/io``. Decrypted files are readable only by their owner, and if decryption fails
partway, the incomplete output file is removed.

### Decrypt with a passphrase

Passphrase-encrypted files use scrypt, whose cost is set by a work factor (log2 of the scrypt N
parameter). By default age rejects files that would take more than about 16 times the work this
device does in one second, which can reject valid files on slower devices. Use `maxWorkFactor`
to set the limit yourself:

```swift
let plaintextURL = try AgeDecryption.decryptFile(
    inputURL: encryptedURL,
    passphrase: passphrase,
    maxWorkFactor: 64 // accept any work factor
)
```

``AgeFileMetadata`` reports a file's work factor without decrypting it, so you can warn before
starting a slow decryption:

```swift
let metadata = try AgeFileMetadata.parse(fileURL: encryptedURL)
if metadata.isPassphraseEncrypted, let workFactor = metadata.scryptWorkFactor, workFactor > 20 {
    // Decryption will take a while
}
```

### Handle errors

Switch on ``AgeError/code`` to respond to each kind of failure:

```swift
do {
    let plaintextURL = try AgeDecryption.decryptFile(inputURL: encryptedURL, passphrase: passphrase)
} catch let error as AgeError {
    switch error.code {
    case .wrongPassphrase:
        askForPassphraseAgain()
    case .encryptedToRecipients:
        askForIdentity()
    case .malformedInput:
        showNotAnAgeFileAlert()
    default:
        logger.error("Decryption failed: \(error.message)")
    }
}
```
