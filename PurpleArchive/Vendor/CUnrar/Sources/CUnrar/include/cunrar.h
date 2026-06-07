// Pure-C facade over RARLAB's unrar C++ "dll" API, so Swift can import it as a
// plain C module. unrar is extract-only freeware (see ../../LICENSE): it may be
// used to *read* RAR archives but not to create them or reverse-engineer the
// compression algorithm.
#ifndef CUNRAR_H
#define CUNRAR_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char name[2048];          // entry path (UTF-8)
    unsigned long long size;  // uncompressed size
    int isDirectory;
    int isEncrypted;
} CUnrarEntry;

/// Open `path`. `forExtract` = 0 to list, 1 to extract. `password` may be NULL.
/// Returns an opaque handle or NULL; `*openResult` gets the unrar code (0 = ok).
void *cunrar_open(const char *path, const char *password, int forExtract, int *openResult);

/// Read the next entry header. Returns 1 (filled `out`), 0 (end), <0 (error).
int cunrar_next(void *handle, CUnrarEntry *out);

/// Advance past the current entry's data without extracting.
int cunrar_skip(void *handle);

/// Extract the current entry into `destDir` (unrar applies the stored subpath).
int cunrar_extract(void *handle, const char *destDir);

/// Decompress-and-verify the current entry without writing it.
int cunrar_test(void *handle);

void cunrar_close(void *handle);

#ifdef __cplusplus
}
#endif
#endif
