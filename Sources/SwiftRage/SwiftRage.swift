import Foundation

/// A Swift wrapper for the Age encryption library.
///
/// SwiftRage provides a simple and secure way to encrypt and decrypt files using the Age encryption format.
/// It supports both x25519 key-based encryption and passphrase-based encryption.
///
/// ## Topics
///
/// ### Encryption and Decryption
/// - ``AgeEncryption``
/// - ``AgeDecryption``
///
/// ### Keys and Recipients
/// - ``AgeIdentity``
/// - ``AgeRecipient``
///
/// ### File Operations
/// - ``EncryptionOptions``
/// - ``DecryptionOptions``

/// High-level Swift API for Age encryption operations.
///
/// This class provides a convenient interface for encrypting and decrypting files
/// using the Age encryption format with x25519 keys or passphrases.
///
/// ## Overview
///
/// Age is a simple, modern, and secure file encryption tool, format, and library.
/// It supports:
/// - X25519 key-based encryption with multiple recipients
/// - Passphrase-based encryption
/// - ASCII armor format for safe transmission
/// - Streaming encryption and decryption
///
/// ## Example Usage
///
/// ### Encrypting a file with a recipient
///
/// ```swift
/// // Generate a new identity
/// let identity = try AgeIdentity.generate()
/// let recipient = try identity.toRecipient()
///
/// // Encrypt a file
/// try AgeEncryption.encryptFile(
///     inputPath: "/path/to/plaintext.txt",
///     outputPath: "/path/to/encrypted.age",
///     recipients: [recipient],
///     armor: true
/// )
/// ```
///
/// ### Decrypting a file with an identity
///
/// ```swift
/// // Parse an existing identity
/// let identity = try AgeIdentity.parse(identityString)
///
/// // Decrypt to a temporary file
/// let decryptedPath = try AgeDecryption.decryptFile(
///     inputPath: "/path/to/encrypted.age",
///     identities: [identity]
/// )
///
/// // Read the decrypted content
/// let content = try String(contentsOfFile: decryptedPath, encoding: .utf8)
///
/// // Clean up the temporary file
/// try FileManager.default.removeItem(atPath: decryptedPath)
/// ```
public enum SwiftRage {}

// MARK: - Identity Management

/// Represents an Age x25519 identity (private key).
///
/// An identity is used to decrypt files that were encrypted for the corresponding recipient (public key).
///
/// ## Topics
///
/// ### Creating Identities
/// - ``generate()``
/// - ``parse(_:)``
///
/// ### Converting to Recipient
/// - ``toRecipient()``
public struct AgeIdentity {
    fileprivate let identity: Identity
    
    /// Generates a new random x25519 identity.
    ///
    /// - Returns: A new Age identity.
    /// - Throws: ``RageError`` if the identity generation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeIdentity.generate()
    /// print("Generated identity: \(identity.keyData)")
    /// ```
    public static func generate() throws -> AgeIdentity {
        let identity = try generateIdentity()
        return AgeIdentity(identity: identity)
    }
    
    /// Parses an x25519 identity from a Bech32-encoded string.
    ///
    /// - Parameter identityString: The Bech32-encoded identity string (starts with "AGE-SECRET-KEY-").
    /// - Returns: The parsed Age identity.
    /// - Throws: ``RageError`` if the identity string is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identityStr = "AGE-SECRET-KEY-1..."
    /// let identity = try AgeIdentity.parse(identityStr)
    /// ```
    public static func parse(_ identityString: String) throws -> AgeIdentity {
        let identity = try parseIdentity(identityStr: identityString)
        return AgeIdentity(identity: identity)
    }
    
    /// Converts this identity to its corresponding recipient (public key).
    ///
    /// - Returns: The Age recipient derived from this identity.
    /// - Throws: ``RageError`` if the conversion fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeIdentity.generate()
    /// let recipient = try identity.toRecipient()
    /// // Share the recipient with others to receive encrypted files
    /// ```
    public func toRecipient() throws -> AgeRecipient {
        let recipient = try identityToRecipient(identity: identity)
        return AgeRecipient(recipient: recipient)
    }
    
    /// The Bech32-encoded string representation of this identity.
    ///
    /// This value should be kept secret as it allows decrypting files.
    public var keyData: String {
        identity.keyData
    }
    
    fileprivate init(identity: Identity) {
        self.identity = identity
    }
}

/// Represents an Age x25519 recipient (public key).
///
/// A recipient is used to encrypt files. Anyone with the corresponding identity can decrypt them.
///
/// ## Topics
///
/// ### Creating Recipients
/// - ``parse(_:)``
public struct AgeRecipient {
    fileprivate let recipient: Recipient
    
    /// Parses an x25519 recipient from a Bech32-encoded string.
    ///
    /// - Parameter recipientString: The Bech32-encoded recipient string (starts with "age1").
    /// - Returns: The parsed Age recipient.
    /// - Throws: ``RageError`` if the recipient string is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let recipientStr = "age1..."
    /// let recipient = try AgeRecipient.parse(recipientStr)
    /// ```
    public static func parse(_ recipientString: String) throws -> AgeRecipient {
        let recipient = try parseRecipient(recipientStr: recipientString)
        return AgeRecipient(recipient: recipient)
    }
    
    /// The Bech32-encoded string representation of this recipient.
    ///
    /// This value can be safely shared with others who want to send you encrypted files.
    public var keyData: String {
        recipient.keyData
    }
    
    fileprivate init(recipient: Recipient) {
        self.recipient = recipient
    }
}

// MARK: - File Metadata

/// Metadata about an Age-encrypted file.
///
/// This structure contains information about an encrypted file without decrypting it.
///
/// ## Topics
///
/// ### Parsing Metadata
/// - ``parse(filePath:)``
public struct AgeFileMetadata {
    /// List of recipient identifiers in the file (may be empty).
    public let recipients: [String]
    
    /// Whether the file uses ASCII armor format.
    public let isArmored: Bool
    
    /// Parses metadata from an Age-encrypted file.
    ///
    /// - Parameter filePath: The path to the encrypted file.
    /// - Returns: The file metadata.
    /// - Throws: ``RageError`` if the file cannot be read or parsed.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let metadata = try AgeFileMetadata.parse(filePath: "/path/to/file.age")
    /// print("File is armored: \(metadata.isArmored)")
    /// ```
    public static func parse(filePath: String) throws -> AgeFileMetadata {
        let metadata = try parseFileMetadata(filePath: filePath)
        return AgeFileMetadata(
            recipients: metadata.recipients,
            isArmored: metadata.isArmored
        )
    }
}

// MARK: - Encryption

/// Options for file encryption operations.
public struct EncryptionOptions {
    /// Whether to use ASCII armor format (text-safe encoding).
    public let armor: Bool
    
    /// Creates encryption options.
    ///
    /// - Parameter armor: Whether to use ASCII armor format. Defaults to `false`.
    public init(armor: Bool = false) {
        self.armor = armor
    }
}

// MARK: - Internal FFI Helpers

fileprivate func callFFIEncryptFile(
    inputPath: String,
    outputPath: String,
    recipients: [Recipient],
    armor: Bool
) throws {
    try encryptFile(inputPath: inputPath, outputPath: outputPath, recipients: recipients, armor: armor)
}

fileprivate func callFFIDecryptFile(
    inputPath: String,
    identities: [Identity]
) throws -> String {
    try decryptFile(inputPath: inputPath, identities: identities)
}

// MARK: - Encryption

/// High-level API for Age file encryption.
///
/// ## Topics
///
/// ### Encrypting Files
/// - ``encryptFile(inputPath:outputPath:recipients:armor:)``
/// - ``encryptFile(inputPath:outputPath:passphrase:armor:)``
public enum AgeEncryption {
    /// Encrypts a file for one or more recipients using streaming.
    ///
    /// The file will be encrypted using x25519 public-key encryption. Only holders of the
    /// corresponding private keys will be able to decrypt it.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the plaintext input file.
    ///   - outputPath: Path where the encrypted file will be written.
    ///   - recipients: List of Age recipients who can decrypt the file. Must contain at least one recipient.
    ///   - armor: Whether to use ASCII armor format. Defaults to `false`.
    /// - Throws: ``RageError`` if encryption fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeIdentity.generate()
    /// let recipient = try identity.toRecipient()
    ///
    /// try AgeEncryption.encryptFile(
    ///     inputPath: "/path/to/secret.txt",
    ///     outputPath: "/path/to/secret.age",
    ///     recipients: [recipient],
    ///     armor: true
    /// )
    /// ```
    public static func encryptFile(
        inputPath: String,
        outputPath: String,
        recipients: [AgeRecipient],
        armor: Bool = false
    ) throws {
        let ffiRecipients = recipients.map { $0.recipient }
        try callFFIEncryptFile(
            inputPath: inputPath,
            outputPath: outputPath,
            recipients: ffiRecipients,
            armor: armor
        )
    }
    
    /// Encrypts a file with a passphrase using streaming.
    ///
    /// The file will be encrypted using the provided passphrase. Anyone with the passphrase
    /// can decrypt it.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the plaintext input file.
    ///   - outputPath: Path where the encrypted file will be written.
    ///   - passphrase: The passphrase to use for encryption.
    ///   - armor: Whether to use ASCII armor format. Defaults to `false`.
    /// - Throws: ``RageError`` if encryption fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try AgeEncryption.encryptFile(
    ///     inputPath: "/path/to/secret.txt",
    ///     outputPath: "/path/to/secret.age",
    ///     passphrase: "correct horse battery staple",
    ///     armor: true
    /// )
    /// ```
    public static func encryptFile(
        inputPath: String,
        outputPath: String,
        passphrase: String,
        armor: Bool = false
    ) throws {
        try encryptFileWithPassphrase(
            inputPath: inputPath,
            outputPath: outputPath,
            passphrase: passphrase,
            armor: armor
        )
    }
}

// MARK: - Decryption

/// High-level API for Age file decryption.
///
/// Files are decrypted to temporary files which must be manually cleaned up.
///
/// ## Topics
///
/// ### Decrypting Files
/// - ``decryptFile(inputPath:identities:)``
/// - ``decryptFile(inputPath:passphrase:)``
public enum AgeDecryption {
    /// Decrypts a file using one or more identities to a temporary file.
    ///
    /// The file will be decrypted using the provided identities. At least one identity must
    /// correspond to a recipient the file was encrypted for.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the encrypted file.
    ///   - identities: List of Age identities to try for decryption. Must contain at least one identity.
    /// - Returns: Path to the temporary file containing the decrypted data.
    ///   The caller is responsible for deleting this file when done.
    /// - Throws: ``RageError`` if decryption fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeIdentity.parse(identityString)
    ///
    /// let tempPath = try AgeDecryption.decryptFile(
    ///     inputPath: "/path/to/encrypted.age",
    ///     identities: [identity]
    /// )
    ///
    /// // Use the decrypted file
    /// let content = try String(contentsOfFile: tempPath, encoding: .utf8)
    ///
    /// // Clean up
    /// try FileManager.default.removeItem(atPath: tempPath)
    /// ```
    public static func decryptFile(
        inputPath: String,
        identities: [AgeIdentity]
    ) throws -> String {
        let ffiIdentities = identities.map { $0.identity }
        return try callFFIDecryptFile(
            inputPath: inputPath,
            identities: ffiIdentities
        )
    }
    
    /// Decrypts a file using a passphrase to a temporary file.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the encrypted file.
    ///   - passphrase: The passphrase used to encrypt the file.
    /// - Returns: Path to the temporary file containing the decrypted data.
    ///   The caller is responsible for deleting this file when done.
    /// - Throws: ``RageError`` if decryption fails or if the passphrase is incorrect.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let tempPath = try AgeDecryption.decryptFile(
    ///     inputPath: "/path/to/encrypted.age",
    ///     passphrase: "correct horse battery staple"
    /// )
    ///
    /// // Use the decrypted file
    /// let content = try String(contentsOfFile: tempPath, encoding: .utf8)
    ///
    /// // Clean up
    /// try FileManager.default.removeItem(atPath: tempPath)
    /// ```
    public static func decryptFile(
        inputPath: String,
        passphrase: String
    ) throws -> String {
        return try decryptFileWithPassphrase(
            inputPath: inputPath,
            passphrase: passphrase
        )
    }
}
