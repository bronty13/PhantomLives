# Security Review — 2026-06-08

**Scope reviewed:** commit `b5063fa` ("fix(purplededup): silence last two
Swift 6 concurrency warnings") — the only change on `main` relative to
`origin/main` at review time. CHANGELOG prose plus two Swift source edits.

## Summary of changes analyzed

The entire code diff consists of Swift 6 actor-isolation annotation changes,
with no behavioral effect:

1. **`Sources/PurpleDedupApp/QuickLook/QuickLook.swift`** — the two
   `QLPreviewPanelDataSource` requirements (`numberOfPreviewItems(in:)`,
   `previewPanel(_:previewItemAt:)`) changed from `@MainActor`-isolated to
   `nonisolated`, reading the existing `items` array via
   `MainActor.assumeIsolated`. No change to how `items` is populated or to
   any data flow.
2. **`Sources/PurpleDedupCore/PhotoKit/PhotoKitDeletionService.swift`** —
   `currentStatus()` changed from an `actor` method to `nonisolated`. It
   still only wraps the read-only, thread-safe system call
   `PHPhotoLibrary.authorizationStatus(for: .readWrite)`; it grants nothing
   and mutates no state.

## Findings

**No HIGH or MEDIUM security vulnerabilities identified.**

The diff introduces no new attack surface across any reviewed category:

- **Input validation / injection** — no user input is parsed, no
  SQL/command/template/path-construction code is touched.
- **Auth & authorization** — `currentStatus()` is a read-only status getter;
  making it `nonisolated` does not bypass or weaken any authorization
  decision (PhotoKit still gates actual library access).
- **Crypto & secrets** — none touched; no keys, tokens, or randomness
  involved.
- **Code execution / deserialization** — none.
- **Data exposure** — no logging, serialization, or PII handling added.

The only conceivable runtime concern — `MainActor.assumeIsolated` trapping if
`QLPreviewPanel` ever invoked the data source off the main thread — is a
crash/DOS-class concern (explicitly out of scope) and not reachable in
practice, since `QLPreviewPanel` is documented to call its data source on the
main thread.

No candidate findings reached the reporting confidence threshold, so no
false-positive filtering sub-tasks were warranted.
