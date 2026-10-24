import Foundation
import Testing
import SwiftRage

/// Tests for encrypting to and decrypting with x25519 and SSH keys.
@Suite("Encryption and Decryption with Recipients")
struct RecipientEncryptionTests {
    let plaintext = "Hello, SwiftRage! This is a secret message."

    @Test("Round trip with a single x25519 recipient", arguments: [false, true])
    func roundTrip(armor: Bool) throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(plaintext, to: "input.txt")
        let encrypted = directory.file("encrypted.age")
        let identity = try AgeIdentity.generate()

        try AgeEncryption.encryptFile(
            inputPath: input.path(percentEncoded: false),
            outputPath: encrypted.path(percentEncoded: false),
            recipients: [identity.toRecipient()],
            armor: armor
        )

        let metadata = try AgeFileMetadata.parse(fileURL: encrypted)
        #expect(metadata.isArmored == armor)

        let decryptedPath = try AgeDecryption.decryptFile(
            inputPath: encrypted.path(percentEncoded: false),
            identities: [identity]
        )
        defer { try? FileManager.default.removeItem(atPath: decryptedPath) }

        #expect(try String(contentsOfFile: decryptedPath, encoding: .utf8) == plaintext)
    }

    @Test("Round trip with URL overloads", arguments: [false, true])
    func roundTripURLs(armor: Bool) throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(plaintext, to: "input.txt")
        let encrypted = directory.file("encrypted.age")
        let identity = try AgeIdentity.generate()

        try AgeEncryption.encryptFile(
            inputURL: input,
            outputURL: encrypted,
            recipients: [identity.toRecipient()],
            armor: armor
        )
        let decrypted = try AgeDecryption.decryptFile(inputURL: encrypted, identities: [identity])
        defer { try? FileManager.default.removeItem(at: decrypted) }

        #expect(decrypted.isFileURL)
        #expect(try String(contentsOf: decrypted, encoding: .utf8) == plaintext)
    }

    @Test("Any of several recipients can decrypt")
    func multipleRecipients() throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(plaintext, to: "input.txt")
        let encrypted = directory.file("encrypted.age")
        let identities = try (0..<3).map { _ in try AgeIdentity.generate() }

        try AgeEncryption.encryptFile(
            inputURL: input,
            outputURL: encrypted,
            recipients: identities.map { try $0.toRecipient() },
            armor: true
        )

        for identity in identities {
            let output = try TemporaryDirectory()
            let decrypted = try AgeDecryption.decryptFile(
                inputURL: encrypted,
                identities: [identity],
                outputDirectory: output.url
            )
            #expect(try String(contentsOf: decrypted, encoding: .utf8) == plaintext)
        }
    }

    @Test("Round trip with SSH recipients", arguments: ["ed25519", "rsa2048"])
    func sshRoundTrip(keyName: String) throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(plaintext, to: "input.txt")
        let encrypted = directory.file("encrypted.age")
        let sshIdentity = try AgeSSHIdentity.parse(Fixtures.string(keyName))

        try AgeEncryption.encryptFile(
            inputURL: input,
            outputURL: encrypted,
            recipients: [AgeRecipient.parse(sshIdentity.publicKey)]
        )

        let metadata = try AgeFileMetadata.parse(fileURL: encrypted)
        #expect(metadata.stanzaTypes == [sshIdentity.algorithm.rawValue])

        let decrypted = try AgeDecryption.decryptFile(
            inputURL: encrypted,
            identities: [sshIdentity],
            outputDirectory: directory.url
        )
        #expect(try String(contentsOf: decrypted, encoding: .utf8) == plaintext)
    }

    @Test("Decrypt files encrypted to SSH keys by the age CLI", arguments: [
        ("ssh-ed25519.age", "ed25519", nil),
        ("ssh-rsa.age.txt", "rsa2048", nil),
        ("ssh-rsa-passphrase-key.age", "rsa2048WithPassphrase", Fixtures.sshKeyPassphrase),
        ("ssh-ed25519-passphrase-key.age", "ed25519WithPassphrase", Fixtures.sshKeyPassphrase),
    ] as [(String, String, String?)])
    func decryptSSHFixtures(file: String, keyName: String, passphrase: String?) throws {
        let sshIdentity = try AgeSSHIdentity.parse(Fixtures.string(keyName), passphrase: passphrase)
        let directory = try TemporaryDirectory()

        let decrypted = try AgeDecryption.decryptFile(
            inputURL: Fixtures.url(file),
            identities: [sshIdentity],
            outputDirectory: directory.url
        )

        #expect(try String(contentsOf: decrypted, encoding: .utf8) == Fixtures.agePlaintext)
    }

    @Test("Decrypt with mixed x25519 and SSH identities")
    func mixedIdentities() throws {
        let directory = try TemporaryDirectory()
        let unrelated = try AgeIdentity.generate()
        let x25519 = try AgeIdentity.parse(Fixtures.string("x25519-identity.txt"))
        let ed25519 = try AgeSSHIdentity.parse(Fixtures.string("ed25519"))
        let rsa = try AgeSSHIdentity.parse(Fixtures.string("rsa2048"))

        // The x25519 identity is not a recipient of this file; the SSH one is
        let fromSSH = try AgeDecryption.decryptFile(
            inputURL: Fixtures.url("ssh-ed25519.age"),
            identities: [unrelated, ed25519],
            outputDirectory: directory.file("ssh").creatingDirectory()
        )
        #expect(try String(contentsOf: fromSSH, encoding: .utf8) == Fixtures.agePlaintext)

        // A file encrypted to an x25519 and two SSH recipients
        for identities in [[x25519, rsa], [rsa, unrelated], [ed25519]] as [[any AgeDecryptionIdentity]] {
            let decrypted = try AgeDecryption.decryptFile(
                inputURL: Fixtures.url("multi-recipient.age.txt"),
                identities: identities,
                outputDirectory: directory.file(UUID().uuidString).creatingDirectory()
            )
            #expect(try String(contentsOf: decrypted, encoding: .utf8) == Fixtures.agePlaintext)
        }
    }

    @Test("Decrypt a file encrypted by the age CLI, with LF and CRLF armor", arguments: ["x25519.age.txt", "x25519-crlf.age.txt"])
    func decryptX25519Vector(file: String) throws {
        let identity = try AgeIdentity.parse(Fixtures.x25519VectorIdentity)
        let output = try TemporaryDirectory()

        let decrypted = try AgeDecryption.decryptFile(
            inputURL: Fixtures.url(file),
            identities: [identity],
            outputDirectory: output.url
        )

        #expect(try String(contentsOf: decrypted, encoding: .utf8) == "World\n")
    }

    @Test("Wrong identity throws noMatchingIdentity")
    func wrongIdentity() throws {
        let unrelated = try AgeIdentity.generate()
        let ed25519 = try AgeSSHIdentity.parse(Fixtures.string("ed25519"))

        expectAgeError(.noMatchingIdentity) {
            try AgeDecryption.decryptFile(inputURL: Fixtures.url("x25519.age.txt"), identities: [unrelated, ed25519])
        }
        expectAgeError(.noMatchingIdentity) {
            try AgeDecryption.decryptFile(inputURL: Fixtures.url("ssh-rsa.age.txt"), identities: [ed25519])
        }
    }

    @Test("No identities throws noMatchingIdentity")
    func noIdentities() {
        expectAgeError(.noMatchingIdentity) {
            try AgeDecryption.decryptFile(inputURL: Fixtures.url("x25519.age.txt"), identities: [])
        }
    }

    @Test("No recipients throws encryptionFailed")
    func noRecipients() throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(plaintext, to: "input.txt")

        expectAgeError(.encryptionFailed) {
            try AgeEncryption.encryptFile(inputURL: input, outputURL: directory.file("out.age"), recipients: [])
        }
    }

    @Test("Passphrase-encrypted file with identities throws encryptedWithPassphrase")
    func passphraseFileWithIdentities() throws {
        let identity = try AgeIdentity.generate()

        expectAgeError(.encryptedWithPassphrase) {
            try AgeDecryption.decryptFile(inputURL: Fixtures.url("scrypt.age.txt"), identities: [identity])
        }
    }

    @Test("Non-age input throws malformedInput")
    func malformedInput() throws {
        let directory = try TemporaryDirectory()
        let identity = try AgeIdentity.generate()
        let inputs = [
            try directory.write("This is not an age file, it is just some text that is long enough.", to: "text"),
            try directory.write("-----BEGIN AGE ENCRYPTED FILE-----\nnot base64!\n-----END AGE ENCRYPTED FILE-----\n", to: "armor"),
            try directory.write("", to: "empty"),
        ]

        for input in inputs {
            expectAgeError(.malformedInput) {
                try AgeDecryption.decryptFile(inputURL: input, identities: [identity])
            }
        }
    }

    @Test("Truncated ciphertext throws malformedInput and leaves no output")
    func truncatedCiphertext() throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(String(repeating: "secret ", count: 20_000), to: "input.txt")
        let encrypted = directory.file("encrypted.age")
        let identity = try AgeIdentity.generate()
        try AgeEncryption.encryptFile(inputURL: input, outputURL: encrypted, recipients: [identity.toRecipient()])

        let data = try Data(contentsOf: encrypted)
        try data.prefix(data.count - 100).write(to: encrypted)
        let output = directory.file("output").creatingDirectory()

        expectAgeError(.malformedInput) {
            try AgeDecryption.decryptFile(inputURL: encrypted, identities: [identity], outputDirectory: output)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: output.path(percentEncoded: false)).isEmpty)
    }

    @Test("Encrypted SSH keys are rejected as identities")
    func encryptedSSHKeyIdentity() throws {
        struct RawIdentity: AgeDecryptionIdentity {
            let identityString: String
        }
        let encryptedKey = RawIdentity(identityString: try Fixtures.string("ed25519WithPassphrase"))

        expectAgeError(.invalidKey) {
            try AgeDecryption.decryptFile(inputURL: Fixtures.url("ssh-ed25519.age"), identities: [encryptedKey])
        }
        expectAgeError(.invalidKey) {
            try AgeDecryption.decryptFile(
                inputURL: Fixtures.url("ssh-ed25519.age"),
                identities: [RawIdentity(identityString: "not a key")]
            )
        }
    }

    @Test("Missing input file throws io")
    func missingInput() throws {
        let directory = try TemporaryDirectory()
        let identity = try AgeIdentity.generate()

        expectAgeError(.io) {
            try AgeDecryption.decryptFile(inputURL: directory.file("missing.age"), identities: [identity])
        }
        expectAgeError(.io) {
            try AgeEncryption.encryptFile(
                inputURL: directory.file("missing.txt"),
                outputURL: directory.file("out.age"),
                recipients: [identity.toRecipient()]
            )
        }
    }

    @Test("Non-file URLs throw io")
    func nonFileURL() throws {
        let identity = try AgeIdentity.generate()
        let webURL = try #require(URL(string: "https://example.com/file.age"))

        expectAgeError(.io) { try AgeDecryption.decryptFile(inputURL: webURL, identities: [identity]) }
        expectAgeError(.io) { try AgeFileMetadata.parse(fileURL: webURL) }
    }

    @Test("Encrypt and decrypt a large file")
    func largeFile() throws {
        let directory = try TemporaryDirectory()
        let input = directory.file("large.bin")
        let encrypted = directory.file("large.age")
        let bytes = Data((0..<(5 * 1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try bytes.write(to: input)
        let identity = try AgeIdentity.generate()

        try AgeEncryption.encryptFile(inputURL: input, outputURL: encrypted, recipients: [identity.toRecipient()])
        let decrypted = try AgeDecryption.decryptFile(
            inputURL: encrypted,
            identities: [identity],
            outputDirectory: directory.file("out").creatingDirectory()
        )

        #expect(try Data(contentsOf: decrypted) == bytes)
    }
}

extension URL {
    /// Creates this directory and returns it.
    func creatingDirectory() -> URL {
        try? FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
