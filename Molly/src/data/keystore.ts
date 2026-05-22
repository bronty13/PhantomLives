import { invoke } from '@tauri-apps/api/core';

// Phase 10 keystore — typed wrappers for the crypto Tauri commands.
// The Rust side owns all key material; the frontend only sees
// (initialized, unlocked, version, unlockedSecs) status flags +
// decrypted plaintext on demand for clipboard use.

export interface KeystoreStatus {
  initialized: boolean;
  unlocked: boolean;
  version: number;
  unlockedSecs: number | null;
}

export interface EncryptedField {
  ciphertext: string;
  dekVersion: number;
}

export interface MnemonicWords {
  words: string[];
}

/** Discriminated error returned by every crypto command. */
export interface CryptoErrorPayload {
  kind:
    | 'notInitialized' | 'locked' | 'alreadyInitialized' | 'unauthorized'
    | 'passphraseTooShort' | 'decryptionFailed' | 'checksumInvalid'
    | 'mnemonicWrongLength' | 'mnemonicWordUnknown' | 'badCiphertextFormat'
    | 'db' | 'io' | 'internal';
  message: string;
}

export async function getKeystoreStatus(): Promise<KeystoreStatus> {
  return invoke<KeystoreStatus>('keystore_status');
}

export async function initKeystore(passphrase: string): Promise<void> {
  await invoke('init_keystore', { passphrase });
}

export async function unlockKeystore(passphrase: string): Promise<KeystoreStatus> {
  return invoke<KeystoreStatus>('unlock_keystore', { passphrase });
}

export async function lockKeystore(): Promise<void> {
  await invoke('lock_keystore');
}

export async function changePassphrase(oldPassphrase: string, newPassphrase: string): Promise<void> {
  await invoke('change_passphrase', { oldPassphrase, newPassphrase });
}

export async function encryptField(plaintext: string): Promise<EncryptedField> {
  return invoke<EncryptedField>('encrypt_field', { plaintext });
}

export async function decryptField(ciphertext: string, dekVersion: number): Promise<string> {
  return invoke<string>('decrypt_field', { ciphertext, dekVersion });
}

export async function exportKeystoreMnemonic(): Promise<MnemonicWords> {
  return invoke<MnemonicWords>('export_keystore_mnemonic');
}

export async function importKeystoreFromMnemonic(
  words: string[],
  newPassphrase: string,
): Promise<KeystoreStatus> {
  return invoke<KeystoreStatus>('import_keystore_from_mnemonic', {
    payload: { words, newPassphrase },
  });
}

export async function wipeKeystore(alsoWipeData: boolean): Promise<void> {
  await invoke('wipe_keystore', { alsoWipeData });
}
