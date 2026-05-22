// Phase 10 crypto subsystem. Public surface:
//   - keystore::{KeystoreState, init, unlock, change_passphrase, import, wipe, load, ...}
//   - wrap::{encrypt_field, decrypt_field}
//   - mnemonic::{dek_to_words, words_to_dek}
//   - errors::CryptoError
//   - commands::* (Tauri command functions; registered in lib.rs)

pub mod commands;
pub mod errors;
pub mod keystore;
pub mod mnemonic;
pub mod wrap;

pub use errors::CryptoError;
pub use keystore::{Dek, KeystoreState, KeystoreStatus};
