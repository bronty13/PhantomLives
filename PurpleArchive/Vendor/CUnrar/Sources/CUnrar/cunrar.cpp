// C shim implementation — bridges cunrar.h to unrar's RAR* dll API.
// rar.hpp pulls in os.hpp (which defines _UNIX / HANDLE on macOS) and the rest
// of the unrar headers; dll.hpp then declares the RAR* C API.
#include "rar.hpp"
#include "dll.hpp"
#include "cunrar.h"
#include <cstring>
#include <cstdlib>

namespace {
struct CUnrarHandle {
    HANDLE rar;
};
}

extern "C" void *cunrar_open(const char *path, const char *password,
                             int forExtract, int *openResult) {
    RAROpenArchiveDataEx data;
    std::memset(&data, 0, sizeof(data));
    data.ArcName = const_cast<char *>(path);
    data.OpenMode = forExtract ? RAR_OM_EXTRACT : RAR_OM_LIST;
    HANDLE h = RAROpenArchiveEx(&data);
    if (openResult) *openResult = (int)data.OpenResult;
    if (h == NULL || data.OpenResult != 0) {
        if (h) RARCloseArchive(h);
        return NULL;
    }
    if (password && password[0]) {
        RARSetPassword(h, const_cast<char *>(password));
    }
    CUnrarHandle *ctx = (CUnrarHandle *)std::malloc(sizeof(CUnrarHandle));
    if (!ctx) { RARCloseArchive(h); return NULL; }
    ctx->rar = h;
    return ctx;
}

extern "C" int cunrar_next(void *handle, CUnrarEntry *out) {
    CUnrarHandle *ctx = (CUnrarHandle *)handle;
    if (!ctx || !out) return -1;
    RARHeaderDataEx hd;
    std::memset(&hd, 0, sizeof(hd));
    int r = RARReadHeaderEx(ctx->rar, &hd);
    if (r == ERAR_END_ARCHIVE) return 0;
    if (r != 0) return -1;
    std::memset(out, 0, sizeof(*out));
    std::strncpy(out->name, hd.FileName, sizeof(out->name) - 1);
    out->size = ((unsigned long long)hd.UnpSizeHigh << 32) | (unsigned long long)hd.UnpSize;
    out->isDirectory = (hd.Flags & RHDF_DIRECTORY) ? 1 : 0;
    out->isEncrypted = (hd.Flags & RHDF_ENCRYPTED) ? 1 : 0;
    return 1;
}

extern "C" int cunrar_skip(void *handle) {
    CUnrarHandle *ctx = (CUnrarHandle *)handle;
    return ctx ? RARProcessFile(ctx->rar, RAR_SKIP, NULL, NULL) : -1;
}

extern "C" int cunrar_extract(void *handle, const char *destDir) {
    CUnrarHandle *ctx = (CUnrarHandle *)handle;
    return ctx ? RARProcessFile(ctx->rar, RAR_EXTRACT, const_cast<char *>(destDir), NULL) : -1;
}

extern "C" int cunrar_test(void *handle) {
    CUnrarHandle *ctx = (CUnrarHandle *)handle;
    return ctx ? RARProcessFile(ctx->rar, RAR_TEST, NULL, NULL) : -1;
}

extern "C" void cunrar_close(void *handle) {
    CUnrarHandle *ctx = (CUnrarHandle *)handle;
    if (ctx) {
        if (ctx->rar) RARCloseArchive(ctx->rar);
        std::free(ctx);
    }
}
