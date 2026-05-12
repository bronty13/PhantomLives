import SQLCipher

/// Force-link shim for the vendored SQLCipher.
///
/// SwiftPM packages a C target as a static archive. The Apple linker
/// only extracts `.o` files from a static archive when something
/// references their symbols by name. GRDB calls `sqlite3_*` functions
/// through its `CSQLite` system-library import — those references get
/// resolved against the *system* `libsqlite3.dylib` (which GRDB's
/// CSQLite module map pulls in via `link "sqlite3"`), so the linker
/// never bothers to crack open our static SQLCipher archive.
///
/// This file imports the `SQLCipher` module (which exists only in our
/// vendored target) and takes the address of `sqlite3_libversion` —
/// one symbol from our archive. That forces the linker to extract
/// our `sqlite3.c.o`, which in turn defines all the other
/// `sqlite3_*` symbols, which then shadow the system ones at link
/// time. Once shadowed, GRDB's `sqlite3_open_v2` etc. resolve to
/// SQLCipher.
///
/// Verified at runtime by `AtRestEncryptionTests.test_sqlcipherIsActuallyLinked`,
/// which runs `PRAGMA cipher_version` — a SQLCipher-only PRAGMA that
/// returns NULL when the system libsqlite3 is in play.
enum SQLCipherForceLink {
    /// Touched once at module-init time so the optimizer can't decide
    /// the symbol reference is dead. Returns the SQLCipher version
    /// string for the curious; nothing depends on the return value.
    @discardableResult
    static func touch() -> String {
        guard let cString = sqlite3_libversion() else { return "" }
        return String(cString: cString)
    }

    /// Module-init eagerly references the symbol so the linker has no
    /// choice but to pull our archive into the binary. Without this,
    /// SwiftPM's "extract only referenced object files from static
    /// archives" behavior would keep our SQLCipher's symbols out of
    /// the final binary entirely.
    static let _force: Bool = {
        _ = touch()
        return true
    }()
}
