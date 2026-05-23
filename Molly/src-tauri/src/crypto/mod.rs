// Phase 10 crypto subsystem. Public surface:
//   - keystore::{KeystoreState, init, unlock, change_passphrase, import, wipe, load, ...}
//   - wrap::{encrypt_field, decrypt_field}
//   - mnemonic::{dek_to_words, words_to_dek}
//   - errors::CryptoError
//   - commands::* (Tauri command functions; registered in lib.rs)

pub mod commands;
pub mod errors;
pub mod keychain;
pub mod keystore;
pub mod mnemonic;
pub mod wrap;

pub use errors::CryptoError;
// Dek + KeystoreStatus re-exported for outside callers (commands wrap them).
// KeystoreState is used directly by `manage(KeystoreState::new_arc())` in lib.rs.
#[allow(unused_imports)]
pub use keystore::{Dek, KeystoreState, KeystoreStatus};
