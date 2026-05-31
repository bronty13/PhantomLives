# SQLCipher provenance

This directory ships a vendored, locally-built copy of SQLCipher. The
file `Sources/SQLCipher/sqlite3.c` is the SQLCipher amalgamation built
against:

| Field | Value |
|---|---|
| Upstream repo | https://github.com/sqlcipher/sqlcipher |
| Tag | `v4.6.1` |
| Tarball URL | https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.6.1.tar.gz |
| Tarball SHA-256 | `d8f9afcbc2f4b55e316ca4ada4425daf3d0b4aab25f45e11a802ae422b9f53a3` |
| Build date | 2026-05-11 |
| Built by | Vendored as part of slice A2 of the encryption-foundation work |

## How the amalgamation was produced

The SQLCipher source archive was extracted, configured with the
CommonCrypto crypto backend (so Apple's CryptoKit / CommonCrypto
provides AES, not OpenSSL or LibTomCrypt — keeps us self-contained
without a `brew install openssl` dependency), and the amalgamation
target invoked:

```
curl -sL -o sqlcipher.tar.gz \
  https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.6.1.tar.gz

# Verify
shasum -a 256 sqlcipher.tar.gz
# Expected: d8f9afcbc2f4b55e316ca4ada4425daf3d0b4aab25f45e11a802ae422b9f53a3

tar xzf sqlcipher.tar.gz
cd sqlcipher-4.6.1

./configure --enable-tempstore=yes --disable-tcl \
            --with-crypto-lib=commoncrypto \
            CFLAGS="-DSQLITE_HAS_CODEC -DSQLCIPHER_CRYPTO_CC \
                    -DSQLITE_ENABLE_FTS5 -DSQLITE_THREADSAFE=1 \
                    -DSQLITE_DEFAULT_MEMSTATUS=0 \
                    -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1 \
                    -DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
                    -DSQLITE_OMIT_DEPRECATED -DSQLITE_DQS=0 \
                    -DHAVE_USLEEP=1 -DSQLITE_MAX_EXPR_DEPTH=0 \
                    -DSQLITE_USE_URI" \
            LDFLAGS="-framework Security -framework Foundation"

make sqlite3.c
```

The resulting `sqlite3.c` (~9.3 MB) and `sqlite3.h` (~646 KB) were
copied into `Sources/SQLCipher/`. Identical compile-time `-D` flags
are re-applied in `Package.swift` so the SwiftPM build of this target
produces a binary equivalent to what `./configure` originally
intended.

## Updating SQLCipher

When a new SQLCipher release lands:

1. Update the tag + tarball SHA-256 in the table above.
2. Re-run the build recipe above against the new tarball.
3. Copy the new `sqlite3.c` and `sqlite3.h` over the existing files.
4. Re-run `./run-tests.sh` from the PurpleLife root to verify the
   integration still holds. Special attention to:
   - `AtRestEncryptionTests` (the slice A2 SQLCipher round-trip tests)
   - All existing 165 tests (the migration shouldn't regress anything)
5. Bump the `Build date` field above and add a one-line `CHANGELOG.md`
   entry: "SQLCipher vendored amalgamation updated to vX.Y.Z".

No SwiftPM `Package.swift` change is needed for a pure SQLCipher
version bump — only the C source + provenance metadata change.
