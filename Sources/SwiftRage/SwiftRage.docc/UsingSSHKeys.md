# Using SSH Keys

Decrypt files encrypted to SSH keys, and encrypt files to SSH public keys.

## Overview

age can encrypt files to `ssh-ed25519` and `ssh-rsa` public keys, and decrypt them with the
matching OpenSSH private key. SwiftRage supports Ed25519 keys and RSA keys of up to 4096 bits.

### Parse a private key

``AgeSSHIdentity/parse(_:passphrase:)`` reads an OpenSSH private key, decrypting it if it is
protected by a passphrase:

```swift
do {
    let identity = try AgeSSHIdentity.parse(keyText, passphrase: passphrase)
    print(identity.algorithm)   // .ed25519 or .rsa
    print(identity.publicKey)   // "ssh-ed25519 AAAA... comment"
    print(identity.fingerprint) // "SHA256:..."
} catch let error as AgeError where error.code == .sshPassphraseRequired {
    // Ask for the key's passphrase
}
```

The parsed identity's ``AgeSSHIdentity/privateKey`` is always the unencrypted key, with LF line
endings, so it can be stored and parsed again later without the passphrase. Keep it secret.

Parsing fails with:

- ``AgeError/Code/sshPassphraseRequired`` if the key is encrypted and no passphrase was given,
- ``AgeError/Code/sshWrongPassphrase`` if the passphrase is wrong,
- ``AgeError/Code/sshUnsupportedAlgorithm`` for other key types, such as ECDSA,
- ``AgeError/Code/sshKeyTooLarge`` for RSA keys over 4096 bits,
- ``AgeError/Code/invalidKey`` if the text is not an OpenSSH private key.

### Decrypt with SSH and x25519 identities

Both ``AgeIdentity`` and ``AgeSSHIdentity`` conform to ``AgeDecryptionIdentity``, so you can pass
any mix of them to ``AgeDecryption``. age tries each identity against the file's recipients:

```swift
let plaintextURL = try AgeDecryption.decryptFile(
    inputURL: encryptedURL,
    identities: [x25519Identity, sshIdentity]
)
```

### Encrypt to an SSH public key

``AgeRecipient/parse(_:)`` accepts SSH public keys as well as `age1...` recipients:

```swift
let recipient = try AgeRecipient.parse("ssh-ed25519 AAAA... alice@example.com")
try AgeEncryption.encryptFile(inputURL: plaintextURL, outputURL: encryptedURL, recipients: [recipient])
```
