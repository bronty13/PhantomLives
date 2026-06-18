# Research spike: eliminating the recurring TCC prompt

**Date:** 2026-06-18 · **Status:** ✅ **Tier 1 implemented** (see CHANGELOG) · **Author:** spike

> **Outcome:** Tier 1 shipped. Video metadata now embeds via the exiftool `Keys:` group and
> imports natively; `PhotosAppleScriptService`, the "Re-apply Metadata" feature, and the
> `com.apple.security.automation.apple-events` entitlement were removed. The load-bearing
> assumption below — *does Photos ingest `Keys:` video tags on import?* — was **verified
> 2026-06-18**: a tagged clip imported with the right Title/Caption and the comma-joined
> `Keys:Keywords` string split into individual keywords. The standard one-time Photos-access
> prompt is now the app's only TCC prompt. The Tier 0 signing-stability hardening
> (build-app.sh ad-hoc fallback) is still worth doing to protect the *Photos* grant during dev,
> but is no longer load-bearing for an automation prompt that no longer exists.

The original research follows, unchanged.

## The problem

Users see a TCC consent prompt on (apparently) every run. Shipping an app that
re-prompts on each launch is not professional — a well-behaved macOS app prompts
**once, ever**, for each capability it genuinely needs. This spike identifies which
prompt is firing, why it recurs, what comparable commercial apps do, and lays out a
spectrum of fixes from a one-line hardening to a small re-architecture.

## What actually triggers TCC in PurplePeek

PurplePeek touches **two distinct TCC surfaces**, and they behave very differently:

| Surface | API | When it fires | Persistence |
|---|---|---|---|
| **Photos library** | `PHPhotoLibrary.requestAuthorization(for: .readWrite)` (`PhotoKitService`) | First import / first album fetch | **Reliable** — standard system prompt, keyed to the app's code requirement. Every photo app shows this once; it is expected and professional. |
| **Apple Events / Automation** | `NSAppleScript` → `tell application "Photos" …` (`PhotosAppleScriptService`) | Importing a **video** (or any photo whose metadata couldn't be embedded), and **Re-apply Metadata** | **Fragile** — the *"PurplePeek wants to control Photos"* prompt. This is the one that recurs. |

The Apple Events prompt exists for one reason: **PhotoKit cannot write `title`/`caption`/`keywords`.**
The complete writable surface of `PHAssetChangeRequest`/`PHAssetCreationRequest` is
`creationDate`, `location`, `isFavorite`, `isHidden`, and `contentEditingOutput` — nothing
descriptive. (Confirmed against Apple's PhotoKit docs; these properties have been stable
since iOS 8 and macOS 14/15 add nothing.) So to get title/caption/keywords onto an asset,
there are only two routes: (a) **embed them in the file before import** so Photos ingests
them, or (b) **drive Photos via Apple Events after import**. PurplePeek already does (a) for
photos (`MetadataStagingService` + exiftool) and falls back to (b) for videos — and (b) is
what triggers the recurring prompt.

## Why it recurs (ranked)

For a correctly Developer-ID-signed, hardened-runtime app with the
`com.apple.security.automation.apple-events` entitlement and `NSAppleEventsUsageDescription`
(PurplePeek has all of these), the Automation grant **should persist after the first "OK".**
TCC keys the grant to the **(source app, target app)** pair, where the source is identified
by its **code-signing designated requirement (DR)**. Recurrence means the DR isn't stable, or
the app's path keeps changing. In likelihood order for this project:

1. **Ad-hoc signing fallback (most likely during dev).** `build-app.sh`'s
   `detect_codesign_identity` falls back to ad-hoc (`codesign -s -`) whenever
   `security find-identity` returns nothing — which happens when codesign runs in a
   **sandboxed** Bash that can't read the login Keychain (a known PhantomLives gotcha; see
   the "Release sandbox/Keychain" memory). An ad-hoc signature has **no certificate**, so the
   DR collapses to the binary's **cdhash**, which changes on **every build**. TCC then treats
   each build as a brand-new app and re-prompts. Worse, *alternating* between ad-hoc and
   Developer-ID builds under the same bundle ID "makes TCC get confused and treat the
   permissions as not granted" (Apple DTS). The currently-installed `/Applications/PurplePeek.app`
   *is* Developer-ID signed (verified), so the recurrence is most visible during iterative
   dev builds — but any ad-hoc build a user ever runs poisons the grant.
2. **App Translocation.** A quarantined app launched from a DMG/Downloads runs from a
   randomized read-only path that differs each launch, which breaks grant persistence. Not a
   factor for the `/Applications` install (our `install.sh` uses `ditto --noextattr`, stripping
   quarantine), but it *would* bite a user who runs the app straight out of a downloaded DMG.
3. **Event timing / target state.** Sending the event before Photos is running, or without
   pre-flighting, can surface an avoidable prompt. Minor, but cheap to harden.

> `AEDeterminePermissionToAutomateTarget` is a **pre-flight**, not a persistence fix — it lets
> you check status (`askUserIfNeeded: false`) and prompt deliberately once at a good moment,
> and detect denial (`-1743`) instead of re-firing. It does not make a grant stick.

## What comparable commercial apps do

The field is unanimous: **serious tools avoid per-asset AppleScript writes to Photos.**

| App | Approach to Photos metadata |
|---|---|
| **osxphotos** (the reference CLI) | **Embed-then-import.** Writes `IPTC:Keywords`, `XMP:Title`/`IPTC:ObjectName`, `IPTC:Caption-Abstract` via exiftool; documents that "Photos will read on import keyword, title, description, location." AppleScript only for *reading* the live library, never per-asset metadata writes. |
| **GraphicConverter** (Lemkesoft) | Pure embed-then-import; **"does not talk directly to Photos."** Edit IPTC/XMP on disk, re-import. |
| **Lightroom Classic** | No native "Add to Photos" — export JPEGs with embedded IPTC/XMP, import those. |
| **Mylio** | Embeds caption/title/keywords in exported files; hands off, never automates Photos. |
| **PhotoSweeper** | **Mark, don't mutate** — moves duplicates to a special album in Photos for the user to delete; avoids deep write-automation. |
| **PowerPhotos** (Fat Cat Software) | Edits the **live library directly** (title/keywords/caption, batch) as a stably-signed notarized app — not per-edit AppleScript round-trips. |

None of them surface a recurring Automation prompt. The consensus diagnosis for a recurring
prompt, across developer blogs and forums, is **unstable/ad-hoc signing** — exactly cause #1.

## Solution spectrum

### Tier 0 — Make the *existing* prompt fire only once (no architecture change)

Cheapest path; keeps the AppleScript fallback but stops it re-prompting.

- **Guarantee stable Developer-ID signing for every build.** Harden
  `detect_codesign_identity` so a missing identity is a **hard error** (or runs `security
  find-identity` with the sandbox disabled), instead of silently falling back to ad-hoc. An
  ad-hoc build should never reach `/Applications` or a user. This is the single highest-value
  change and directly kills cause #1.
- **Keep stripping quarantine on install** (already done) and document "install to
  /Applications; don't run from the DMG" to avoid translocation (cause #2).
- **Pre-flight the prompt** with `AEDeterminePermissionToAutomateTarget(…, typeWildCard,
  typeWildCard, askUserIfNeeded: true)` once, at a deliberate moment (e.g. when the user first
  starts an import that includes a video), and handle `-1743` (denied) gracefully instead of
  re-firing `NSAppleScript` per item.

**Outcome:** the Automation prompt appears once and persists. Acceptable, but the app still
ships a second, scarier-sounding permission ("control Photos") on top of the normal Photos
prompt.

### Tier 1 — Eliminate the Apple Events prompt entirely (recommended)

Extend the embed-then-import pattern the app already uses for photos to **videos**, then
delete the AppleScript path. Videos use QuickTime metadata atoms, not IPTC/XMP, and Photos
**does** ingest them on import via exiftool's **`Keys:` group**:

```
exiftool -m -P -overwrite_original_in_place \
  -Keys:Title='…' \
  -Keys:Description='…' \
  -Keys:Keywords='kw1,kw2' \
  movie.mp4
```

Field mapping Photos reads from videos (`.mp4`/`.m4v`/`.mov`):

| Photos field | Tag to write |
|---|---|
| Title | `Keys:Title` — **do not set `Keys:DisplayName`**, which overrides Title |
| Caption | `Keys:Description` |
| Keywords | `Keys:Keywords` |

Then:

1. Add a video branch to `MetadataStagingService.stage(...)` that writes the `Keys:` group
   (the service comment currently says "video-container metadata is not [reliable]" — the
   `Keys:` group specifically *is* the reliable path; that assumption predates this spike).
2. Route videos through staging in `importOneFile` exactly like photos.
3. **Delete `PhotosAppleScriptService`** and the AppleScript branch in `importOneFile`.
4. Re-implement **Re-apply Metadata** as a re-import (or drop it) — it's the other
   AppleScript caller.
5. **Remove `com.apple.security.automation.apple-events` from the entitlements** and
   `NSAppleEventsUsageDescription` from `Info.plist`.

**Outcome:** the only TCC prompt left is the standard PhotoKit "Allow access to Photos" — the
same one-time prompt Photos itself, PowerPhotos, and every photo importer show. Fully
professional. This is what osxphotos/GraphicConverter/Lightroom effectively do.

> **Caveats to verify before committing to Tier 1** (this is a spike — these need a hands-on
> test, see below): (a) Photos has a long-standing bug where importing a **single referenced
> file** silently drops Title/Caption (keywords still come through); importing in **batch /
> copy-to-library mode** is reliable — PurplePeek already copies (`shouldMoveFile = false`), so
> this should be fine, but confirm. (b) A minority of reports mention Photos 7.x dropping
> keywords on some video files; verify against the formats users actually feed it.

### Tier 2 — Alternative architectures (lower priority)

- **Mark-don't-mutate** (PhotoSweeper pattern): import keepers, drop metadata-on-Photos
  entirely, and let the user title/keyword in Photos. Simplest, but loses a feature.
- **Live-library editing** (PowerPhotos pattern): write directly into the `.photoslibrary`
  database. Powerful but unsupported/fragile and a much larger undertaking — not worth it here.

## Recommendation

**Tier 0 immediately (it's a one-function hardening and fixes the dev-time recurrence), then
Tier 1 as the real fix.** Tier 1 removes an entire entitlement and the entire class of
"control Photos" prompts, matching how the rest of the industry ships this exact feature. The
photo path already proves the pattern works; videos are the only gap, and there's a documented
exiftool recipe for them.

## Verification plan (before shipping either tier)

1. Build **Developer-ID signed** (confirm `codesign -dvvv` shows `Authority=Developer ID
   Application`, not `Signature=adhoc`; `codesign -d -r-` shows a Team-ID-based DR, not a bare
   cdhash). Install to `/Applications`, launch, `tccutil reset AppleEvents com.bronty13.PurplePeek`,
   import a video → confirm the Automation prompt appears **once**, then never again across
   relaunches. (Tier 0 acceptance.)
2. For Tier 1: stage a video with the `Keys:` tags, import it, and confirm Photos shows the
   correct **Title / Caption / Keywords** in its UI — **with the `apple-events` entitlement
   removed** so there's no chance AppleScript is silently doing the work. Test single + batch,
   and `.mp4`/`.mov`/`.m4v`.
3. Confirm the standard Photos-access prompt still appears exactly once and persists.

## Sources

- Apple — PhotoKit writable properties: `PHAssetChangeRequest` reference (no title/caption/keywords).
- Apple Developer Forums — *Persistent Privacy and Automation* (thread 126345); code signature is what makes TCC recognize "same app".
- Apple — `AEDeterminePermissionToAutomateTarget` docs; felix-schwarz, "New Apple Event APIs in macOS Mojave".
- Eclectic Light (Howard Oakley) — App quarantine & translocation series.
- Apple Community — what metadata Photos reads from images (IPTC/XMP) and from movies (QuickTime `Keys:` group), incl. the `DisplayName`-overrides-`Title` precedence trap and the single-file import bug.
- osxphotos (rhettbull) docs + discussions; GraphicConverter / Mylio / Lightroom / PowerPhotos / PhotoSweeper vendor docs and support threads.
- Scripting OS X — "Avoiding AppleScript Security and Privacy Requests"; electron-builder #9529 (ad-hoc signing breaks TCC).
