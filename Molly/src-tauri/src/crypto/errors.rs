// CryptoError — every variant intentionally generic. The frontend
// surfaces these messages directly to Sallie, so error text must NOT
// leak side-channel information about whether a passphrase was "close"
// or which step inside the unwrap chain failed. "Unauthorized" covers
// both "wrong passphrase" and "tampered ciphertext"; "DecryptionFailed"
// covers any AEAD tag mismatch on a non-keystore blob.

use std::time::SystemTimeError;

#[derive(Debug, thiserror::Error)]
pub enum CryptoError {
    #[error("keystore is not initialized — set a passphrase in Settings → Security")]
    NotInitialized,
    #[error("keystore is locked — unlock in Settings → Security")]
    Locked,
    #[error("keystore is already initialized")]
    AlreadyInitialized,
    #[error("passphrase rejected")]
    Unauthorized,
    #[error("passphrase is too short (need at least 10 characters)")]
    PassphraseTooShort,
    #[error("decryption failed (data may be corrupt or encrypted with a different key)")]
    DecryptionFailed,
    #[error("mnemonic checksum failed — re-check the 24 words")]
    ChecksumInvalid,
    #[error("mnemonic has unexpected length (need exactly 24 words)")]
    MnemonicWrongLength,
    #[error("mnemonic word #{idx} is not in the BIP-39 English word list")]
    MnemonicWordUnknown { idx: usize, word: String },
    #[error("ciphertext is malformed (bad version byte or truncated)")]
    BadCiphertextFormat,
    #[error("db: {0}")]
    Db(String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("internal: {0}")]
    Internal(String),
}

impl From<rusqlite::Error> for CryptoError {
    fn from(e: rusqlite::Error) -> Self {
        CryptoError::Db(e.to_string())
    }
}

impl From<SystemTimeError> for CryptoError {
    fn from(e: SystemTimeError) -> Self {
        CryptoError::Internal(format!("system clock: {e}"))
    }
}

impl serde::Serialize for CryptoError {
    fn serialize<S: serde::Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        // Generic envelope so frontend can dispatch on `kind` but never
        // see implementation detail (e.g. which crate threw what).
        use serde::ser::SerializeStruct;
        let mut st = s.serialize_struct("CryptoError", 2)?;
        st.serialize_field("kind", self.kind_tag())?;
        st.serialize_field("message", &self.to_string())?;
        st.end()
    }
}

impl CryptoError {
    fn kind_tag(&self) -> &'static str {
        match self {
            CryptoError::NotInitialized => "notInitialized",
            CryptoError::Locked => "locked",
            CryptoError::AlreadyInitialized => "alreadyInitialized",
            CryptoError::Unauthorized => "unauthorized",
            CryptoError::PassphraseTooShort => "passphraseTooShort",
            CryptoError::DecryptionFailed => "decryptionFailed",
            CryptoError::ChecksumInvalid => "checksumInvalid",
            CryptoError::MnemonicWrongLength => "mnemonicWrongLength",
            CryptoError::MnemonicWordUnknown { .. } => "mnemonicWordUnknown",
            CryptoError::BadCiphertextFormat => "badCiphertextFormat",
            CryptoError::Db(_) => "db",
            CryptoError::Io(_) => "io",
            CryptoError::Internal(_) => "internal",
        }
    }
}
