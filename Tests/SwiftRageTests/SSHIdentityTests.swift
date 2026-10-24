import Foundation
import Testing
import SwiftRage

/// Tests for parsing OpenSSH private keys.
@Suite("SSH Identity Tests")
struct SSHIdentityTests {
    @Test("Parse an unencrypted ed25519 key")
    func ed25519() throws {
        let keyText = try Fixtures.string("ed25519")
        let identity = try AgeSSHIdentity.parse(keyText)

        #expect(identity.algorithm == .ed25519)
        #expect(identity.algorithm.rawValue == "ssh-ed25519")
        #expect(identity.publicKey.hasPrefix("ssh-ed25519 "))
        #expect(identity.fingerprint == "SHA256:eOyuFHgZbtluYSK188sRWPf5XMxYQF4ABGDfZAjjATs")
        #expect(identity.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            == keyText.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(identity.identityString == identity.privateKey)
    }

    @Test("Parse an unencrypted RSA key")
    func rsa() throws {
        let keyText = try Fixtures.string("rsa2048")
        let identity = try AgeSSHIdentity.parse(keyText, passphrase: nil)

        #expect(identity.algorithm == .rsa)
        #expect(identity.publicKey.hasPrefix("ssh-rsa "))
        #expect(identity.fingerprint == "SHA256:r+HFDeIirFxMb542ZG0OqPhOrnjDWKkzbfuPYqfh/KE")
        #expect(identity.privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            == keyText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @Test("Parse passphrase-protected keys", arguments: [
        ("ed25519WithPassphrase", AgeSSHIdentity.Algorithm.ed25519, "SHA256:fKS3PjXylsAqjWlwSXYWKtEYxE2H92i+FMTtT7K9YGo"),
        ("rsa2048WithPassphrase", AgeSSHIdentity.Algorithm.rsa, "SHA256:nHSJSJk0OT/s4XbS9XvCH+mQsMDd74qsjB3c5HC72rk"),
    ])
    func passphraseProtected(name: String, algorithm: AgeSSHIdentity.Algorithm, fingerprint: String) throws {
        let keyText = try Fixtures.string(name)
        let identity = try AgeSSHIdentity.parse(keyText, passphrase: Fixtures.sshKeyPassphrase)

        #expect(identity.algorithm == algorithm)
        #expect(identity.fingerprint == fingerprint)
        #expect(identity.publicKey.hasPrefix("\(algorithm.rawValue) "))

        // The private key is returned decrypted, with LF line endings
        #expect(identity.privateKey.hasPrefix("-----BEGIN OPENSSH PRIVATE KEY-----\n"))
        #expect(!identity.privateKey.contains("\r"))
        let reparsed = try AgeSSHIdentity.parse(identity.privateKey)
        #expect(reparsed.fingerprint == fingerprint)
    }

    @Test("Missing passphrase throws sshPassphraseRequired", arguments: ["ed25519WithPassphrase", "rsa2048WithPassphrase"])
    func missingPassphrase(name: String) throws {
        let keyText = try Fixtures.string(name)

        expectAgeError(.sshPassphraseRequired) { try AgeSSHIdentity.parse(keyText) }
        expectAgeError(.sshPassphraseRequired) { try AgeSSHIdentity.parse(keyText, passphrase: "") }
    }

    @Test("Wrong passphrase throws sshWrongPassphrase", arguments: ["ed25519WithPassphrase", "rsa2048WithPassphrase"])
    func wrongPassphrase(name: String) throws {
        let keyText = try Fixtures.string(name)

        expectAgeError(.sshWrongPassphrase) { try AgeSSHIdentity.parse(keyText, passphrase: "wrong") }
    }

    @Test("RSA keys over 4096 bits throw sshKeyTooLarge")
    func rsaTooLarge() throws {
        let keyText = try Fixtures.string("rsa5120")

        expectAgeError(.sshKeyTooLarge) { try AgeSSHIdentity.parse(keyText) }
    }

    @Test("ECDSA keys throw sshUnsupportedAlgorithm")
    func unsupportedAlgorithm() throws {
        let keyText = try Fixtures.string("ecdsa")

        expectAgeError(.sshUnsupportedAlgorithm) { try AgeSSHIdentity.parse(keyText) }
    }

    @Test("Invalid keys throw invalidKey")
    func invalidKey() {
        let nonsense = """
            -----BEGIN OPENSSH PRIVATE KEY-----
            nonsense
            -----END OPENSSH PRIVATE KEY-----
            """

        expectAgeError(.invalidKey) { try AgeSSHIdentity.parse(nonsense) }
        expectAgeError(.invalidKey) { try AgeSSHIdentity.parse(Fixtures.x25519VectorIdentity) }
        expectAgeError(.invalidKey) { try AgeSSHIdentity.parse("") }
    }
}
