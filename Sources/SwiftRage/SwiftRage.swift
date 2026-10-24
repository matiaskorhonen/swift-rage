import Foundation

// MARK: - Errors

/// An error from an age operation.
///
/// Use ``code`` to tell failures apart, and ``message`` for logging:
///
/// ```swift
/// do {
///     let url = try AgeDecryption.decryptFile(inputURL: fileURL, passphrase: passphrase)
/// } catch let error as AgeError where error.code == .wrongPassphrase {
///     // Ask for the passphrase again
/// } catch let error as AgeError {
///     logger.error("Decryption failed: \(error.message)")
/// }
/// ```
public struct AgeError: Error, Sendable, Hashable, CustomStringConvertible, LocalizedError {
    /// The kind of failure.
    public enum Code: String, Sendable, Hashable, CaseIterable {
        /// Reading or writing a file failed.
        case io
        /// The passphrase did not decrypt the file.
        case wrongPassphrase
        /// None of the identities could decrypt the file.
        case noMatchingIdentity
        /// The file was encrypted with a passphrase, but identities were given.
        case encryptedWithPassphrase
        /// The file was encrypted to recipients, but a passphrase was given.
        case encryptedToRecipients
        /// A key is invalid or of an unsupported type.
        case invalidKey
        /// The input is not a well-formed age file, binary or armored.
        case malformedInput
        /// The file's scrypt work factor is higher than the accepted maximum.
        case excessiveWorkFactor
        /// A recipient is invalid or of an unsupported type.
        case invalidRecipient
        /// Encryption failed for a reason other than I/O, for example no recipients were given.
        case encryptionFailed
        /// The SSH private key is encrypted, and no passphrase was given.
        case sshPassphraseRequired
        /// The passphrase did not decrypt the SSH private key.
        case sshWrongPassphrase
        /// The SSH key is neither ssh-ed25519 nor ssh-rsa.
        case sshUnsupportedAlgorithm
        /// The SSH RSA key is larger than 4096 bits.
        case sshKeyTooLarge
    }

    /// The kind of failure.
    public let code: Code

    /// The underlying error message, for logging.
    public let message: String

    /// Creates an error.
    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { message }

    public var errorDescription: String? { message }
}

extension AgeError {
    init(_ error: RageError) {
        switch error {
        case .Io(let message): self.init(code: .io, message: message)
        case .WrongPassphrase(let message): self.init(code: .wrongPassphrase, message: message)
        case .NoMatchingIdentity(let message): self.init(code: .noMatchingIdentity, message: message)
        case .EncryptedWithPassphrase(let message): self.init(code: .encryptedWithPassphrase, message: message)
        case .EncryptedToRecipients(let message): self.init(code: .encryptedToRecipients, message: message)
        case .InvalidKey(let message): self.init(code: .invalidKey, message: message)
        case .MalformedInput(let message): self.init(code: .malformedInput, message: message)
        case .ExcessiveWorkFactor(let message): self.init(code: .excessiveWorkFactor, message: message)
        case .InvalidRecipient(let message): self.init(code: .invalidRecipient, message: message)
        case .EncryptionFailed(let message): self.init(code: .encryptionFailed, message: message)
        case .SshPassphraseRequired(let message): self.init(code: .sshPassphraseRequired, message: message)
        case .SshWrongPassphrase(let message): self.init(code: .sshWrongPassphrase, message: message)
        case .SshUnsupportedAlgorithm(let message): self.init(code: .sshUnsupportedAlgorithm, message: message)
        case .SshKeyTooLarge(let message): self.init(code: .sshKeyTooLarge, message: message)
        }
    }
}

/// Runs an FFI call, converting its errors to ``AgeError``.
fileprivate func ffi<T>(_ body: () throws -> T) throws -> T {
    do {
        return try body()
    } catch let error as RageError {
        throw AgeError(error)
    }
}

/// Returns the file system path of a file URL.
fileprivate func filePath(of url: URL) throws -> String {
    guard url.isFileURL else {
        throw AgeError(code: .io, message: "I/O error: Not a file URL: \(url)")
    }
    return url.path(percentEncoded: false)
}

// MARK: - Identity Management

/// An identity that can decrypt age files: an ``AgeIdentity`` or an ``AgeSSHIdentity``.
///
/// Pass any mix of identities to ``AgeDecryption/decryptFile(inputPath:identities:outputDirectory:)``.
/// Only the types in this package conform to this protocol.
public protocol AgeDecryptionIdentity: Sendable {
    /// The secret key text handed to age: an `AGE-SECRET-KEY-1...` string, or an
    /// unencrypted OpenSSH private key.
    ///
    /// This value must be kept secret.
    var identityString: String { get }
}

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
/// ### Getting the Public Key
/// - ``toRecipient()``
/// - ``info()``
public struct AgeIdentity: AgeDecryptionIdentity, Hashable {
    /// The Bech32-encoded string representation of this identity.
    ///
    /// This value should be kept secret as it allows decrypting files.
    public let keyData: String

    /// Generates a new random x25519 identity.
    ///
    /// - Returns: A new Age identity.
    /// - Throws: ``AgeError`` if the identity generation fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeIdentity.generate()
    /// print("Generated identity: \(identity.keyData)")
    /// ```
    public static func generate() throws -> AgeIdentity {
        AgeIdentity(identity: try ffi { try generateIdentity() })
    }

    /// Parses an x25519 identity from a Bech32-encoded string.
    ///
    /// Leading and trailing whitespace is ignored.
    ///
    /// - Parameter identityString: The Bech32-encoded identity string (starts with "AGE-SECRET-KEY-").
    /// - Returns: The parsed Age identity.
    /// - Throws: ``AgeError`` with code ``AgeError/Code/invalidKey`` if the identity string is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identityStr = "AGE-SECRET-KEY-1..."
    /// let identity = try AgeIdentity.parse(identityStr)
    /// ```
    public static func parse(_ identityString: String) throws -> AgeIdentity {
        AgeIdentity(identity: try ffi { try parseIdentity(identityStr: identityString) })
    }

    /// Converts this identity to its corresponding recipient (public key).
    ///
    /// - Returns: The Age recipient derived from this identity.
    /// - Throws: ``AgeError`` if the conversion fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeIdentity.generate()
    /// let recipient = try identity.toRecipient()
    /// // Share the recipient with others to receive encrypted files
    /// ```
    public func toRecipient() throws -> AgeRecipient {
        AgeRecipient(recipient: try ffi { try identityToRecipient(identity: ffiIdentity) })
    }

    /// Returns the public recipient string and key type of this identity.
    ///
    /// - Returns: The identity's public information.
    /// - Throws: ``AgeError`` if the identity is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let info = try AgeIdentity.parse(identityString).info()
    /// print(info.recipient) // "age1..."
    /// print(info.keyType)   // "age-x25519"
    /// ```
    public func info() throws -> AgeIdentityInfo {
        let info = try ffi { try identityInfo(identity: ffiIdentity) }
        return AgeIdentityInfo(recipient: info.recipient, keyType: info.keyType)
    }

    public var identityString: String { keyData }

    fileprivate var ffiIdentity: Identity { Identity(keyData: keyData) }

    fileprivate init(identity: Identity) {
        self.keyData = identity.keyData
    }
}

/// Public information about an ``AgeIdentity``.
public struct AgeIdentityInfo: Sendable, Hashable {
    /// The key type label of x25519 identities.
    public static let x25519KeyType = "age-x25519"

    /// The Bech32-encoded recipient (public key), starting with "age1".
    public let recipient: String

    /// The key type label, ``x25519KeyType``.
    public let keyType: String
}

/// An OpenSSH private key (ed25519 or RSA) that can decrypt files encrypted to its public key.
///
/// ## Topics
///
/// ### Parsing Keys
/// - ``parse(_:passphrase:)``
///
/// ### Key Information
/// - ``privateKey``
/// - ``publicKey``
/// - ``fingerprint``
/// - ``algorithm``
public struct AgeSSHIdentity: AgeDecryptionIdentity, Hashable {
    /// The algorithm of an SSH key.
    public enum Algorithm: String, Sendable, Hashable, CaseIterable {
        /// An Ed25519 key.
        case ed25519 = "ssh-ed25519"
        /// An RSA key of at most 4096 bits.
        case rsa = "ssh-rsa"
    }

    /// The unencrypted OpenSSH private key, with LF line endings.
    ///
    /// This value must be kept secret. If the original key was protected by a passphrase,
    /// this is the decrypted key.
    public let privateKey: String

    /// The public key in OpenSSH format, for example `ssh-ed25519 AAAA... comment`.
    public let publicKey: String

    /// The SHA256 fingerprint of the public key, for example `SHA256:eOyuFHgZ...`.
    public let fingerprint: String

    /// The key's algorithm.
    public let algorithm: Algorithm

    /// Parses an OpenSSH private key, decrypting it with `passphrase` if it is encrypted.
    ///
    /// - Parameters:
    ///   - privateKey: The OpenSSH private key text (`-----BEGIN OPENSSH PRIVATE KEY-----`).
    ///   - passphrase: The key's passphrase, if it has one.
    /// - Returns: The parsed SSH identity.
    /// - Throws: ``AgeError`` with code
    ///   - ``AgeError/Code/sshPassphraseRequired`` if the key is encrypted and `passphrase` is `nil` or empty,
    ///   - ``AgeError/Code/sshWrongPassphrase`` if the passphrase is wrong,
    ///   - ``AgeError/Code/sshUnsupportedAlgorithm`` for keys other than ed25519 and RSA,
    ///   - ``AgeError/Code/sshKeyTooLarge`` for RSA keys over 4096 bits,
    ///   - ``AgeError/Code/invalidKey`` if the text is not a valid OpenSSH private key.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeSSHIdentity.parse(keyText, passphrase: "snakeoil")
    /// print(identity.fingerprint) // "SHA256:..."
    /// ```
    public static func parse(_ privateKey: String, passphrase: String? = nil) throws -> AgeSSHIdentity {
        let identity = try ffi { try parseSshIdentity(privateKey: privateKey, passphrase: passphrase) }
        guard let algorithm = Algorithm(rawValue: identity.algorithm) else {
            throw AgeError(code: .sshUnsupportedAlgorithm, message: "Unsupported SSH key algorithm: \(identity.algorithm)")
        }
        return AgeSSHIdentity(
            privateKey: identity.privateKey,
            publicKey: identity.publicKey,
            fingerprint: identity.fingerprint,
            algorithm: algorithm
        )
    }

    public var identityString: String { privateKey }
}

/// Represents an Age recipient (public key): x25519 or SSH.
///
/// A recipient is used to encrypt files. Anyone with the corresponding identity can decrypt them.
///
/// ## Topics
///
/// ### Creating Recipients
/// - ``parse(_:)``
public struct AgeRecipient: Sendable, Hashable {
    /// The string representation of this recipient: Bech32 for x25519, OpenSSH format for SSH keys.
    ///
    /// This value can be safely shared with others who want to send you encrypted files.
    public let keyData: String

    /// Parses a recipient: an x25519 recipient (starts with "age1"), or an SSH public key
    /// (starts with "ssh-ed25519 " or "ssh-rsa ").
    ///
    /// - Parameter recipientString: The recipient string.
    /// - Returns: The parsed Age recipient.
    /// - Throws: ``AgeError`` with code ``AgeError/Code/invalidRecipient`` if the recipient string is invalid.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let recipient = try AgeRecipient.parse("age1...")
    /// let sshRecipient = try AgeRecipient.parse(sshIdentity.publicKey)
    /// ```
    public static func parse(_ recipientString: String) throws -> AgeRecipient {
        AgeRecipient(recipient: try ffi { try parseRecipient(recipientStr: recipientString) })
    }

    fileprivate var ffiRecipient: Recipient { Recipient(keyData: keyData) }

    fileprivate init(recipient: Recipient) {
        self.keyData = recipient.keyData
    }
}

// MARK: - File Metadata

/// Metadata about an Age-encrypted file, read from its header without decrypting it.
///
/// ## Topics
///
/// ### Parsing Metadata
/// - ``parse(filePath:)``
/// - ``parse(fileURL:)``
public struct AgeFileMetadata: Sendable, Hashable {
    /// Whether the file uses ASCII armor format.
    public let isArmored: Bool

    /// The types of the header's recipient stanzas, in header order without duplicates,
    /// for example `["X25519"]`, `["scrypt"]`, `["ssh-ed25519", "ssh-rsa"]`.
    ///
    /// Random "grease" stanzas that age adds to headers are left out.
    public let stanzaTypes: [String]

    /// The scrypt work factor (log2 of the scrypt N parameter) for passphrase-encrypted files.
    public let scryptWorkFactor: UInt8?

    /// Whether the file is encrypted with a passphrase rather than to recipients.
    public var isPassphraseEncrypted: Bool {
        stanzaTypes.contains("scrypt")
    }

    /// Parses metadata from an Age-encrypted file.
    ///
    /// Both binary and armored files are supported, including armored files with CRLF line endings.
    ///
    /// - Parameter filePath: The path to the encrypted file.
    /// - Returns: The file metadata.
    /// - Throws: ``AgeError`` with code ``AgeError/Code/malformedInput`` if the file is not an age file,
    ///   or ``AgeError/Code/io`` if it cannot be read.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let metadata = try AgeFileMetadata.parse(filePath: "/path/to/file.age")
    /// if metadata.isPassphraseEncrypted {
    ///     print("scrypt work factor: \(metadata.scryptWorkFactor ?? 0)")
    /// }
    /// ```
    public static func parse(filePath: String) throws -> AgeFileMetadata {
        let metadata = try ffi { try parseFileMetadata(filePath: filePath) }
        return AgeFileMetadata(
            isArmored: metadata.isArmored,
            stanzaTypes: metadata.stanzaTypes,
            scryptWorkFactor: metadata.scryptWorkFactor
        )
    }

    /// Parses metadata from an Age-encrypted file.
    ///
    /// - Parameter fileURL: The file URL of the encrypted file.
    /// - Returns: The file metadata.
    /// - Throws: ``AgeError``; see ``parse(filePath:)``.
    public static func parse(fileURL: URL) throws -> AgeFileMetadata {
        try parse(filePath: filePath(of: fileURL))
    }
}

// MARK: - Encryption

/// Options for file encryption operations.
public struct EncryptionOptions: Sendable, Hashable {
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
//
// These live at file scope so that the generated FFI functions are not shadowed by
// the static methods of the same name.

fileprivate func ffiEncryptFile(inputPath: String, outputPath: String, recipients: [AgeRecipient], armor: Bool) throws {
    try ffi {
        try encryptFile(
            inputPath: inputPath,
            outputPath: outputPath,
            recipients: recipients.map(\.ffiRecipient),
            armor: armor
        )
    }
}

fileprivate func ffiEncryptFile(inputPath: String, outputPath: String, passphrase: String, armor: Bool) throws {
    try ffi {
        try encryptFileWithPassphrase(inputPath: inputPath, outputPath: outputPath, passphrase: passphrase, armor: armor)
    }
}

fileprivate func ffiDecryptFile(
    inputPath: String,
    identities: [any AgeDecryptionIdentity],
    outputDirectory: URL?
) throws -> String {
    let outputDirectoryPath = try outputDirectory.map { try filePath(of: $0) }
    return try ffi {
        try decryptFile(
            inputPath: inputPath,
            identities: identities.map { Identity(keyData: $0.identityString) },
            outputDirectory: outputDirectoryPath
        )
    }
}

fileprivate func ffiDecryptFile(
    inputPath: String,
    passphrase: String,
    maxWorkFactor: UInt8?,
    outputDirectory: URL?
) throws -> String {
    let outputDirectoryPath = try outputDirectory.map { try filePath(of: $0) }
    return try ffi {
        try decryptFileWithPassphrase(
            inputPath: inputPath,
            passphrase: passphrase,
            maxWorkFactor: maxWorkFactor,
            outputDirectory: outputDirectoryPath
        )
    }
}

/// High-level API for Age file encryption.
///
/// Encryption streams the input, so large files are never loaded into memory.
///
/// ## Topics
///
/// ### Encrypting to Recipients
/// - ``encryptFile(inputPath:outputPath:recipients:armor:)``
/// - ``encryptFile(inputURL:outputURL:recipients:armor:)``
///
/// ### Encrypting with a Passphrase
/// - ``encryptFile(inputPath:outputPath:passphrase:armor:)``
/// - ``encryptFile(inputURL:outputURL:passphrase:armor:)``
public enum AgeEncryption {
    /// Encrypts a file for one or more recipients.
    ///
    /// Recipients can be any mix of x25519 and SSH recipients.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the plaintext input file.
    ///   - outputPath: Path where the encrypted file will be written. An existing file is replaced.
    ///   - recipients: List of Age recipients who can decrypt the file. Must contain at least one recipient.
    ///   - armor: Whether to use ASCII armor format. Defaults to `false`.
    /// - Throws: ``AgeError`` if encryption fails.
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
        try ffiEncryptFile(inputPath: inputPath, outputPath: outputPath, recipients: recipients, armor: armor)
    }

    /// Encrypts a file for one or more recipients.
    ///
    /// - Parameters:
    ///   - inputURL: File URL of the plaintext input file.
    ///   - outputURL: File URL where the encrypted file will be written. An existing file is replaced.
    ///   - recipients: List of Age recipients who can decrypt the file. Must contain at least one recipient.
    ///   - armor: Whether to use ASCII armor format. Defaults to `false`.
    /// - Throws: ``AgeError`` if encryption fails.
    public static func encryptFile(
        inputURL: URL,
        outputURL: URL,
        recipients: [AgeRecipient],
        armor: Bool = false
    ) throws {
        try encryptFile(
            inputPath: filePath(of: inputURL),
            outputPath: filePath(of: outputURL),
            recipients: recipients,
            armor: armor
        )
    }

    /// Encrypts a file with a passphrase.
    ///
    /// Anyone with the passphrase can decrypt the file.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the plaintext input file.
    ///   - outputPath: Path where the encrypted file will be written. An existing file is replaced.
    ///   - passphrase: The passphrase to use for encryption.
    ///   - armor: Whether to use ASCII armor format. Defaults to `false`.
    /// - Throws: ``AgeError`` if encryption fails.
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
        try ffiEncryptFile(inputPath: inputPath, outputPath: outputPath, passphrase: passphrase, armor: armor)
    }

    /// Encrypts a file with a passphrase.
    ///
    /// - Parameters:
    ///   - inputURL: File URL of the plaintext input file.
    ///   - outputURL: File URL where the encrypted file will be written. An existing file is replaced.
    ///   - passphrase: The passphrase to use for encryption.
    ///   - armor: Whether to use ASCII armor format. Defaults to `false`.
    /// - Throws: ``AgeError`` if encryption fails.
    public static func encryptFile(
        inputURL: URL,
        outputURL: URL,
        passphrase: String,
        armor: Bool = false
    ) throws {
        try encryptFile(
            inputPath: filePath(of: inputURL),
            outputPath: filePath(of: outputURL),
            passphrase: passphrase,
            armor: armor
        )
    }
}

// MARK: - Decryption

/// High-level API for Age file decryption.
///
/// Decryption streams the input, so large files are never loaded into memory. The plaintext is
/// written to a new file, readable only by the current user:
///
/// - Without an `outputDirectory`, it is a new file in the temporary directory, which the caller
///   must delete when done.
/// - With an `outputDirectory`, it is `<outputDirectory>/<input file name>`, with a trailing
///   `.age` extension removed. Decryption fails with ``AgeError/Code/io`` if that file already exists.
///
/// If decryption fails, the partially written output file is removed.
///
/// ## Topics
///
/// ### Decrypting with Identities
/// - ``decryptFile(inputPath:identities:outputDirectory:)``
/// - ``decryptFile(inputURL:identities:outputDirectory:)``
///
/// ### Decrypting with a Passphrase
/// - ``decryptFile(inputPath:passphrase:maxWorkFactor:outputDirectory:)``
/// - ``decryptFile(inputURL:passphrase:maxWorkFactor:outputDirectory:)``
public enum AgeDecryption {
    /// Decrypts a file using one or more identities.
    ///
    /// Identities can be any mix of ``AgeIdentity`` and ``AgeSSHIdentity`` values. At least one of
    /// them must correspond to a recipient the file was encrypted to.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the encrypted file, binary or armored.
    ///   - identities: Identities to try for decryption. Must contain at least one identity.
    ///   - outputDirectory: Directory to write the decrypted file to. Defaults to `nil`, which
    ///     writes a new file in the temporary directory.
    /// - Returns: Path to the file containing the decrypted data.
    /// - Throws: ``AgeError`` with code
    ///   - ``AgeError/Code/noMatchingIdentity`` if no identity decrypts the file,
    ///   - ``AgeError/Code/encryptedWithPassphrase`` if the file was encrypted with a passphrase,
    ///   - ``AgeError/Code/invalidKey`` if an identity is invalid,
    ///   - ``AgeError/Code/malformedInput`` if the input is not a valid age file,
    ///   - ``AgeError/Code/io`` if a file cannot be read or written.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let identity = try AgeIdentity.parse(identityString)
    /// let sshIdentity = try AgeSSHIdentity.parse(sshKeyText)
    ///
    /// let tempPath = try AgeDecryption.decryptFile(
    ///     inputPath: "/path/to/encrypted.age",
    ///     identities: [identity, sshIdentity]
    /// )
    ///
    /// // Use the decrypted file, then clean up
    /// let content = try String(contentsOfFile: tempPath, encoding: .utf8)
    /// try FileManager.default.removeItem(atPath: tempPath)
    /// ```
    public static func decryptFile(
        inputPath: String,
        identities: [any AgeDecryptionIdentity],
        outputDirectory: URL? = nil
    ) throws -> String {
        try ffiDecryptFile(inputPath: inputPath, identities: identities, outputDirectory: outputDirectory)
    }

    /// Decrypts a file using one or more identities.
    ///
    /// - Parameters:
    ///   - inputURL: File URL of the encrypted file, binary or armored.
    ///   - identities: Identities to try for decryption. Must contain at least one identity.
    ///   - outputDirectory: Directory to write the decrypted file to. Defaults to `nil`, which
    ///     writes a new file in the temporary directory.
    /// - Returns: File URL of the file containing the decrypted data.
    /// - Throws: ``AgeError``; see ``decryptFile(inputPath:identities:outputDirectory:)``.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Decrypt straight into a directory the app has access to
    /// let plaintextURL = try AgeDecryption.decryptFile(
    ///     inputURL: encryptedURL,
    ///     identities: [identity],
    ///     outputDirectory: destinationDirectory
    /// )
    /// ```
    public static func decryptFile(
        inputURL: URL,
        identities: [any AgeDecryptionIdentity],
        outputDirectory: URL? = nil
    ) throws -> URL {
        let path = try decryptFile(
            inputPath: filePath(of: inputURL),
            identities: identities,
            outputDirectory: outputDirectory
        )
        return URL(filePath: path)
    }

    /// Decrypts a file using a passphrase.
    ///
    /// - Parameters:
    ///   - inputPath: Path to the encrypted file, binary or armored.
    ///   - passphrase: The passphrase used to encrypt the file.
    ///   - maxWorkFactor: The highest scrypt work factor (log2 N) to accept. Defaults to `nil`,
    ///     which uses age's limit: about 16 times the work this device does in one second.
    ///     Pass a higher value, such as `64`, to accept any file.
    ///   - outputDirectory: Directory to write the decrypted file to. Defaults to `nil`, which
    ///     writes a new file in the temporary directory.
    /// - Returns: Path to the file containing the decrypted data.
    /// - Throws: ``AgeError`` with code
    ///   - ``AgeError/Code/wrongPassphrase`` if the passphrase is wrong,
    ///   - ``AgeError/Code/encryptedToRecipients`` if the file was encrypted to recipients,
    ///   - ``AgeError/Code/excessiveWorkFactor`` if the work factor is above the maximum,
    ///   - ``AgeError/Code/malformedInput`` if the input is not a valid age file,
    ///   - ``AgeError/Code/io`` if a file cannot be read or written.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let tempPath = try AgeDecryption.decryptFile(
    ///     inputPath: "/path/to/encrypted.age",
    ///     passphrase: "correct horse battery staple"
    /// )
    /// ```
    public static func decryptFile(
        inputPath: String,
        passphrase: String,
        maxWorkFactor: UInt8? = nil,
        outputDirectory: URL? = nil
    ) throws -> String {
        try ffiDecryptFile(
            inputPath: inputPath,
            passphrase: passphrase,
            maxWorkFactor: maxWorkFactor,
            outputDirectory: outputDirectory
        )
    }

    /// Decrypts a file using a passphrase.
    ///
    /// - Parameters:
    ///   - inputURL: File URL of the encrypted file, binary or armored.
    ///   - passphrase: The passphrase used to encrypt the file.
    ///   - maxWorkFactor: The highest scrypt work factor (log2 N) to accept. Defaults to `nil`,
    ///     which uses age's limit.
    ///   - outputDirectory: Directory to write the decrypted file to. Defaults to `nil`, which
    ///     writes a new file in the temporary directory.
    /// - Returns: File URL of the file containing the decrypted data.
    /// - Throws: ``AgeError``; see ``decryptFile(inputPath:passphrase:maxWorkFactor:outputDirectory:)``.
    public static func decryptFile(
        inputURL: URL,
        passphrase: String,
        maxWorkFactor: UInt8? = nil,
        outputDirectory: URL? = nil
    ) throws -> URL {
        let path = try decryptFile(
            inputPath: filePath(of: inputURL),
            passphrase: passphrase,
            maxWorkFactor: maxWorkFactor,
            outputDirectory: outputDirectory
        )
        return URL(filePath: path)
    }
}
