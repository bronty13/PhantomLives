-- Phase 10: AES-256-GCM keystore for site passwords + (later) ATW
-- credentials. Single-row table; first `init_keystore` Tauri command
-- generates a 16-byte random salt + a 32-byte random DEK, derives a
-- KEK from the user's passphrase via PBKDF2-HMAC-SHA256 (300k iter),
-- and writes back (salt_b64, wrapped_dek_b64).
--
-- Storing the keystore in SQLite (not a sidecar JSON) means Molly's
-- existing backup ZIPs automatically capture it — no extra wiring.
--
-- Design ported from PurpleIRC's KeyStore + EncryptedJSON (Swift →
-- Rust); see HANDOFF for cross-reference notes.

CREATE TABLE IF NOT EXISTS crypto_keystore (
    id              INTEGER PRIMARY KEY CHECK (id = 1),
    salt_b64        TEXT,
    kdf_iterations  INTEGER NOT NULL DEFAULT 300000,
    kdf_algo        TEXT    NOT NULL DEFAULT 'PBKDF2-HMAC-SHA256',
    wrapped_dek_b64 TEXT,
    dek_version     INTEGER NOT NULL DEFAULT 1,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Singleton row; NULL columns mean "not initialized yet."
INSERT OR IGNORE INTO crypto_keystore (id) VALUES (1);
