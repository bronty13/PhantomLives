// Intentionally empty. CSQLite carries no symbols of its own — it
// only re-exports SQLCipher's sqlite3 API via the umbrella header
// `shim.h`. SwiftPM requires a target to have at least one source
// file; this empty .c satisfies that without contributing anything.
//
// The work happens in:
//   * `shim.h` — `@import SQLCipher;` plus the inline wrappers GRDB
//     uses for variadic SQLite functions.
//   * `Package.swift` — declares this CSQLite target with a real-target
//     dependency on the local `SQLCipher` package, which is what makes
//     GRDB's compiled symbol bindings tag against SQLCipher's binary
//     instead of libsqlite3.dylib.
