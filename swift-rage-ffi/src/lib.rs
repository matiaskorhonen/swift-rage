use std::fs::{File, OpenOptions};
use std::io::{self, BufRead, BufReader, BufWriter, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};

use age::DecryptError;
use secrecy::ExposeSecret;
use thiserror::Error;

/// Error types for the Age wrapper.
///
/// Every variant carries the underlying error message, for logging.
#[derive(Debug, Error)]
pub enum RageError {
    /// Reading or writing a file failed.
    #[error("I/O error: {0}")]
    Io(String),
    /// The passphrase did not decrypt the file.
    #[error("Wrong passphrase: {0}")]
    WrongPassphrase(String),
    /// None of the identities could decrypt the file.
    #[error("No matching identity: {0}")]
    NoMatchingIdentity(String),
    /// The file was encrypted with a passphrase, but identities were given.
    #[error("File is encrypted with a passphrase: {0}")]
    EncryptedWithPassphrase(String),
    /// The file was encrypted to recipients, but a passphrase was given.
    #[error("File is encrypted to recipients: {0}")]
    EncryptedToRecipients(String),
    /// A key is invalid or of an unsupported type.
    #[error("Invalid key: {0}")]
    InvalidKey(String),
    /// The input is not a well-formed age file (binary or armored).
    #[error("Malformed input: {0}")]
    MalformedInput(String),
    /// The file's scrypt work factor exceeds the accepted maximum.
    #[error("Excessive work factor: {0}")]
    ExcessiveWorkFactor(String),
    /// A recipient is invalid or of an unsupported type.
    #[error("Invalid recipient: {0}")]
    InvalidRecipient(String),
    /// Encryption failed for a reason other than I/O.
    #[error("Encryption failed: {0}")]
    EncryptionFailed(String),
    /// The SSH private key is encrypted, and no passphrase was given.
    #[error("SSH key passphrase required: {0}")]
    SshPassphraseRequired(String),
    /// The passphrase did not decrypt the SSH private key.
    #[error("Wrong SSH key passphrase: {0}")]
    SshWrongPassphrase(String),
    /// The SSH key is neither ssh-ed25519 nor ssh-rsa.
    #[error("Unsupported SSH key algorithm: {0}")]
    SshUnsupportedAlgorithm(String),
    /// The SSH RSA key is larger than 4096 bits.
    #[error("SSH key too large: {0}")]
    SshKeyTooLarge(String),
}

impl From<io::Error> for RageError {
    fn from(err: io::Error) -> Self {
        RageError::Io(err.to_string())
    }
}

/// An x25519 identity (private key), or an unencrypted OpenSSH private key
#[derive(Clone)]
pub struct Identity {
    pub key_data: String,
}

/// An x25519 or SSH recipient (public key)
#[derive(Clone)]
pub struct Recipient {
    pub key_data: String,
}

/// Public information about an x25519 identity
pub struct IdentityInfo {
    pub recipient: String,
    pub key_type: String,
}

/// A parsed and, if necessary, decrypted OpenSSH private key
pub struct SshIdentity {
    pub private_key: String,
    pub public_key: String,
    pub fingerprint: String,
    pub algorithm: String,
}

/// Metadata about an Age encrypted file, read from its header
pub struct FileMetadata {
    pub is_armored: bool,
    pub stanza_types: Vec<String>,
    pub scrypt_work_factor: Option<u8>,
}

const X25519_IDENTITY_PREFIX: &str = "AGE-SECRET-KEY-";
const X25519_KEY_TYPE: &str = "age-x25519";
const MAX_RSA_BITS: usize = 4096;

// MARK: - Keys

/// Generate a new x25519 identity
pub fn generate_identity() -> Result<Identity, RageError> {
    let identity = age::x25519::Identity::generate();
    Ok(Identity {
        key_data: identity.to_string().expose_secret().to_string(),
    })
}

fn parse_x25519_identity(identity_str: &str) -> Result<age::x25519::Identity, RageError> {
    identity_str
        .trim()
        .parse()
        .map_err(|e| RageError::InvalidKey(format!("Failed to parse identity: {e}")))
}

/// Parse an x25519 identity from a string (Bech32 encoded)
pub fn parse_identity(identity_str: String) -> Result<Identity, RageError> {
    let identity = parse_x25519_identity(&identity_str)?;
    Ok(Identity {
        key_data: identity.to_string().expose_secret().to_string(),
    })
}

/// Get the recipient (public key) for an x25519 identity
pub fn identity_to_recipient(identity: Identity) -> Result<Recipient, RageError> {
    let ident = parse_x25519_identity(&identity.key_data)?;
    Ok(Recipient {
        key_data: ident.to_public().to_string(),
    })
}

/// Get the recipient and key type for an x25519 identity
pub fn identity_info(identity: Identity) -> Result<IdentityInfo, RageError> {
    let ident = parse_x25519_identity(&identity.key_data)?;
    Ok(IdentityInfo {
        recipient: ident.to_public().to_string(),
        key_type: X25519_KEY_TYPE.to_string(),
    })
}

/// Parse an OpenSSH private key (ed25519 or RSA), decrypting it with `passphrase` if needed
pub fn parse_ssh_identity(
    private_key: String,
    passphrase: Option<String>,
) -> Result<SshIdentity, RageError> {
    let mut key = ssh_key::PrivateKey::from_openssh(private_key.trim())
        .map_err(|e| RageError::InvalidKey(format!("Failed to parse SSH private key: {e}")))?;

    if key.is_encrypted() {
        let passphrase = match passphrase.as_deref() {
            Some(p) if !p.is_empty() => p,
            _ => {
                return Err(RageError::SshPassphraseRequired(
                    "The SSH private key is encrypted".to_string(),
                ))
            }
        };
        key = key
            .decrypt(passphrase)
            .map_err(|e| RageError::SshWrongPassphrase(e.to_string()))?;
    }

    let algorithm = match key.algorithm() {
        ssh_key::Algorithm::Ed25519 => "ssh-ed25519",
        ssh_key::Algorithm::Rsa { .. } => "ssh-rsa",
        other => {
            return Err(RageError::SshUnsupportedAlgorithm(format!(
                "{other} keys are not supported"
            )))
        }
    };

    if let Some(rsa) = key.key_data().rsa() {
        let bits = rsa.public.n.as_positive_bytes().map_or(0, |n| n.len() * 8);
        if bits > MAX_RSA_BITS {
            return Err(RageError::SshKeyTooLarge(format!(
                "RSA key has {bits} bits, the maximum is {MAX_RSA_BITS}"
            )));
        }
    }

    let unencrypted = key
        .to_openssh(ssh_key::LineEnding::LF)
        .map_err(|e| RageError::InvalidKey(format!("Failed to encode SSH private key: {e}")))?;
    let public_key = key
        .public_key()
        .to_openssh()
        .map_err(|e| RageError::InvalidKey(format!("Failed to encode SSH public key: {e}")))?;

    // Make sure age can use the key before handing it out
    parse_ssh_age_identity(&unencrypted)?;

    Ok(SshIdentity {
        private_key: unencrypted.to_string(),
        public_key,
        fingerprint: key.fingerprint(ssh_key::HashAlg::Sha256).to_string(),
        algorithm: algorithm.to_string(),
    })
}

fn parse_ssh_age_identity(private_key: &str) -> Result<age::ssh::Identity, RageError> {
    let identity = age::ssh::Identity::from_buffer(private_key.as_bytes(), None)
        .map_err(|e| RageError::InvalidKey(format!("Failed to parse SSH private key: {e}")))?;
    match identity {
        age::ssh::Identity::Unencrypted(_) => Ok(identity),
        age::ssh::Identity::Encrypted(_) => Err(RageError::InvalidKey(
            "Encrypted SSH keys must be unlocked with parse_ssh_identity first".to_string(),
        )),
        age::ssh::Identity::Unsupported(_) => Err(RageError::SshUnsupportedAlgorithm(
            "The SSH key type is not supported by age".to_string(),
        )),
    }
}

/// Parse an x25519 identity or an unencrypted OpenSSH private key
fn parse_any_identity(key_data: &str) -> Result<Box<dyn age::Identity>, RageError> {
    let key_data = key_data.trim();
    if key_data.starts_with(X25519_IDENTITY_PREFIX) {
        Ok(Box::new(parse_x25519_identity(key_data)?))
    } else if key_data.starts_with("-----BEGIN") {
        Ok(Box::new(parse_ssh_age_identity(key_data)?))
    } else {
        Err(RageError::InvalidKey(
            "Expected an AGE-SECRET-KEY-1... identity or an OpenSSH private key".to_string(),
        ))
    }
}

/// Parse an x25519 (age1...) or SSH (ssh-ed25519/ssh-rsa) recipient
fn parse_any_recipient(recipient_str: &str) -> Result<Box<dyn age::Recipient + Send>, RageError> {
    let recipient_str = recipient_str.trim();
    if recipient_str.starts_with("ssh-") {
        let recipient: age::ssh::Recipient = recipient_str.parse().map_err(|e| {
            RageError::InvalidRecipient(format!("Failed to parse SSH recipient: {e:?}"))
        })?;
        Ok(Box::new(recipient))
    } else {
        let recipient: age::x25519::Recipient = recipient_str
            .parse()
            .map_err(|e| RageError::InvalidRecipient(format!("Failed to parse recipient: {e}")))?;
        Ok(Box::new(recipient))
    }
}

/// Parse a recipient from a string (x25519 Bech32 or an SSH public key)
pub fn parse_recipient(recipient_str: String) -> Result<Recipient, RageError> {
    parse_any_recipient(&recipient_str)?;
    Ok(Recipient {
        key_data: recipient_str.trim().to_string(),
    })
}

// MARK: - Metadata

const ARMOR_BEGIN_MARKER: &[u8] = b"-----BEGIN AGE ENCRYPTED FILE-----";
const AGE_V1_VERSION_LINE: &str = "age-encryption.org/v1";
const MAX_HEADER_BYTES: u64 = 1024 * 1024;
const STANZA_BODY_COLUMNS: usize = 64;

/// Map an error from reading an age file: bad data is malformed input, anything else is I/O
fn read_error(err: io::Error) -> RageError {
    match err.kind() {
        io::ErrorKind::InvalidData | io::ErrorKind::UnexpectedEof => {
            RageError::MalformedInput(err.to_string())
        }
        _ => RageError::Io(err.to_string()),
    }
}

fn malformed(message: &str) -> RageError {
    RageError::MalformedInput(message.to_string())
}

/// Read one LF-terminated header line, without the line ending
fn read_header_line<R: BufRead>(reader: &mut R) -> Result<String, RageError> {
    let mut line = Vec::new();
    reader.read_until(b'\n', &mut line).map_err(read_error)?;
    if line.pop() != Some(b'\n') {
        return Err(malformed("The age header ended unexpectedly"));
    }
    String::from_utf8(line).map_err(|_| malformed("The age header is not valid UTF-8"))
}

/// Parse an age v1 header, without decrypting the file
fn parse_header<R: BufRead>(reader: &mut R) -> Result<(Vec<String>, Option<u8>), RageError> {
    let version = read_header_line(reader)?;
    if version != AGE_V1_VERSION_LINE {
        return Err(if version.starts_with("age-encryption.org/") {
            malformed(&format!("Unsupported age version: {version}"))
        } else {
            malformed("Not an age file")
        });
    }

    let mut stanza_types: Vec<String> = Vec::new();
    let mut scrypt_work_factor = None;

    loop {
        let line = read_header_line(reader)?;
        if line.starts_with("---") {
            break;
        }
        let Some(stanza) = line.strip_prefix("-> ") else {
            return Err(malformed("Invalid line in the age header"));
        };

        let mut parts = stanza.split(' ');
        let tag = parts.next().unwrap_or_default();
        if tag.is_empty() {
            return Err(malformed("Stanza without a type in the age header"));
        }
        let args: Vec<&str> = parts.collect();

        if tag == "scrypt" {
            let work_factor = args
                .get(1)
                .and_then(|log_n| log_n.parse::<u8>().ok())
                .ok_or_else(|| malformed("Invalid scrypt stanza in the age header"))?;
            scrypt_work_factor = Some(work_factor);
        }

        // age adds random "grease" stanzas so that clients don't depend on
        // the exact set of stanzas; they carry no information
        if !tag.ends_with("-grease") && !stanza_types.iter().any(|t| t == tag) {
            stanza_types.push(tag.to_string());
        }

        // The body is base64 wrapped at 64 columns; the final line is shorter
        loop {
            let body = read_header_line(reader)?;
            if body.len() > STANZA_BODY_COLUMNS {
                return Err(malformed("Invalid stanza body in the age header"));
            }
            if body.len() < STANZA_BODY_COLUMNS {
                break;
            }
        }
    }

    Ok((stanza_types, scrypt_work_factor))
}

/// Parse Age file metadata from its header, without decrypting the file
pub fn parse_file_metadata(file_path: String) -> Result<FileMetadata, RageError> {
    let mut file = File::open(&file_path)?;

    let mut prefix = Vec::new();
    (&mut file)
        .take(ARMOR_BEGIN_MARKER.len() as u64)
        .read_to_end(&mut prefix)?;
    let is_armored = prefix == ARMOR_BEGIN_MARKER;
    file.seek(SeekFrom::Start(0))?;

    // ArmoredReader passes binary files through unchanged
    let armored_reader = age::armor::ArmoredReader::new(file);
    let mut header_reader = BufReader::new(armored_reader.take(MAX_HEADER_BYTES));
    let (stanza_types, scrypt_work_factor) = parse_header(&mut header_reader)?;

    Ok(FileMetadata {
        is_armored,
        stanza_types,
        scrypt_work_factor,
    })
}

// MARK: - Encryption

/// Create a new file that only the current user can read
fn create_private_file(path: &Path) -> Result<File, RageError> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options
        .open(path)
        .map_err(|e| RageError::Io(format!("Failed to create {}: {e}", path.display())))
}

/// Stream `input` into `writer`, keeping read and write failures apart
fn copy_stream<R: Read, W: Write>(
    input: &mut R,
    writer: &mut W,
    on_read_error: fn(io::Error) -> RageError,
) -> Result<(), RageError> {
    let mut buffer = vec![0u8; 64 * 1024];
    loop {
        let count = match input.read(&mut buffer) {
            Ok(0) => return Ok(()),
            Ok(count) => count,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(on_read_error(e)),
        };
        writer.write_all(&buffer[..count])?;
    }
}

fn encrypt_to_path(
    encryptor: age::Encryptor,
    input_path: &str,
    output_path: &str,
    armor: bool,
) -> Result<(), RageError> {
    let mut input = BufReader::new(File::open(input_path)?);
    let output = File::create(output_path)?;

    let format = if armor {
        age::armor::Format::AsciiArmor
    } else {
        age::armor::Format::Binary
    };

    let result = (|| {
        let armored_writer =
            age::armor::ArmoredWriter::wrap_output(BufWriter::new(output), format)?;
        let mut writer = encryptor
            .wrap_output(armored_writer)
            .map_err(|e| RageError::EncryptionFailed(e.to_string()))?;
        copy_stream(&mut input, &mut writer, RageError::from)?;
        let mut buf_writer = writer.finish()?.finish()?;
        buf_writer.flush()?;
        Ok(())
    })();

    if result.is_err() {
        let _ = std::fs::remove_file(output_path);
    }
    result
}

/// Encrypt a file to x25519 and/or SSH recipients
pub fn encrypt_file(
    input_path: String,
    output_path: String,
    recipients: Vec<Recipient>,
    armor: bool,
) -> Result<(), RageError> {
    if recipients.is_empty() {
        return Err(RageError::EncryptionFailed(
            "At least one recipient required".to_string(),
        ));
    }

    let age_recipients = recipients
        .iter()
        .map(|r| parse_any_recipient(&r.key_data))
        .collect::<Result<Vec<_>, _>>()?;

    let encryptor = age::Encryptor::with_recipients(age_recipients)
        .ok_or_else(|| RageError::EncryptionFailed("At least one recipient required".to_string()))?;

    encrypt_to_path(encryptor, &input_path, &output_path, armor)
}

/// Encrypt a file with a passphrase
pub fn encrypt_file_with_passphrase(
    input_path: String,
    output_path: String,
    passphrase: String,
    armor: bool,
) -> Result<(), RageError> {
    let encryptor = age::Encryptor::with_user_passphrase(secrecy::Secret::new(passphrase));
    encrypt_to_path(encryptor, &input_path, &output_path, armor)
}

// MARK: - Decryption

type FileDecryptor = age::Decryptor<age::armor::ArmoredReader<BufReader<File>>>;

/// Map age's decryption errors to ours. `on_failure` covers a key that does not decrypt the file.
fn decrypt_error(err: DecryptError, on_failure: fn(String) -> RageError) -> RageError {
    match err {
        DecryptError::DecryptionFailed | DecryptError::NoMatchingKeys => {
            on_failure(err.to_string())
        }
        DecryptError::ExcessiveWork { required, target } => RageError::ExcessiveWorkFactor(
            format!("The file requires work factor {required} (this device targets {target})"),
        ),
        DecryptError::InvalidHeader | DecryptError::InvalidMac | DecryptError::UnknownFormat => {
            RageError::MalformedInput(err.to_string())
        }
        DecryptError::KeyDecryptionFailed => RageError::InvalidKey(err.to_string()),
        DecryptError::Io(e) => read_error(e),
    }
}

fn open_decryptor(input_path: &str) -> Result<FileDecryptor, RageError> {
    // ArmoredReader buffers the input, and handles both armored and binary files
    age::Decryptor::new(age::armor::ArmoredReader::new(File::open(input_path)?))
        .map_err(|e| decrypt_error(e, RageError::MalformedInput))
}

/// Where to write the plaintext: a new temporary file, or `<output_directory>/<input name minus .age>`
fn decrypted_output_path(
    input_path: &str,
    output_directory: Option<String>,
) -> Result<PathBuf, RageError> {
    let Some(directory) = output_directory else {
        return Ok(std::env::temp_dir().join(format!("age_decrypt_{}.tmp", uuid::Uuid::new_v4())));
    };

    let name = Path::new(input_path)
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| RageError::Io(format!("Invalid input path: {input_path}")))?;
    let stem = match name.len() {
        len if len > 4 && name[len - 4..].eq_ignore_ascii_case(".age") => &name[..len - 4],
        _ => name,
    };
    Ok(Path::new(&directory).join(stem))
}

fn decrypt_to_path<R: Read>(
    mut reader: R,
    input_path: &str,
    output_directory: Option<String>,
) -> Result<String, RageError> {
    let output_path = decrypted_output_path(input_path, output_directory)?;
    let mut writer = BufWriter::new(create_private_file(&output_path)?);

    let result = copy_stream(&mut reader, &mut writer, read_error)
        .and_then(|_| writer.flush().map_err(RageError::from));
    drop(writer);

    match result {
        Ok(()) => Ok(output_path.to_string_lossy().into_owned()),
        Err(e) => {
            let _ = std::fs::remove_file(&output_path);
            Err(e)
        }
    }
}

/// Decrypt a file with x25519 and/or SSH identities
pub fn decrypt_file(
    input_path: String,
    identities: Vec<Identity>,
    output_directory: Option<String>,
) -> Result<String, RageError> {
    if identities.is_empty() {
        return Err(RageError::NoMatchingIdentity(
            "At least one identity required".to_string(),
        ));
    }

    let age_identities = identities
        .iter()
        .map(|i| parse_any_identity(&i.key_data))
        .collect::<Result<Vec<_>, _>>()?;

    let decryptor = match open_decryptor(&input_path)? {
        age::Decryptor::Recipients(d) => d,
        age::Decryptor::Passphrase(_) => {
            return Err(RageError::EncryptedWithPassphrase(
                "The file was encrypted with a passphrase, not to recipients".to_string(),
            ))
        }
    };

    let reader = decryptor
        .decrypt(age_identities.iter().map(|i| i.as_ref()))
        .map_err(|e| decrypt_error(e, RageError::NoMatchingIdentity))?;

    decrypt_to_path(reader, &input_path, output_directory)
}

/// Decrypt a file with a passphrase. `max_work_factor` caps the scrypt work factor (log2 N);
/// `None` uses age's default limit.
pub fn decrypt_file_with_passphrase(
    input_path: String,
    passphrase: String,
    max_work_factor: Option<u8>,
    output_directory: Option<String>,
) -> Result<String, RageError> {
    let decryptor = match open_decryptor(&input_path)? {
        age::Decryptor::Passphrase(d) => d,
        age::Decryptor::Recipients(_) => {
            return Err(RageError::EncryptedToRecipients(
                "The file was encrypted to recipients, not with a passphrase".to_string(),
            ))
        }
    };

    let reader = decryptor
        .decrypt(&secrecy::Secret::new(passphrase), max_work_factor)
        .map_err(|e| decrypt_error(e, RageError::WrongPassphrase))?;

    decrypt_to_path(reader, &input_path, output_directory)
}

// Include the UniFFI generated scaffolding
uniffi::include_scaffolding!("swift_rage");
