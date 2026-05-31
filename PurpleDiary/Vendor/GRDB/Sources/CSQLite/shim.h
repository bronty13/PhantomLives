// PurpleLife local modification: pull in SQLCipher's sqlite3.h
// directly instead of `<sqlite3.h>`. The angle-bracket form would
// resolve via the SDK and tag GRDB's compiled symbol references with
// libsqlite3.dylib (two-level namespace), which then makes runtime
// calls go to the system SQLite even though our static SQLCipher
// symbols are also in the binary. The quoted include forces Clang to
// search project-local paths first, finding the SQLCipher target's
// header — and the SwiftPM dep on `SQLCipher` (added to this CSQLite
// target's deps) makes the linker tag the resulting bindings with the
// SQLCipher target. End result: GRDB → SQLCipher at runtime.
@import SQLCipher;

typedef void(*_errorLogCallback)(void *pArg, int iErrCode, const char *zMsg);

/// Wrapper around sqlite3_config(SQLITE_CONFIG_LOG, ...) which is a variadic
/// function that can't be used from Swift.
static inline void _registerErrorLogCallback(_errorLogCallback callback) {
    sqlite3_config(SQLITE_CONFIG_LOG, callback, 0);
}

#if SQLITE_VERSION_NUMBER >= 3029000
/// Wrapper around sqlite3_db_config() which is a variadic function that can't
/// be used from Swift.
static inline void _disableDoubleQuotedStringLiterals(sqlite3 *db) {
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DDL, 0, (void *)0);
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DML, 0, (void *)0);
}

/// Wrapper around sqlite3_db_config() which is a variadic function that can't
/// be used from Swift.
static inline void _enableDoubleQuotedStringLiterals(sqlite3 *db) {
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DDL, 1, (void *)0);
    sqlite3_db_config(db, SQLITE_DBCONFIG_DQS_DML, 1, (void *)0);
}
#else
static inline void _disableDoubleQuotedStringLiterals(sqlite3 *db) { }
static inline void _enableDoubleQuotedStringLiterals(sqlite3 *db) { }
#endif

// Expose APIs that are missing from system <sqlite3.h>
#ifdef GRDB_SQLITE_ENABLE_PREUPDATE_HOOK
SQLITE_API void *sqlite3_preupdate_hook(
  sqlite3 *db,
  void(*xPreUpdate)(
    void *pCtx,                   /* Copy of third arg to preupdate_hook() */
    sqlite3 *db,                  /* Database handle */
    int op,                       /* SQLITE_UPDATE, DELETE or INSERT */
    char const *zDb,              /* Database name */
    char const *zName,            /* Table name */
    sqlite3_int64 iKey1,          /* Rowid of row about to be deleted/updated */
    sqlite3_int64 iKey2           /* New rowid value (for a rowid UPDATE) */
  ),
  void*
);
SQLITE_API int sqlite3_preupdate_old(sqlite3 *, int, sqlite3_value **);
SQLITE_API int sqlite3_preupdate_count(sqlite3 *);
SQLITE_API int sqlite3_preupdate_depth(sqlite3 *);
SQLITE_API int sqlite3_preupdate_new(sqlite3 *, int, sqlite3_value **);
#endif /* GRDB_SQLITE_ENABLE_PREUPDATE_HOOK */
