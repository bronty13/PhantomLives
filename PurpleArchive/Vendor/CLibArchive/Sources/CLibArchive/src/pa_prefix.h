/*
 * PurpleArchive force-include prefix for the vendored libarchive sources.
 *
 * SwiftPM and Xcode define `DEBUG=1` on the compiler command line in debug
 * configurations. libarchive gates noisy `fprintf(stderr, "Header id …")` /
 * mtime diagnostics behind `#ifdef DEBUG`, so a debug build would spew on every
 * zip read. A command-line `-UDEBUG` is order-sensitive and unreliable; a
 * force-included header (`-include pa_prefix.h`) is injected at the very top of
 * each translation unit, AFTER command-line macros are established, so this
 * #undef deterministically wins regardless of flag order.
 *
 * This file is PurpleArchive's, not part of the upstream libarchive tree.
 */
#ifdef DEBUG
#undef DEBUG
#endif
