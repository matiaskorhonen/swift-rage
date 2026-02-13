import Foundation
import Testing
@testable import SwiftRage

/// Tests for Age identity and recipient operations.
@Suite("Identity and Recipient Tests")
struct IdentityTests {
    
    @Test("Generate new identity")
    func generateIdentity() throws {
        let identity = try AgeIdentity.generate()
        
        #expect(!identity.keyData.isEmpty)
        #expect(identity.keyData.hasPrefix("AGE-SECRET-KEY-"))
    }
    
    @Test("Parse identity from string")
    func parseIdentity() throws {
        // First generate an identity
        let generatedIdentity = try AgeIdentity.generate()
        let identityString = generatedIdentity.keyData
        
        // Parse it back
        let parsedIdentity = try AgeIdentity.parse(identityString)
        
        #expect(parsedIdentity.keyData == identityString)
    }
    
    @Test("Convert identity to recipient")
    func identityToRecipient() throws {
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        
        #expect(!recipient.keyData.isEmpty)
        #expect(recipient.keyData.hasPrefix("age1"))
    }
    
    @Test("Parse recipient from string")
    func parseRecipient() throws {
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        let recipientString = recipient.keyData
        
        // Parse it back
        let parsedRecipient = try AgeRecipient.parse(recipientString)
        
        #expect(parsedRecipient.keyData == recipientString)
    }
    
    @Test("Invalid identity string throws error")
    func invalidIdentityString() {
        #expect(throws: (any Error).self) {
            try AgeIdentity.parse("invalid-identity-string")
        }
    }
    
    @Test("Invalid recipient string throws error")
    func invalidRecipientString() {
        #expect(throws: (any Error).self) {
            try AgeRecipient.parse("invalid-recipient-string")
        }
    }
}

/// Tests for file encryption and decryption with recipients.
@Suite("Encryption and Decryption with Recipients")
struct EncryptionWithRecipientsTests {
    
    @Test("Encrypt and decrypt file with single recipient (binary format)")
    func encryptDecryptBinary() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Hello, Age encryption!"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        // Generate identity and get recipient
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        
        // Encrypt
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            recipients: [recipient],
            armor: false
        )
        
        // Verify encrypted file exists and is not empty
        let encryptedData = try Data(contentsOf: URL(fileURLWithPath: encryptedPath))
        #expect(encryptedData.count > 0)
        
        // Decrypt
        let decryptedPath = try AgeDecryption.decryptFile(
            inputPath: encryptedPath,
            identities: [identity]
        )
        
        // Verify decrypted content
        let decryptedContent = try String(contentsOfFile: decryptedPath, encoding: .utf8)
        #expect(decryptedContent == testContent)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
        try? FileManager.default.removeItem(atPath: decryptedPath)
    }
    
    @Test("Encrypt and decrypt file with single recipient (ASCII armor)")
    func encryptDecryptArmored() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Hello, Age encryption with armor!"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        // Generate identity and get recipient
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        
        // Encrypt with armor
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            recipients: [recipient],
            armor: true
        )
        
        // Verify file is armored (starts with ASCII armor header)
        let encryptedContent = try String(contentsOfFile: encryptedPath, encoding: .utf8)
        #expect(encryptedContent.hasPrefix("-----BEGIN AGE ENCRYPTED FILE-----"))
        
        // Decrypt
        let decryptedPath = try AgeDecryption.decryptFile(
            inputPath: encryptedPath,
            identities: [identity]
        )
        
        // Verify decrypted content
        let decryptedContent = try String(contentsOfFile: decryptedPath, encoding: .utf8)
        #expect(decryptedContent == testContent)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
        try? FileManager.default.removeItem(atPath: decryptedPath)
    }
    
    @Test("Encrypt with multiple recipients")
    func encryptDecryptMultipleRecipients() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Secret message for multiple recipients"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        // Generate multiple identities
        let identity1 = try AgeIdentity.generate()
        let identity2 = try AgeIdentity.generate()
        let identity3 = try AgeIdentity.generate()
        
        let recipient1 = try identity1.toRecipient()
        let recipient2 = try identity2.toRecipient()
        let recipient3 = try identity3.toRecipient()
        
        // Encrypt for all three recipients
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            recipients: [recipient1, recipient2, recipient3],
            armor: false
        )
        
        // Verify each identity can decrypt
        for identity in [identity1, identity2, identity3] {
            let decryptedPath = try AgeDecryption.decryptFile(
                inputPath: encryptedPath,
                identities: [identity]
            )
            
            let decryptedContent = try String(contentsOfFile: decryptedPath, encoding: .utf8)
            #expect(decryptedContent == testContent)
            
            try? FileManager.default.removeItem(atPath: decryptedPath)
        }
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
    }
    
    @Test("Wrong identity cannot decrypt")
    func wrongIdentity() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Secret message"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        // Generate two different identities
        let identity1 = try AgeIdentity.generate()
        let identity2 = try AgeIdentity.generate()
        
        let recipient1 = try identity1.toRecipient()
        
        // Encrypt for identity1 only
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            recipients: [recipient1],
            armor: false
        )
        
        // Try to decrypt with identity2 (should fail)
        #expect(throws: (any Error).self) {
            try AgeDecryption.decryptFile(
                inputPath: encryptedPath,
                identities: [identity2]
            )
        }
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
    }
}

/// Tests for file encryption and decryption with passphrases.
@Suite("Encryption and Decryption with Passphrase")
struct EncryptionWithPassphraseTests {
    
    @Test("Encrypt and decrypt with passphrase (binary format)")
    func encryptDecryptPassphraseBinary() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Passphrase protected content"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        let passphrase = "correct horse battery staple"
        
        // Encrypt
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            passphrase: passphrase,
            armor: false
        )
        
        // Verify encrypted file exists
        #expect(FileManager.default.fileExists(atPath: encryptedPath))
        
        // Decrypt
        let decryptedPath = try AgeDecryption.decryptFile(
            inputPath: encryptedPath,
            passphrase: passphrase
        )
        
        // Verify decrypted content
        let decryptedContent = try String(contentsOfFile: decryptedPath, encoding: .utf8)
        #expect(decryptedContent == testContent)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
        try? FileManager.default.removeItem(atPath: decryptedPath)
    }
    
    @Test("Encrypt and decrypt with passphrase (ASCII armor)")
    func encryptDecryptPassphraseArmored() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Armored passphrase protected content"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        let passphrase = "my secret passphrase"
        
        // Encrypt with armor
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            passphrase: passphrase,
            armor: true
        )
        
        // Verify file is armored
        let encryptedContent = try String(contentsOfFile: encryptedPath, encoding: .utf8)
        #expect(encryptedContent.hasPrefix("-----BEGIN AGE ENCRYPTED FILE-----"))
        
        // Decrypt
        let decryptedPath = try AgeDecryption.decryptFile(
            inputPath: encryptedPath,
            passphrase: passphrase
        )
        
        // Verify decrypted content
        let decryptedContent = try String(contentsOfFile: decryptedPath, encoding: .utf8)
        #expect(decryptedContent == testContent)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
        try? FileManager.default.removeItem(atPath: decryptedPath)
    }
    
    @Test("Wrong passphrase cannot decrypt")
    func wrongPassphrase() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Secret content"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        let correctPassphrase = "correct passphrase"
        let wrongPassphrase = "wrong passphrase"
        
        // Encrypt
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            passphrase: correctPassphrase,
            armor: false
        )
        
        // Try to decrypt with wrong passphrase (should fail)
        #expect(throws: (any Error).self) {
            try AgeDecryption.decryptFile(
                inputPath: encryptedPath,
                passphrase: wrongPassphrase
            )
        }
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
    }
    
    @Test("Cannot decrypt passphrase file with identity")
    func cannotDecryptPassphraseWithIdentity() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create test content
        let testContent = "Passphrase encrypted"
        try testContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        let passphrase = "my passphrase"
        
        // Encrypt with passphrase
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            passphrase: passphrase,
            armor: false
        )
        
        // Try to decrypt with identity (should fail)
        let identity = try AgeIdentity.generate()
        #expect(throws: (any Error).self) {
            try AgeDecryption.decryptFile(
                inputPath: encryptedPath,
                identities: [identity]
            )
        }
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
    }
}

/// Tests for file metadata parsing.
@Suite("File Metadata Tests")
struct FileMetadataTests {
    
    @Test("Parse metadata from armored file")
    func parseArmoredMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create and encrypt a file
        try "test".write(toFile: inputPath, atomically: true, encoding: .utf8)
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            recipients: [recipient],
            armor: true
        )
        
        // Parse metadata
        let metadata = try AgeFileMetadata.parse(filePath: encryptedPath)
        #expect(metadata.isArmored == true)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
    }
    
    @Test("Parse metadata from binary file")
    func parseBinaryMetadata() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_input_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create and encrypt a file
        try "test".write(toFile: inputPath, atomically: true, encoding: .utf8)
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            recipients: [recipient],
            armor: false
        )
        
        // Parse metadata
        let metadata = try AgeFileMetadata.parse(filePath: encryptedPath)
        #expect(metadata.isArmored == false)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
    }
}

/// Tests for large file handling and streaming.
@Suite("Streaming and Large Files")
struct StreamingTests {
    
    @Test("Encrypt and decrypt large file")
    func largeFileEncryption() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let inputPath = tempDir.appendingPathComponent("test_large_\(UUID()).txt").path
        let encryptedPath = tempDir.appendingPathComponent("test_encrypted_\(UUID()).age").path
        
        // Create a larger test file (1 MB)
        let largeContent = String(repeating: "A", count: 1024 * 1024)
        try largeContent.write(toFile: inputPath, atomically: true, encoding: .utf8)
        
        // Generate identity and encrypt
        let identity = try AgeIdentity.generate()
        let recipient = try identity.toRecipient()
        
        try AgeEncryption.encryptFile(
            inputPath: inputPath,
            outputPath: encryptedPath,
            recipients: [recipient],
            armor: false
        )
        
        // Decrypt
        let decryptedPath = try AgeDecryption.decryptFile(
            inputPath: encryptedPath,
            identities: [identity]
        )
        
        // Verify content
        let decryptedContent = try String(contentsOfFile: decryptedPath, encoding: .utf8)
        #expect(decryptedContent.count == largeContent.count)
        #expect(decryptedContent == largeContent)
        
        // Cleanup
        try? FileManager.default.removeItem(atPath: inputPath)
        try? FileManager.default.removeItem(atPath: encryptedPath)
        try? FileManager.default.removeItem(atPath: decryptedPath)
    }
}
