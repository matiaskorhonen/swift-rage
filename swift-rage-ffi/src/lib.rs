use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Write};
use thiserror::Error;
use secrecy::ExposeSecret;

/// Error types for the Age wrapper
#[derive(Debug, Error)]
pub enum RageError {
    #[error("IO error: {0}")]
    IoError(String),
    #[error("Decryption error: {0}")]
    DecryptionError(String),
    #[error("Encryption error: {0}")]
    EncryptionError(String),
    #[error("Invalid key: {0}")]
    InvalidKey(String),
    #[error("Invalid recipient: {0}")]
    InvalidRecipient(String),
    #[error("Parse error: {0}")]
    ParseError(String),
    #[error("UTF-8 error: {0}")]
    Utf8Error(String),
}

impl From<std::io::Error> for RageError {
    fn from(err: std::io::Error) -> Self {
        RageError::IoError(err.to_string())
    }
}

impl From<std::str::Utf8Error> for RageError {
    fn from(err: std::str::Utf8Error) -> Self {
        RageError::Utf8Error(err.to_string())
    }
}

/// An x25519 identity (private key)
#[derive(Clone)]
pub struct Identity {
    pub key_data: String,
}

/// An x25519 recipient (public key)
#[derive(Clone)]
pub struct Recipient {
    pub key_data: String,
}

/// Metadata about an Age encrypted file
pub struct FileMetadata {
    pub recipients: Vec<String>,
    pub is_armored: bool,
}

/// Generate a new x25519 identity
pub fn generate_identity() -> Result<Identity, RageError> {
    let identity = age::x25519::Identity::generate();
    Ok(Identity {
        key_data: identity.to_string().expose_secret().to_string(),
    })
}

/// Parse an x25519 identity from a string (Bech32 encoded)
pub fn parse_identity(identity_str: String) -> Result<Identity, RageError> {
    let identity: age::x25519::Identity = identity_str
        .parse()
        .map_err(|e| {
            RageError::InvalidKey(format!("Failed to parse identity: {:?}", e))
        })?;
    
    Ok(Identity {
        key_data: identity.to_string().expose_secret().to_string(),
    })
}

/// Get the recipient (public key) for an identity
pub fn identity_to_recipient(identity: Identity) -> Result<Recipient, RageError> {
    let ident: age::x25519::Identity = identity.key_data
        .parse()
        .map_err(|e| {
            RageError::InvalidKey(format!("Failed to parse identity: {:?}", e))
        })?;
    
    let recipient = ident.to_public();
    Ok(Recipient {
        key_data: recipient.to_string(),
    })
}

/// Parse a recipient from a string (Bech32 encoded)
pub fn parse_recipient(recipient_str: String) -> Result<Recipient, RageError> {
    let _recipient: age::x25519::Recipient = recipient_str
        .parse()
        .map_err(|e| {
            RageError::InvalidRecipient(format!("Failed to parse recipient: {:?}", e))
        })?;
    
    Ok(Recipient {
        key_data: recipient_str,
    })
}

/// Parse Age file metadata/header from a file
pub fn parse_file_metadata(file_path: String) -> Result<FileMetadata, RageError> {
    let file = File::open(&file_path)?;
    let mut reader = BufReader::new(file);
    
    // Try to detect if it's armored by reading the first few bytes
    let mut header = [0u8; 32];
    reader.read_exact(&mut header)?;
    
    let is_armored = header.starts_with(b"-----BEGIN AGE ENCRYPTED FILE-----");
    
    // For now, we can't easily extract recipient info without decrypting
    // This is a simplified implementation
    Ok(FileMetadata {
        recipients: vec![],
        is_armored,
    })
}

/// Encrypt a file with x25519 recipients using streaming
pub fn encrypt_file(
    input_path: String,
    output_path: String,
    recipients: Vec<Recipient>,
    armor: bool,
) -> Result<(), RageError> {
    if recipients.is_empty() {
        return Err(RageError::EncryptionError(
            "At least one recipient required".to_string(),
        ));
    }

    let input_file = File::open(&input_path)?;
    let mut input_reader = BufReader::new(input_file);

    let output_file = File::create(&output_path)?;
    
    // Parse all recipients
    let age_recipients: Result<Vec<Box<dyn age::Recipient + Send>>, RageError> = recipients
        .into_iter()
        .map(|r| {
            let recipient: age::x25519::Recipient = r.key_data
                .parse()
                .map_err(|e| {
                    RageError::InvalidRecipient(format!("Failed to parse recipient: {:?}", e))
                })?;
            Ok(Box::new(recipient) as Box<dyn age::Recipient + Send>)
        })
        .collect();
    
    let age_recipients = age_recipients?;

    // Create encryptor
    let encryptor = age::Encryptor::with_recipients(age_recipients)
        .expect("we provided at least one recipient");

    // Stream the data with or without armor
    if armor {
        let armored_writer = age::armor::ArmoredWriter::wrap_output(
            BufWriter::new(output_file),
            age::armor::Format::AsciiArmor,
        ).map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
        
        let mut writer = encryptor
            .wrap_output(armored_writer)
            .map_err(|e: age::EncryptError| RageError::EncryptionError(e.to_string()))?;
        
        std::io::copy(&mut input_reader, &mut writer)?;
        let armored_writer = writer.finish().map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
        let buf_writer = armored_writer.finish().map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
        buf_writer.into_inner().map_err(|e| RageError::IoError(e.to_string()))?;
    } else {
        let mut writer = encryptor
            .wrap_output(BufWriter::new(output_file))
            .map_err(|e: age::EncryptError| RageError::EncryptionError(e.to_string()))?;
        
        std::io::copy(&mut input_reader, &mut writer)?;
        writer.finish().map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
    }

    Ok(())
}

/// Encrypt a file with a passphrase using streaming
pub fn encrypt_file_with_passphrase(
    input_path: String,
    output_path: String,
    passphrase: String,
    armor: bool,
) -> Result<(), RageError> {
    let input_file = File::open(&input_path)?;
    let mut input_reader = BufReader::new(input_file);

    let output_file = File::create(&output_path)?;

    // Create encryptor with passphrase
    let encryptor = age::Encryptor::with_user_passphrase(secrecy::Secret::new(passphrase));

    // Stream the data with or without armor
    if armor {
        let armored_writer = age::armor::ArmoredWriter::wrap_output(
            BufWriter::new(output_file),
            age::armor::Format::AsciiArmor,
        ).map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
        
        let mut writer = encryptor
            .wrap_output(armored_writer)
            .map_err(|e: age::EncryptError| RageError::EncryptionError(e.to_string()))?;
        
        std::io::copy(&mut input_reader, &mut writer)?;
        let armored_writer = writer.finish().map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
        let buf_writer = armored_writer.finish().map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
        buf_writer.into_inner().map_err(|e| RageError::IoError(e.to_string()))?;
    } else {
        let mut writer = encryptor
            .wrap_output(BufWriter::new(output_file))
            .map_err(|e: age::EncryptError| RageError::EncryptionError(e.to_string()))?;
        
        std::io::copy(&mut input_reader, &mut writer)?;
        writer.finish().map_err(|e: std::io::Error| RageError::IoError(e.to_string()))?;
    }

    Ok(())
}

/// Decrypt a file with x25519 identities to a temporary file using streaming
pub fn decrypt_file(
    input_path: String,
    identities: Vec<Identity>,
) -> Result<String, RageError> {
    if identities.is_empty() {
        return Err(RageError::DecryptionError(
            "At least one identity required".to_string(),
        ));
    }

    let input_file = File::open(&input_path)?;
    let input_reader = BufReader::new(input_file);

    // Parse all identities
    let age_identities: Result<Vec<Box<dyn age::Identity>>, RageError> = identities
        .into_iter()
        .map(|i| {
            let identity: age::x25519::Identity = i.key_data
                .parse()
                .map_err(|e| {
                    RageError::InvalidKey(format!("Failed to parse identity: {:?}", e))
                })?;
            Ok(Box::new(identity) as Box<dyn age::Identity>)
        })
        .collect();
    
    let age_identities = age_identities?;

    // Wrap in ArmoredReader to handle both armored and non-armored files
    let armored_reader = age::armor::ArmoredReader::new(input_reader);

    // Create a decryptor
    let decryptor = match age::Decryptor::new(armored_reader)
        .map_err(|e: age::DecryptError| RageError::DecryptionError(e.to_string()))?
    {
        age::Decryptor::Recipients(d) => d,
        _ => {
            return Err(RageError::DecryptionError(
                "File was encrypted with a passphrase, not with recipients".to_string(),
            ));
        }
    };

    // Try to decrypt with the provided identities
    let mut reader = decryptor
        .decrypt(age_identities.iter().map(|i| i.as_ref() as &dyn age::Identity))
        .map_err(|e: age::DecryptError| RageError::DecryptionError(e.to_string()))?;

    // Create a temporary file
    let temp_dir = std::env::temp_dir();
    let temp_file_path = temp_dir.join(format!("age_decrypt_{}.tmp", uuid::Uuid::new_v4()));
    let temp_file = File::create(&temp_file_path)?;
    let mut temp_writer = BufWriter::new(temp_file);

    // Stream the decrypted data to the temporary file
    std::io::copy(&mut reader, &mut temp_writer)?;
    temp_writer.flush()?;

    Ok(temp_file_path.to_string_lossy().to_string())
}

/// Decrypt a file with a passphrase to a temporary file using streaming
pub fn decrypt_file_with_passphrase(
    input_path: String,
    passphrase: String,
) -> Result<String, RageError> {
    let input_file = File::open(&input_path)?;
    let input_reader = BufReader::new(input_file);

    // Wrap in ArmoredReader to handle both armored and non-armored files
    let armored_reader = age::armor::ArmoredReader::new(input_reader);

    // Create a decryptor
    let decryptor = match age::Decryptor::new(armored_reader)
        .map_err(|e: age::DecryptError| RageError::DecryptionError(e.to_string()))?
    {
        age::Decryptor::Passphrase(d) => d,
        _ => {
            return Err(RageError::DecryptionError(
                "File was encrypted with recipients, not with a passphrase".to_string(),
            ));
        }
    };

    // Try to decrypt with the provided passphrase
    let mut reader = decryptor
        .decrypt(&secrecy::Secret::new(passphrase), None)
        .map_err(|e: age::DecryptError| RageError::DecryptionError(e.to_string()))?;

    // Create a temporary file
    let temp_dir = std::env::temp_dir();
    let temp_file_path = temp_dir.join(format!("age_decrypt_{}.tmp", uuid::Uuid::new_v4()));
    let temp_file = File::create(&temp_file_path)?;
    let mut temp_writer = BufWriter::new(temp_file);

    // Stream the decrypted data to the temporary file
    std::io::copy(&mut reader, &mut temp_writer)?;
    temp_writer.flush()?;

    Ok(temp_file_path.to_string_lossy().to_string())
}

// Include the UniFFI generated scaffolding
uniffi::include_scaffolding!("swift_rage");
