// swift-tools-version:5.7
import PackageDescription

/// Local SwiftPM package wrapping SQLCipher 4.6.1.
///
/// The C source (`Sources/SQLCipher/sqlite3.c`) is the SQLCipher
/// amalgamation produced by `make sqlite3.c` against
/// https://github.com/sqlcipher/sqlcipher tag v4.6.1. See
/// `PROVENANCE.md` for the tarball SHA-256 and build flags used.
///
/// Build flags align with what SQLCipher's `./configure` set + the
/// FTS5 + URI flags PurpleLife depends on (PurpleLife's FTS5-backed
/// `objects_fts` search index is non-negotiable). `SQLITE_HAS_CODEC` +
/// `SQLCIPHER_CRYPTO_CC` activate SQLCipher's encryption layer over
/// Apple's CommonCrypto — no OpenSSL dependency, no Homebrew install
/// required on the build host or any consuming machine.
let package = Package(
    name: "SQLCipher",
    products: [
        .library(name: "SQLCipher", targets: ["SQLCipher"]),
    ],
    targets: [
        .target(
            name: "SQLCipher",
            path: "Sources/SQLCipher",
            sources: ["sqlite3.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_HAS_CODEC"),
                .define("SQLCIPHER_CRYPTO_CC"),
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_TEMP_STORE", to: "2"),
                .define("SQLITE_ENABLE_FTS5"),
                .define("SQLITE_USE_URI"),
                .define("SQLITE_DEFAULT_MEMSTATUS", to: "0"),
                .define("SQLITE_DEFAULT_WAL_SYNCHRONOUS", to: "1"),
                .define("SQLITE_LIKE_DOESNT_MATCH_BLOBS"),
                .define("SQLITE_OMIT_DEPRECATED"),
                .define("SQLITE_DQS", to: "0"),
                .define("HAVE_USLEEP", to: "1"),
                .define("SQLITE_MAX_EXPR_DEPTH", to: "0"),
                // GRDB calls into the WAL snapshot APIs (sqlite3_snapshot_*).
                // SQLite gates these behind SQLITE_ENABLE_SNAPSHOT. Without
                // it the symbols are #ifdef'd out and the linker fails on
                // GRDB's `DatabaseSnapshotPool` references.
                .define("SQLITE_ENABLE_SNAPSHOT"),
                // GRDB's column-metadata introspection (table schema, column
                // origin tracking) calls sqlite3_table_column_metadata.
                .define("SQLITE_ENABLE_COLUMN_METADATA"),
                // NDEBUG: SQLCipher's amalgamation includes helper-function
                // calls inside `assert()` macros. C99 strict mode flags the
                // implicit declarations as errors. Defining NDEBUG turns the
                // asserts into no-ops, which both removes the calls and
                // matches what Zetetic's own SQLCipher release builds use.
                .define("NDEBUG"),
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
