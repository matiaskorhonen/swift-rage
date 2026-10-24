import Foundation
import Testing
import SwiftRage

/// Tests for passphrase encryption and decryption.
@Suite("Encryption and Decryption with Passphrase")
struct PassphraseEncryptionTests {
    let plaintext = "This message is protected by a passphrase."
    let passphrase = "correct horse battery staple"

    @Test("Round trip with a passphrase", arguments: [false, true])
    func roundTrip(armor: Bool) throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(plaintext, to: "input.txt")
        let encrypted = directory.file("encrypted.age")

        try AgeEncryption.encryptFile(
            inputPath: input.path(percentEncoded: false),
            outputPath: encrypted.path(percentEncoded: false),
            passphrase: passphrase,
            armor: armor
        )

        let metadata = try AgeFileMetadata.parse(fileURL: encrypted)
        #expect(metadata.isArmored == armor)
        #expect(metadata.isPassphraseEncrypted)

        let decryptedPath = try AgeDecryption.decryptFile(
            inputPath: encrypted.path(percentEncoded: false),
            passphrase: passphrase
        )
        defer { try? FileManager.default.removeItem(atPath: decryptedPath) }

        #expect(try String(contentsOfFile: decryptedPath, encoding: .utf8) == plaintext)
    }

    @Test("Round trip with URL overloads", arguments: [false, true])
    func roundTripURLs(armor: Bool) throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write(plaintext, to: "input.txt")
        let encrypted = directory.file("encrypted.age")

        try AgeEncryption.encryptFile(inputURL: input, outputURL: encrypted, passphrase: passphrase, armor: armor)
        let decrypted = try AgeDecryption.decryptFile(
            inputURL: encrypted,
            passphrase: passphrase,
            outputDirectory: directory.file("out").creatingDirectory()
        )

        #expect(try String(contentsOf: decrypted, encoding: .utf8) == plaintext)
    }

    @Test("Decrypt a file encrypted by the age CLI")
    func decryptScryptVector() throws {
        let output = try TemporaryDirectory()
        let decrypted = try AgeDecryption.decryptFile(
            inputURL: Fixtures.url("scrypt.age.txt"),
            passphrase: Fixtures.scryptVectorPassphrase,
            outputDirectory: output.url
        )

        #expect(try String(contentsOf: decrypted, encoding: .utf8) == "Hello\n")
    }

    @Test("Maximum work factor is enforced")
    func maxWorkFactor() throws {
        // scrypt.age.txt uses work factor 18
        for maxWorkFactor: UInt8 in [18, 64] {
            let decrypted = try AgeDecryption.decryptFile(
                inputURL: Fixtures.url("scrypt.age.txt"),
                passphrase: Fixtures.scryptVectorPassphrase,
                maxWorkFactor: maxWorkFactor
            )
            try FileManager.default.removeItem(at: decrypted)
        }

        expectAgeError(.excessiveWorkFactor) {
            try AgeDecryption.decryptFile(
                inputURL: Fixtures.url("scrypt.age.txt"),
                passphrase: Fixtures.scryptVectorPassphrase,
                maxWorkFactor: 17
            )
        }
    }

    @Test("Wrong passphrase throws wrongPassphrase and leaves no output")
    func wrongPassphrase() throws {
        let directory = try TemporaryDirectory()

        expectAgeError(.wrongPassphrase) {
            try AgeDecryption.decryptFile(
                inputURL: Fixtures.url("scrypt.age.txt"),
                passphrase: "wrong passphrase",
                outputDirectory: directory.url
            )
        }
        #expect(try directory.contents().isEmpty)
    }

    @Test("Recipient-encrypted file with a passphrase throws encryptedToRecipients")
    func recipientFileWithPassphrase() {
        for file in ["x25519.age.txt", "ssh-ed25519.age"] {
            expectAgeError(.encryptedToRecipients) {
                try AgeDecryption.decryptFile(inputURL: Fixtures.url(file), passphrase: passphrase)
            }
        }
    }

    @Test("Non-age input throws malformedInput")
    func malformedInput() throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write("age-encryption.org/v1\n-> scrypt\n", to: "truncated.age")

        expectAgeError(.malformedInput) {
            try AgeDecryption.decryptFile(inputURL: input, passphrase: passphrase)
        }
    }
}

/// Tests for where decrypted files are written.
@Suite("Decryption Output Location")
struct DecryptionOutputTests {
    @Test("Without an output directory, decrypt to a new temporary file")
    func temporaryDirectory() throws {
        let path = try AgeDecryption.decryptFile(
            inputPath: Fixtures.path("scrypt.age.txt"),
            passphrase: Fixtures.scryptVectorPassphrase
        )
        defer { try? FileManager.default.removeItem(atPath: path) }

        let temporaryDirectory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        let parent = URL(filePath: path).deletingLastPathComponent().resolvingSymlinksInPath()
        #expect(parent.path() == temporaryDirectory.path())
    }

    @Test("With an output directory, decrypt to the input name without .age", arguments: [
        ("report.pdf.age", "report.pdf"),
        ("NOTES.AGE", "NOTES"),
        ("message.txt", "message.txt"),
        (".age", ".age"),
    ])
    func outputName(inputName: String, outputName: String) throws {
        let directory = try TemporaryDirectory()
        let input = directory.file(inputName)
        try FileManager.default.copyItem(at: Fixtures.url("x25519.age.txt"), to: input)
        let output = directory.file("output").creatingDirectory()
        let identity = try AgeIdentity.parse(Fixtures.x25519VectorIdentity)

        let decrypted = try AgeDecryption.decryptFile(inputURL: input, identities: [identity], outputDirectory: output)

        #expect(decrypted.lastPathComponent == outputName)
        #expect(decrypted.deletingLastPathComponent().standardizedFileURL == output.standardizedFileURL)
        #expect(try String(contentsOf: decrypted, encoding: .utf8) == "World\n")
    }

    @Test("String-path overloads accept an output directory")
    func stringPathOutputDirectory() throws {
        let directory = try TemporaryDirectory()

        let path = try AgeDecryption.decryptFile(
            inputPath: Fixtures.path("x25519.age.txt"),
            identities: [AgeIdentity.parse(Fixtures.x25519VectorIdentity)],
            outputDirectory: directory.url
        )

        #expect(path == directory.file("x25519.age.txt").path(percentEncoded: false))
    }

    @Test("Existing output files are not overwritten")
    func existingOutput() throws {
        let directory = try TemporaryDirectory()
        let existing = try directory.write("keep me", to: "scrypt.age.txt")

        expectAgeError(.io) {
            try AgeDecryption.decryptFile(
                inputURL: Fixtures.url("scrypt.age.txt"),
                passphrase: Fixtures.scryptVectorPassphrase,
                outputDirectory: directory.url
            )
        }
        #expect(try String(contentsOf: existing, encoding: .utf8) == "keep me")
    }

    @Test("Missing output directory throws io")
    func missingOutputDirectory() throws {
        let directory = try TemporaryDirectory()

        expectAgeError(.io) {
            try AgeDecryption.decryptFile(
                inputURL: Fixtures.url("scrypt.age.txt"),
                passphrase: Fixtures.scryptVectorPassphrase,
                outputDirectory: directory.file("missing")
            )
        }
    }

    @Test("Decrypted files are readable only by the owner")
    func permissions() throws {
        let directory = try TemporaryDirectory()

        let decrypted = try AgeDecryption.decryptFile(
            inputURL: Fixtures.url("scrypt.age.txt"),
            passphrase: Fixtures.scryptVectorPassphrase,
            outputDirectory: directory.url
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: decrypted.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }
}
