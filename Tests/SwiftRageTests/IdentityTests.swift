import Foundation
import Testing
import SwiftRage

/// Tests for x25519 identities and recipients.
@Suite("Identity and Recipient Tests")
struct IdentityTests {
    @Test("Generate new identity")
    func generateIdentity() throws {
        let identity = try AgeIdentity.generate()

        #expect(identity.keyData.hasPrefix("AGE-SECRET-KEY-"))
        #expect(identity.identityString == identity.keyData)
    }

    @Test("Parse identity from string")
    func parseIdentity() throws {
        let generated = try AgeIdentity.generate()
        let parsed = try AgeIdentity.parse(generated.keyData)

        #expect(parsed == generated)
    }

    @Test("Parse identity ignores surrounding whitespace")
    func parseIdentityWithWhitespace() throws {
        let parsed = try AgeIdentity.parse("  \(Fixtures.x25519VectorIdentity)\n")

        #expect(parsed.keyData == Fixtures.x25519VectorIdentity)
    }

    @Test("Convert identity to recipient")
    func identityToRecipient() throws {
        let recipient = try AgeIdentity.generate().toRecipient()

        #expect(recipient.keyData.hasPrefix("age1"))
    }

    @Test("Identity info returns the recipient and key type")
    func identityInfo() throws {
        let identity = try AgeIdentity.parse("AGE-SECRET-KEY-182J9RW3Z4343SWE5WNMGYYKK3CNYRFR4UE07J6MR20QUZ7C7KYAQY9GVSS")
        let info = try identity.info()

        #expect(info.recipient == "age1c02mpgl3hxvd654pg6ettf9gxdrfjfzc59r8yjry907pt4j9hyws40a5j5")
        #expect(info.keyType == "age-x25519")
        #expect(info.keyType == AgeIdentityInfo.x25519KeyType)
        #expect(try info.recipient == identity.toRecipient().keyData)
    }

    @Test("Parse recipient from string")
    func parseRecipient() throws {
        let recipient = try AgeIdentity.generate().toRecipient()
        let parsed = try AgeRecipient.parse(recipient.keyData)

        #expect(parsed == recipient)
    }

    @Test("Parse SSH public keys as recipients")
    func parseSSHRecipient() throws {
        for name in ["ed25519", "rsa2048"] {
            let identity = try AgeSSHIdentity.parse(Fixtures.string(name))
            let recipient = try AgeRecipient.parse(identity.publicKey)

            #expect(recipient.keyData == identity.publicKey)
        }
    }

    @Test("Invalid identity string throws invalidKey")
    func invalidIdentityString() {
        expectAgeError(.invalidKey) { try AgeIdentity.parse("invalid-identity-string") }
        expectAgeError(.invalidKey) { try AgeIdentity.parse("AGE-SECRET-KEY-1INVALID") }
    }

    @Test("Invalid recipient string throws invalidRecipient")
    func invalidRecipientString() {
        expectAgeError(.invalidRecipient) { try AgeRecipient.parse("invalid-recipient-string") }
        expectAgeError(.invalidRecipient) { try AgeRecipient.parse("ssh-ed25519 notbase64") }
    }

    @Test("Values can be sent across concurrency domains")
    func sendable() async throws {
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        let sshIdentity = try AgeSSHIdentity.parse(Fixtures.string("ed25519"))
        let metadata = try AgeFileMetadata.parse(filePath: Fixtures.path("x25519.age.txt"))
        let options = EncryptionOptions(armor: true)

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try identity.toRecipient().keyData }
            group.addTask { recipient.keyData }
            group.addTask { sshIdentity.fingerprint }
            group.addTask { metadata.stanzaTypes.joined() }
            group.addTask { "\(options.armor)" }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(results.count == 5)
    }
}
