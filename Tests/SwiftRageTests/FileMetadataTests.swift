import Foundation
import Testing
import SwiftRage

/// Tests for reading age file headers.
@Suite("File Metadata Tests")
struct FileMetadataTests {
    @Test("scrypt header reports the work factor")
    func scrypt() throws {
        let metadata = try AgeFileMetadata.parse(filePath: Fixtures.path("scrypt.age.txt"))

        #expect(metadata.isArmored)
        #expect(metadata.stanzaTypes == ["scrypt"])
        #expect(metadata.scryptWorkFactor == 18)
        #expect(metadata.isPassphraseEncrypted)
    }

    @Test("X25519 header, with LF and CRLF armor", arguments: ["x25519.age.txt", "x25519-crlf.age.txt"])
    func x25519(file: String) throws {
        let metadata = try AgeFileMetadata.parse(fileURL: Fixtures.url(file))

        #expect(metadata.isArmored)
        #expect(metadata.stanzaTypes == ["X25519"])
        #expect(metadata.scryptWorkFactor == nil)
        #expect(!metadata.isPassphraseEncrypted)
    }

    @Test("SSH headers, binary and armored", arguments: [
        ("ssh-ed25519.age", false, ["ssh-ed25519"]),
        ("ssh-rsa.age.txt", true, ["ssh-rsa"]),
    ])
    func ssh(file: String, isArmored: Bool, stanzaTypes: [String]) throws {
        let metadata = try AgeFileMetadata.parse(fileURL: Fixtures.url(file))

        #expect(metadata.isArmored == isArmored)
        #expect(metadata.stanzaTypes == stanzaTypes)
        #expect(metadata.scryptWorkFactor == nil)
    }

    @Test("Header with several recipient types")
    func multipleRecipients() throws {
        let metadata = try AgeFileMetadata.parse(fileURL: Fixtures.url("multi-recipient.age.txt"))

        #expect(Set(metadata.stanzaTypes) == ["X25519", "ssh-ed25519", "ssh-rsa"])
        #expect(metadata.stanzaTypes.count == 3)
    }

    @Test("Files written by this package, binary and armored", arguments: [false, true])
    func ownFiles(armor: Bool) throws {
        let directory = try TemporaryDirectory()
        let input = try directory.write("metadata", to: "input.txt")
        let x25519File = directory.file("x25519.age")
        let scryptFile = directory.file("scrypt.age")
        let identity = try AgeIdentity.generate()

        try AgeEncryption.encryptFile(
            inputURL: input,
            outputURL: x25519File,
            recipients: [identity.toRecipient(), AgeIdentity.generate().toRecipient()],
            armor: armor
        )
        try AgeEncryption.encryptFile(inputURL: input, outputURL: scryptFile, passphrase: "metadata", armor: armor)

        // Grease stanzas are left out, and repeated types are listed once
        let x25519 = try AgeFileMetadata.parse(fileURL: x25519File)
        #expect(x25519.isArmored == armor)
        #expect(x25519.stanzaTypes == ["X25519"])

        let scrypt = try AgeFileMetadata.parse(fileURL: scryptFile)
        #expect(scrypt.isArmored == armor)
        #expect(scrypt.stanzaTypes == ["scrypt"])
        #expect((scrypt.scryptWorkFactor ?? 0) > 0)
    }

    @Test("Non-age input throws malformedInput")
    func malformedInput() throws {
        let directory = try TemporaryDirectory()
        let inputs = [
            try directory.write("This is not an age file.\n", to: "text"),
            try directory.write("", to: "empty"),
            try directory.write("age-encryption.org/v2\n-> X25519 abc\n\n--- mac\n", to: "version"),
            try directory.write("age-encryption.org/v1\n-> X25519 abc\n", to: "truncated"),
            try directory.write("age-encryption.org/v1\nnot a stanza\n--- mac\n", to: "stanza"),
            try directory.write("-----BEGIN AGE ENCRYPTED FILE-----\n!!!!\n-----END AGE ENCRYPTED FILE-----\n", to: "armor"),
        ]

        for input in inputs {
            expectAgeError(.malformedInput) { try AgeFileMetadata.parse(fileURL: input) }
        }
    }

    @Test("Missing file throws io")
    func missingFile() throws {
        let directory = try TemporaryDirectory()

        expectAgeError(.io) { try AgeFileMetadata.parse(fileURL: directory.file("missing.age")) }
    }
}
