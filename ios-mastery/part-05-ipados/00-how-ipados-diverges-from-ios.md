---
title: "How iPadOS diverges from iOS"
part: "05 — iPadOS as a Computer"
lesson: 00
est_time: "40 min read + 15 min labs"
prerequisites: [macos-to-ios-mental-model-reset, memory-jetsam-app-lifecycle]
tags: [ios, ipados, platform, divergence]
last_reviewed: 2026-06-26
---

# How iPadOS diverges from iOS

> **In one sentence:** iPadOS is iOS from the kernel up — the same XNU, the same sandbox, the same Data Protection, the same artifact databases — wearing a Mac-like windowing system on top, so forensically you treat an iPad as *"iOS plus an extra evidence surface"* (external storage, multi-window scene state, Apple Pencil handwriting), not as a different operating system.

## Why this matters

You just spent a course learning that iOS is "macOS with the doors welded shut." iPadOS is where Apple is slowly unwelding *some* of those doors — a windowed multitasking model, a real file manager, pointer and trackpad input, external displays, and on the M-series machines, actual virtual-memory swap — while leaving the security floor (SEP, Data Protection, AMFI, the sandbox) completely intact.

For a **builder**, that means iPadOS is a superset SDK: every iOS API plus a windowing and document surface that behaves more like AppKit every year — `UIScene` multi-window, a real menu bar, pointer interactions, File Provider, and long-running background tasks. You don't ship a separate "iPad app"; you ship a universal binary that branches on traits at runtime.

For a **forensicator**, the payoff is the opposite of intimidating: **an iPad image parses with the exact same tooling and the exact same database schemas as an iPhone image** (everything in Parts 07–08 applies unchanged), and then it *adds* evidence sources an iPhone simply doesn't have. Knowing precisely where iPadOS forks — and, just as important, where it doesn't — tells you which of your iPhone playbooks transfer verbatim and which new artifacts you'd miss if you treated the tablet like a big phone.

## Concepts

### The shared spine: one OS, two product personalities

"iPadOS" became a marketing name in 2019 (iPadOS 13). It was never a fork. The two systems are built from the same source tree and ship in lockstep — **iPadOS 26.5** and **iOS 26.5** are the same release train, the same kernel, the same SDK, the same security architecture covered across Parts 02 and 03. What differs is a set of capability flags and a different presentation layer, gated at runtime by hardware traits and a `UIUserInterfaceIdiom` value.

What is *byte-for-byte identical* between iOS and iPadOS, and therefore where every earlier lesson transfers without an asterisk:

| Subsystem | Status on iPadOS | Lesson it's covered in |
|---|---|---|
| XNU kernel, BSD layer, Mach | Identical | [[xnu-on-mobile]] |
| Secure boot chain, Image4, SHSH | Identical | [[boot-chain-securerom-iboot]] |
| APFS volume roles, sealed system volume | Identical | [[apfs-on-ios-volumes]] |
| Sandbox, AMFI, code-signing, entitlements | Identical | [[code-signing-amfi-entitlements]] |
| Secure Enclave, Data Protection, keybags | Identical | [[data-protection-and-keybags]], [[sep-sepos-deep-dive]] |
| Per-app container layout under `/private/var/mobile/Containers/` | Identical | [[filesystem-layout-and-containers]], [[app-sandbox-and-filesystem-layout]] |
| The artifact databases (`sms.db`, `CallHistory.storedata`, Photos `Photos.sqlite`, `knowledgeC`/Biome, `NoteStore.sqlite`, Safari history) | Identical schemas | All of Part 08 |
| Backup format (`Manifest.db`, domain/relative-path hashing) | Identical | [[the-itunes-finder-backup-format]] |
| BFU/AFU lock states, 72-hour inactivity reboot | Identical | [[passcode-bfu-afu-and-inactivity]] |

In other words: there is no "iPad version" of `chat.db` or the Photos catalog. The schema you learn on an iPhone image is the schema on an iPad image. The difference is *additive*.

> 🔬 **Forensics note:** Timestamp discipline transfers wholesale too. The iPad uses the same "epoch zoo" as the iPhone and the Mac — Mac Absolute Time (`+ 978307200`) in most Apple SQLite stores, Unix epoch elsewhere, WebKit epoch in browser caches — covered in [[the-ios-timestamp-zoo]]. Nothing about being a tablet changes which epoch a given store uses; if a query worked on an iPhone image, the same conversion works on the iPad's copy of that store.

The same parity holds for your **tooling and acquisition methods**. `libimobiledevice`/`pymobiledevice3` pair, mount, and pull from an iPad exactly as from an iPhone; an iTunes/Finder backup of an iPad has the identical `Manifest.db` + domain layout; **iLEAPP**, **mvt**, and the commercial suites run their iOS parsers against an iPad image unchanged. The acquisition *boundary* is also the same hardware story you already know: the BootROM-exploit line (**checkm8** A8–A11, **usbliter8** A12–A13, nothing public for A14+) is defined by the SoC, so it applies to A-series iPads identically — and note that the **M-series iPads, like all A14-and-later silicon, have no public BootROM exploit**, so full-filesystem acquisition there depends on an agent/exploit path and lock state, not a SecureROM bug (see [[the-acquisition-taxonomy]]).

> 🖥️ **macOS contrast:** You already know this pattern in reverse. macOS and iOS share XNU and most of the lower frameworks but diverge hard at the top (AppKit vs UIKit, WindowServer vs SpringBoard, a writable shell-accessible filesystem vs a sealed one). iPadOS is the *convergence point* of that split: it keeps iOS's locked-down floor but is steadily importing the Mac's ceiling — windows, a menu bar, a Finder-like file app, a pointer. When you read an iPad you are reading an iOS device that is trying to become a Mac from the UI down, while the security model holds the line from the kernel up.

### Where iPadOS forks (1): the windowing system

On iPhone, one app owns the screen (plus the occasional Slide Over). On iPadOS 26 the presentation layer is a genuine **multi-window compositor**. The mechanism is *not* a port of macOS's WindowServer — there is still no per-window separate render process and no Quartz Compositor. Instead, **SpringBoard/FrontBoard** (the system UI and scene-lifecycle daemons you met in [[launchd-and-system-daemons]] and [[memory-jetsam-app-lifecycle]]) manage a set of **`UIScene`** instances, and each app process hosts one or more `UIWindowScene`s that the system composites into freely placed, overlapping, resizable windows.

The iPadOS 26 windowing model, mechanism by mechanism:

- **Three multitasking modes**, selectable in Settings → Multitasking & Gestures: **Full-Screen Apps**, **Windowed Apps** (the new default), and **Stage Manager**. All three sit on top of the same `UIScene` plumbing; they differ only in how SpringBoard arranges and clips the scenes.
- **macOS-style window controls** ("traffic lights": close / minimize / maximize) and a **grab-corner resize** on every window.
- **A Mac-style menu bar**, revealed by swiping down from the top edge or pushing the pointer into the top of the display. This is not new infrastructure — it is the **`UIMenuBuilder` / `UIMenuSystem.main`** command tree (the menu-command API introduced in **iOS/iPadOS 13.0**, which on iPad already drove the ⌘-key shortcut/discoverability HUD and, in Mac Catalyst apps, the real Mac menu bar) finally surfaced on iPad as a persistent, always-available bar. An app populates it by overriding `buildMenu(with:)`; the same `UIKeyCommand`/`UIMenu` declarations that powered ⌘-shortcuts now render as pull-down menus.
- **Window tiling** (drag to a screen edge / keyboard-driven tiling), mirroring macOS Sequoia's tiling.

The scene model is the load-bearing abstraction, and it differs sharply from how the Mac does windows. On macOS, every window is a `WindowServer`-owned surface and an app can sprawl across the screen; the kernel-side window server is a separate process compositing buffers from every app. iPadOS has **no per-window process and no `WindowServer`**. Instead the app process owns a tree of `UIScene` objects — multiple `UIWindowScene`s for the same app are still **one process** with one address space — and **SpringBoard/FrontBoard** owns the compositing, placement, and the lifecycle transitions (foreground-active → foreground-inactive → background → suspended). This is why "two windows of the same app" on iPad is cheaper than two Mac windows in some ways (one process) and more constrained in others (the system, not the app, decides when a scene is disconnected and its memory reclaimed).

The legacy multitasking primitives you may remember — **Split View** (two apps tiled) and **Slide Over** (a floating overlay app) — did not disappear; in iPadOS 26 they are special cases of the same scene compositor, now subsumed by free-form windowing. Forensically they all reduce to the same thing: multiple connected scenes recorded in the lifecycle bookkeeping.

```
macOS                              iPadOS
─────                              ──────
App ── windows ─▶ WindowServer     App ── UIScene tree ─▶ SpringBoard/FrontBoard
     (separate compositor proc)         (one app process; system composites)
     window == OS-level surface          UIWindowScene == app-owned, system-placed
```

Hardware gating is the subtle part, and it matters for both capability and forensics:

| Feature | Where it works |
|---|---|
| Windowed Apps + Stage Manager (on the built-in display) | **All** iPads that run iPadOS 26 — down to an A-series base iPad |
| Number of simultaneous windows | Capped lower (historically ~4) on older/non-M iPads; many more on M-series |
| **External display in *extended* mode** (true second desktop, not mirroring) | **M-series only (M1 and later)** — unchanged in iPadOS 26 |

So iPadOS 26 democratized *windowing* to every supported iPad but kept the *extended external desktop* an M-series privilege, because that mode leans on the memory headroom and swap discussed below.

> 🔬 **Forensics note:** Multi-window state is a new evidence surface with no iPhone equivalent. SpringBoard persists per-app scene/lifecycle state in **`/private/var/mobile/Library/FrontBoard/applicationState.db`** (a SQLite store keyed by bundle ID, recording background/foreground state and scene bookkeeping). On a multi-window iPadOS image this can corroborate that an app had *multiple live scenes* and what the system last knew about them. Per-app **state restoration** archives and `NSUserActivity` continuation payloads also live inside each app's own container (`Library/` under the data container) — these can preserve the *content* of a window (open document path, scroll position, draft text) even when the document itself is gone. Treat `applicationState.db` as the iPad-specific cousin of macOS's `~/Library/Saved Application State/`. *(Verify the exact column set against your target iPadOS version — the FrontBoard schema has changed across releases.)*

### Where iPadOS forks (2): pointer, trackpad, keyboard

Since iPadOS 13.4, a connected trackpad or mouse drives a **real cursor** — not an emulated finger. UIKit exposes it through the pointer-interaction APIs (`UIPointerInteraction`, hover via `UIHoverGestureRecognizer`), and the cursor *morphs* to fit the control under it (the "magnetic" pointer). Hardware keyboards get the full `UIKeyCommand` responder-chain menu system described above, plus system-wide keyboard navigation. Combined with the menu bar, an iPad with a Magic Keyboard is, from the input model's perspective, a laptop.

> 🖥️ **macOS contrast:** This is the responder chain you know from AppKit, retrofitted onto UIKit. `buildMenu(with:)` + `UIKeyCommand` is iPadOS's `NSMenu` + `NSResponder`-`validateMenuItem(_:)`. Where macOS dispatches menu actions up the `NSResponder` chain, iPadOS dispatches `UICommand`/`UIAction` up the `UIResponder` chain — same idea, same first-responder semantics.

### Where iPadOS forks (3): Files, external storage, document providers

iPhone has the Files app too, but on iPad it is a first-class file manager and — crucially — a **gateway to physical and network storage** that an iPhone effectively never touches: USB-C mass-storage drives, SD readers, and SMB shares mounted directly. This is the single biggest *new* evidence surface.

The mechanism is the **File Provider** architecture. The Files UI is a thin browser; the actual storage is exposed by **File Provider extensions** (`NSFileProviderReplicatedExtension`), one per provider — iCloud Drive, "On My iPad" local storage, third-party clouds (Dropbox, Google Drive), and externally attached volumes. Each provider has its own container and its own metadata DB tracking item identifiers, parent relationships, and sync state.

Forensically relevant consequences:

- **"On My iPad" local files** live in a system-owned File Provider container, not scattered in app sandboxes — a single place to enumerate user-managed documents. *(Confirm the exact container path on your target image; the local provider's storage path has moved across iPadOS versions.)*
- **External-volume access leaves traces even when the files are gone.** The system logs mount/attach events (queryable in the unified log, see [[unified-logs-sysdiagnose-crash-network]]), and File Provider metadata can retain item records for content that lived on a now-removed drive.
- **Document-picker round-trips** (a file imported from a USB drive into an app via the document picker) are mediated by these extensions and may appear in both the provider metadata and the consuming app's container.

> 🖥️ **macOS contrast:** The Files app is the iPad's Finder, and File Provider extensions are the direct descendant of macOS's File Provider framework (the same one that backs iCloud Drive and third-party sync clients in Finder). The "On My iPad" location is the local-disk analogue of `~`; mounted SMB/USB volumes are the analogue of `/Volumes/`. The difference is that on iPad each is a sandboxed provider, not a raw mount you can `cd` into.

> 🔬 **Forensics note:** This is the iPad's biggest divergence from the iPhone evidence model. An iPhone is essentially a closed box; an iPad can be the *transfer point* for data moving on and off external media. Always check (a) the unified log for USB/volume attach events, (b) File Provider metadata for records of external items, and (c) the Files app's recents/favorites bookmarks. A USB drive that touched the iPad may *also* carry its own filesystem artifacts of that interaction — image the drive too if you have authority over it.

> ⚖️ **Authorization:** External media broadens the scope of an examination beyond the device itself. A warrant or authorization scoped to "the iPad" may not cover a USB drive that was attached to it. Confirm your legal authority extends to attached/removable media before acquiring or examining it, and document attach events from the device log as the link between the two.

### Where iPadOS forks (3b): background execution gets a real escape hatch

The memory split has a lifecycle consequence. On iPhone, the background-execution model you learned in [[memory-jetsam-app-lifecycle]] is deliberately starved: short `beginBackgroundTask` windows, opportunistic `BGTaskScheduler` jobs, and a quick march to *suspended* — because the device needs to reclaim memory by termination. iOS/iPadOS 26 introduces **`BGContinuedProcessingTaskRequest`**: a user-initiated, foreground-started task (export a video, upload a large file) that **continues after you switch away and is presented in a system-drawn, Live-Activity-style progress UI** — the Dynamic Island / a notification banner on iPhone, a progress indicator on iPad. The system, not your app, draws that UI; the task conforms to `ProgressReporting` and **must keep reporting measurable progress or the system expires it** (a stalled task is killed). On supported devices it can also be granted **background GPU access** (opt-in via the background-GPU capability + a runtime check of the scheduler's supported-resources). This is the closest iPadOS has come to a Mac-style "keep working while I do something else" background job, and it leans directly on the M-series memory headroom — an app that's paging to swap can keep grinding where an iPhone would have suspended or jetsammed it.

Two engineering quirks worth knowing: the task is tied to the *active/focused* scene, not merely "some foreground window" — submission expects an active scene, and on iPad a scene running active-but-unfocused (e.g., the non-focused side of a Split View) is *not* the same as the focused window. iPadOS surfaces exactly this distinction through a per-scene **"active appearance"** signal (new on the iPadOS-26 windowing path; older OSes report nothing) that tells an app when *its* window has focus among many. iPadOS 26 also adds a **Local Capture** capability (high-quality on-device capture of your **own** camera + microphone streams — recorded separately as an HEVC-video / FLAC-audio MP4, with echo cancellation to strip other participants) usable while any video-conferencing app is running — another "this is a content-creation computer now" capability with no iPhone-first framing.

> 🖥️ **macOS contrast:** On a Mac, a backgrounded app just keeps running — there is no jetsam and no suspension; `NSBackgroundActivityScheduler` is a *politeness* API, not a survival one. iPhone is the opposite extreme (suspend fast, kill under pressure). `BGContinuedProcessingTaskRequest` is iPadOS splitting the difference: a bounded, system-tracked, user-visible (a system-drawn progress UI) license to keep computing after you switch away — the tablet inching toward the Mac's "apps just run" model without giving up the phone's memory discipline.

> 🔬 **Forensics note:** Background work that finishes while the user is elsewhere can leave traces an iPhone wouldn't generate — `BGContinuedProcessingTask` scheduling/bookkeeping and the system progress-UI's own state. Combined with the swap-shifted jetsam cadence above, the iPad's process-lifecycle timeline reads differently from an iPhone's: longer-lived background app activity is *expected*, so don't treat a long background run as anomalous the way you might on a phone. Cross-check the unified log and `applicationState.db` for the lifecycle story. *(Treat the exact on-disk form of this bookkeeping as version-specific — confirm against your target image rather than asserting a path.)*

### Where iPadOS forks (4): the M-series hardware story — and why it breaks the jetsam model

The iPad lineup is split down the middle by silicon, and that split creates **two different memory-management realities running the same OS**:

- The **base iPad** and **iPad mini** run **A-series** SoCs (phone-class memory, phone-class behavior).
- The **iPad Air** and **iPad Pro** run **M-series** SoCs (M1 → M5), the *same desktop-class designs as the Mac* (see [[soc-lineup-and-device-matrix]]). The 2025 **iPad Pro (M5)** ships with **12 GB** of LPDDR5X on the 256/512 GB models and **16 GB** on the 1 TB/2 TB models.

| Line | 2026-era SoC | Memory class | Swap? | External display (extend) |
|---|---|---|---|---|
| base iPad | A-series (phone-class) | phone-class RAM | **No** | No (mirror only) |
| iPad mini | A-series (A17 Pro era) | phone-class RAM | **No** | No (mirror only) |
| iPad Air | **M-series** (M1→) | desktop-class | **Yes** (storage-gated) | **Yes** |
| iPad Pro | **M-series** (M1→M5) | desktop-class, up to 16 GB | **Yes** | **Yes** |

The board ID (`iPadN,N` from `ProductType`) is the authoritative way to place a device in this table — never infer the SoC from the marketing name alone.

The capability that matters most is **Virtual Memory Swap**, introduced with iPadOS 16 on M-series iPads. In [[memory-jetsam-app-lifecycle]] you learned the iPhone memory model: **there is no swap.** iOS relies on the in-kernel compressor (`vm_compressor`, WKdm-style compression of dirty pages) and, when that isn't enough, **Jetsam** kills the lowest-priority app outright. Memory pressure on iOS is resolved by *termination*, not paging.

M-series iPads change that. With Virtual Memory Swap, the VM subsystem can page compressed/dirty memory out to **backing-store swap files on the data partition** — exactly like a Mac — giving demanding apps a far larger effective working set (Apple historically cited up to 16 GB of addressable memory for a single app). The compressor still runs *in front of* swap, and Jetsam still exists as the backstop, but the kill threshold moves: an app that would be jetsammed on an iPhone can instead be paged out and survive on an M-series iPad. That is *the* mechanism behind "real" multitasking, eight-plus live windows, and extended external displays — the OS can keep more apps resident because it can spill to flash.

```
iPhone / A-series iPad           M-series iPad (swap enabled)
─────────────────────           ───────────────────────────
RAM ── vm_compressor             RAM ── vm_compressor ── swapfiles (flash)
        │                                 │                    │
        └─ pressure ─▶ Jetsam kill        └─ pressure ─▶ page out, THEN Jetsam
        (no backing store)                (backing store exists; kills are rarer)
```

Swap is gated not only on M-series silicon but historically on sufficient storage as well (the early 64 GB M1 iPad Air, for example, did **not** get it — the up-to-16 GB figure required the 256 GB-and-up configs). Verify the exact gating on your specific model/version.

> 🖥️ **macOS contrast:** This is literally the Mac's `dynamic_pager`/compressor model arriving on a tablet. On macOS, swap lives at **`/private/var/vm/swapfile0`, `swapfile1`, …** alongside `/private/var/vm/sleepimage`. An M-series iPad with swap enabled creates analogous backing-store swap files on its data volume — a thing that *does not exist on an iPhone at all*. **Verify the exact on-disk path inside an iPadOS full-filesystem image before quoting it in a report** — it has historically tracked the macOS `/private/var/vm/` convention, but confirm against your image rather than asserting it.

> 🔬 **Forensics note:** Swap is a memory-forensics surface unique to M-series iPads. Pages that an iPhone would have compressed-in-RAM-then-killed can persist on the iPad's flash as swap content — potentially capturing fragments of app memory (decrypted message text, keys in use at swap time, clipboard data) in a full-filesystem acquisition (see [[full-file-system-acquisition]]). It also means the **jetsam event logs** (`/private/var/mobile/Library/Logs/CrashReporter/` JetsamEvent reports) read differently: fewer low-memory kills on a swap-capable iPad changes the baseline of "what got terminated when," which you may otherwise misread as light usage. Don't port iPhone assumptions about termination cadence onto an M-series iPad.

> ⚠️ **ADVANCED:** Swap-file content is high-value but volatile and only reachable via a **full-filesystem acquisition** (BootROM-exploit or agent-based, requiring at least AFU state and the relevant keys — see [[the-acquisition-taxonomy]] and [[bfu-vs-afu-and-data-protection-classes]]). It is *not* present in an iTunes/Finder logical backup. Plan the acquisition method around it; you cannot retroactively recover swap from a backup that never contained it.

### Where iPadOS forks (5): EU DMA lands separately on iPadOS

The EU's Digital Markets Act treats iPhone and iPad as **two distinct designations**. iOS was named a core platform service in the first wave; **iPadOS was designated a gatekeeper separately (April 2024)**, with its own six-month compliance clock. Practically, the same alternative-distribution machinery that came to iOS — **alternative app marketplaces, Web Distribution, default-app choice, and Notarization-gated sideloading** — extends to iPadOS for EU users, but on iPadOS's own timeline and under its own designation.

The engineering surface is identical to iOS (covered in depth in [[eu-dma-sideloading-and-alternative-marketplaces]]): EU-region apps can install from a notarized alternative marketplace or directly from a developer's website, gated by **MarketplaceKit**, install entitlements, and Apple's notarization scan (a malware/integrity check, explicitly *not* the App Store's full review bar).

> 🖥️ **macOS contrast:** This is iPadOS importing the Mac's *distribution* freedom while keeping iOS's *runtime* lockdown. On macOS you can run any signed (or even unsigned, with a TCC/Gatekeeper override) binary from anywhere; notarization is advisory. On an EU iPad, distribution opens up — multiple stores, web downloads — but every binary still passes AMFI/code-signing and notarization, and still runs inside the iOS sandbox. The iPad gained the Mac's *front door choices*, not the Mac's *open execution floor*.

> 🔬 **Forensics note:** On an EU-region iPad, "where did this app come from?" is no longer "the App Store, full stop." The install source is recorded in the app's receipt/metadata and in **MarketplaceKit**'s bookkeeping (the installed-marketplace registry and per-app distribution records), plus `installd`/`appstored` install-history logs. A non-App-Store provenance is itself an investigative signal — different review bar, different update channel, different trust anchor. To establish region/provenance, cross-reference the device's stored region, the app's distribution metadata, and the unified log around install time. The mechanism is shared with iOS — see [[eu-dma-sideloading-and-alternative-marketplaces]] for the artifact specifics — but remember the **designation is per-platform**, so an EU iPad and a non-EU iPad of the same model can have entirely different install surfaces. *(Confirm the MarketplaceKit store path against your target version before quoting it.)*

### Where iPadOS forks (6): Continuity binds the iPad to the Mac

The iPad is the device most tightly coupled to a Mac, and several Continuity features exist *only* in iPad↔Mac form (covered fully in [[continuity-with-the-mac]]):

- **Universal Control** — one keyboard/trackpad driving a Mac and an iPad side by side, with the cursor crossing the bezel between them.
- **Sidecar** — the iPad as a wired/wireless secondary display and graphics tablet for the Mac.
- **Handoff / Continuity** (Clipboard, Camera, etc.) — shared with iPhone, but the iPad participates as a near-peer.

The transport underneath is the same proximity stack as the rest of the Apple ecosystem — historically **AWDL**, now migrating to **Wi-Fi Aware** (see [[wifi-bluetooth-and-proximity]]) — plus iCloud-mediated state. The point for this lesson: an iPad is rarely a standalone island; it is usually one node of a Mac+iPad+iPhone mesh, and evidence flows between them.

> 🔬 **Forensics note:** Continuity makes **cross-device correlation** a first-class iPad concern. A document, clipboard payload, or browser tab on the iPad may have *originated* on a paired Mac or iPhone via Handoff/Universal Clipboard, and the pairing/activity leaves traces on both ends (Bluetooth/Wi-Fi proximity records, Handoff activity, `NSUserActivity` continuation state). When you image an iPad, ask what it was *paired with* — the timeline you want may span three devices, and the iPad is often the bridge.

### The forensic thesis: iPad = iOS + an extra evidence surface

Stitch the forks together and the operating principle for any iPad examination falls out:

```
            ┌─────────────────────────────────────────────┐
            │  EVERYTHING from Parts 07–08 (iOS artifacts) │  ← parse identically
            │  sms.db · Photos.sqlite · NoteStore · Safari │
            │  knowledgeC/Biome · CallHistory · backups    │
            └─────────────────────────────────────────────┘
                              +  (iPad-only)
            ┌─────────────────────────────────────────────┐
            │  External storage (USB-C / SMB via Files)    │
            │  Multi-window / scene state (FrontBoard,      │
            │     state restoration, NSUserActivity)        │
            │  Apple Pencil handwriting (PencilKit drawings)│
            │  M-series swap (full-filesystem only)         │
            │  Per-platform DMA install provenance (EU)     │
            └─────────────────────────────────────────────┘
```

So an iPad examination is your iPhone SOP plus a short "what's extra here?" pass:

1. **Run the full iPhone artifact pass unchanged** — all of Part 08 applies verbatim (copy-before-query each SQLite store; an open even for `SELECT` spawns `-wal`/`-shm`).
2. **Resolve the silicon personality** from `ProductType` → SoC: does this model swap? drive an extended display? what's the expected Jetsam cadence?
3. **Enumerate external storage** — Files/File Provider metadata, "On My iPad" local store, and unified-log USB/SMB attach events. Scope-check authority over any attached media.
4. **Recover multi-window/scene state** — `FrontBoard/applicationState.db`, per-app state-restoration archives, `NSUserActivity` payloads.
5. **Pull Apple Pencil handwriting** — `PKDrawing` blobs in Notes/third-party note apps, and any Scribble-recognized text.
6. **If M-series + full-filesystem** — carve `/private/var/vm/` swap content for in-flight memory fragments.
7. **Map Continuity** — what Mac/iPhone was this iPad paired with? The timeline may span devices.

The third new surface — **Apple Pencil handwriting** — deserves its own note. Pencil strokes are captured by **PencilKit** as a `PKDrawing`, an opaque, versioned, serialized blob of vector stroke data (pressure, tilt, timing). In **Notes**, a drawing is embedded into the note's content: the rich-text body is a gzipped protobuf in `NoteStore.sqlite` (the `ZICNOTEDATA`/`ZDATA` lineage you'll dissect in [[mail-notes-calendar-reminders]]), with the drawing carried as an inline attachment, and any rendered/preview media under the Notes group container's media directories. **Scribble** (handwriting-to-text) converts ink to text inline, so the recognized text lands in the normal text store while the raw `PKDrawing` may or may not be retained depending on the app. Third-party note apps (GoodNotes, Notability) store their own `PKDrawing`/proprietary ink blobs inside their containers.

> 🔬 **Forensics note:** Handwriting is content that exists *only* because there's a Pencil — an evidence type with no iPhone analogue. The `PKDrawing` blob is not plain text; recovering legible content means either rendering the drawing (PencilKit can rasterize it) or running Scribble-style recognition. Two angles to remember: (1) the **recognized/Scribble text** may already be sitting in a normal text column even when the ink looks opaque; (2) drawing blobs carry **per-stroke timing**, so a single note can yield a micro-timeline of when it was actually written. Always note the app — Notes vs GoodNotes vs Freeform store ink in different places and formats. *(Treat `PKDrawing` as version-specific: confirm the serialization with the PencilKit version on your target before asserting field meanings.)*

## Hands-on

There is no on-device shell, and the iPad's most interesting divergences (real windowing, swap, Pencil) **do not exist in the Simulator** — the Simulator runs your app against macOS frameworks with no SpringBoard, no Jetsam, no swap, and no File Provider hardware backing. So the Mac-side work here is: (a) use the Simulator to *prove the container layout is identical to iOS*, and (b) use device metadata / sample images for the iPad-only surfaces.

**Enumerate the iPad simulators and confirm the idiom split:**
```bash
xcrun simctl list devicetypes | grep -i ipad
#   iPad Pro 13-inch (M4) (com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4)
#   iPad Air 11-inch (M3) (com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3)
#   iPad mini (A17 Pro)   (com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro)
#   ...
```

**Boot an iPad simulator and show its container tree is the *same shape* as an iPhone's** (this is the whole point — same OS):
```bash
DEV=$(xcrun simctl create "ipad-lab" \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4)
xcrun simctl boot "$DEV"
DATA=~/Library/Developer/CoreSimulator/Devices/$DEV/data
ls "$DATA/Containers/Data/Application"      # per-app data containers — identical layout to iPhone sim
ls "$DATA/Containers/Shared/AppGroup"       # app groups — identical
# There is NO FrontBoard/applicationState.db, NO /private/var/vm swapfile,
# NO File Provider hardware backing here. The Simulator teaches structure, not device behavior.
```

**Tell an iPad apart from an iPhone (and M-series from A-series) by device metadata.** With a connected device you'd use `libimobiledevice`; with no device, the same keys appear in a backup's `Info.plist`/`Manifest.plist` or a sample image's properties:
```bash
# Real-device form (walkthrough — there is no device here):
ideviceinfo -k DeviceClass     # -> "iPad"
ideviceinfo -k ProductType     # -> e.g. "iPad16,3" (Pro M4) — maps to the SoC via the device matrix
ideviceinfo -k HardwarePlatform

# From a logical backup you DO have on the Mac:
/usr/libexec/PlistBuddy -c 'Print :DeviceClass'  ~/path/to/backup/Info.plist   # iPad
/usr/libexec/PlistBuddy -c 'Print :ProductType'  ~/path/to/backup/Info.plist   # iPadN,N
```
The `iPadN,N` board ID resolves to the SoC (and therefore to "does this device have swap?") via the device matrix in [[soc-lineup-and-device-matrix]].

**See how an app's own code learns it's on an iPad** (the runtime fork your binaries branch on). The idiom is a trait, not a compile-time constant — the same `.app` runs on both:
```bash
# Inspect a decrypted app binary's Info.plist for iPad capability:
/usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily' /path/to/App.app/Info.plist
#   1   -> iPhone only
#   2   -> iPad only
#   1 and 2 -> universal (most apps)
# At runtime the app branches on UITraitCollection.userInterfaceIdiom == .pad
# and on scene/size-class traits — there is no separate "iPad build" of a universal app.
```

**Query the iPad-only multi-window bookkeeping** (on a *copy* from a full-filesystem image or extraction — never the live store):
```bash
cp /path/to/extraction/private/var/mobile/Library/FrontBoard/applicationState.db /tmp/appstate.db
sqlite3 /tmp/appstate.db ".tables"
# Inspect the bundle-id-keyed rows; correlate background/foreground/scene state.
# (Column names vary by iPadOS version — dump the schema first: .schema)
```

**Check for swap presence in a full-filesystem image** (the M-series tell):
```bash
ls -la /path/to/ffs/private/var/vm/ 2>/dev/null
# On an M-series iPad with swap: backing-store swapfile(s) present (verify naming on your image).
# On an iPhone or A-series iPad image: this evidence does not exist.
```

**Surface Apple Pencil handwriting from the Notes store** (copy first — a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`):
```bash
NS=/path/to/extraction/.../group.com.apple.notes/NoteStore.sqlite
cp "$NS" /tmp/notestore.db
# Notes whose body protobuf carries an embedded drawing/attachment:
sqlite3 /tmp/notestore.db "
  SELECT Z_PK, ZTITLE1,
         datetime(ZCREATIONDATE1 + 978307200,'unixepoch','localtime') AS created
  FROM ZICCLOUDSYNCINGOBJECT
  WHERE ZTITLE1 IS NOT NULL
  ORDER BY ZCREATIONDATE1 DESC LIMIT 20;"
# The rich-text body lives in ZICNOTEDATA.ZDATA as gzipped protobuf; an inline PKDrawing
# rides inside it. Confirm the exact table/column lineage against the NoteStore schema for
# the image's iOS version (it has drifted across releases), then gunzip + parse the protobuf.
```
Note the Apple epoch (`+ 978307200`) — the same Mac Absolute Time you used on macOS. The artifact format and timestamp convention are identical to the Mac; only the *handwriting payload* is iPad-specific.

## 🧪 Labs

> ⚠️ **Substrate honesty up front:** Labs 1 is on the **Simulator** (structure only — no SpringBoard windowing, no swap, no FrontBoard, no File Provider hardware). Labs 2–4 use a **public iPad sample image** or a **read-only walkthrough** for the device-only surfaces. Every iPad-divergent behavior (windowing, swap, Pencil, external storage) is device/image-only; the Simulator can only prove the *shared* layer.

### Lab 1 — Prove "same containers" on the Simulator *(substrate: Xcode Simulator; fidelity caveat: no device daemons, no swap, no FrontBoard)*

1. Boot an **iPad** simulator and an **iPhone** simulator (`xcrun simctl boot <UDID>` for each).
2. Install or launch the same app (e.g., open Notes/Safari in both, or `xcrun simctl install`) and add some data.
3. Diff the two container trees under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/`.
4. Confirm the directory shapes and the per-app SQLite schemas are identical. **Conclusion to internalize:** the iPad adds *nothing* to the shared artifact layer — it only adds surfaces the Simulator can't show.
5. Now look for what's *missing*: there is no `FrontBoard/applicationState.db`, no `/private/var/vm/` swapfile, and no File Provider hardware backing in the Simulator tree. Write down each absent artifact — that list *is* the set of iPad-only surfaces you must source from a real image instead.

### Lab 2 — Find the iPad-only surfaces in a sample image *(substrate: public iPad reference image — e.g. Josh Hickman's published iOS/iPadOS images on thebinaryhick.blog, or iLEAPP/mvt test data; fidelity caveat: read-only, image-as-captured)*

1. Obtain an iPad full-filesystem reference image. Mount/extract read-only.
2. `cp` and query `FrontBoard/applicationState.db` (schema-dump first) — note any multi-scene/window state you would *not* see on an iPhone.
3. Enumerate the unified log (or `iLEAPP`'s parsed output) for **USB/external-volume attach** events and **File Provider** activity — the external-storage surface.
4. Locate the File Provider / "On My iPad" local storage and list user documents. Write down which of these artifacts have **no iPhone equivalent**.

### Lab 3 — Detect M-series swap; contrast with an iPhone image *(substrate: full-filesystem sample images; fidelity caveat: presence depends on model + storage tier + whether swap was active at capture)*

1. In an **M-series iPad** full-filesystem image, look under `/private/var/vm/` for backing-store swap files (verify the exact naming on the image).
2. In an **iPhone** image, confirm that path/evidence is **absent** — termination, not paging, is the iPhone memory model.
3. Open the JetsamEvent reports under `/private/var/mobile/Library/Logs/CrashReporter/` on both. Compare the cadence of low-memory kills. Explain in one line why the M-series iPad's baseline differs (swap absorbs pressure the iPhone resolves by killing).
4. Tie it back to the device matrix: from the image's `ProductType`, confirm the iPad is in fact an M-series model. If it were an A-series base iPad, you'd expect the *iPhone* memory profile (no swap, more frequent kills) on the very same OS version — the silicon, not the OS, sets the behavior.

### Lab 4 — Apple Pencil handwriting in Notes *(substrate: read-only walkthrough + sample image; fidelity caveat: ink requires a real Pencil — capture it on an image, parse it on the Mac)*

1. On a sample iPad image, `cp` the Notes store: `Group Containers .../group.com.apple.notes/NoteStore.sqlite` (mirror the macOS path you already know).
2. Identify notes containing drawings: the body protobuf in `ZICNOTEDATA`/`ZDATA` carries an embedded `PKDrawing` attachment.
3. Check whether **Scribble-recognized text** is present in a normal text column even when the ink blob is opaque.
4. Document the takeaway: handwriting is **iPad-only content**, the blob needs rendering or recognition, and per-stroke timing can yield a micro-timeline. *(Confirm `PKDrawing` field meaning against the PencilKit version for the image's OS.)*
5. Cross-check: open the same note's `ZICCLOUDSYNCINGOBJECT` row metadata (creation/modification dates) against the per-stroke timing inside the drawing. A modification timestamp that *post-dates* the latest ink stroke implies a later edit (text added, drawing moved) — a small but real corroboration/contradiction check.

### Lab 5 — Read the silicon split from device metadata *(substrate: logical backup or sample-image properties; fidelity caveat: metadata only — no live behavior)*

1. From any iPad logical backup on your Mac, print `DeviceClass` and `ProductType` from `Info.plist` (PlistBuddy).
2. Map the `iPadN,N` board ID to its SoC using the matrix in [[soc-lineup-and-device-matrix]].
3. State, *before opening any artifact*, whether this device (a) can swap, (b) can drive an extended external display, and (c) how aggressively you should expect Jetsam to have fired. You've now derived the device's entire memory/window personality from two plist keys.

## Pitfalls & gotchas

- **Treating the iPad as a different OS.** The most common reflex error in both directions: builders re-learning frameworks that are identical, and forensicators reaching for "iPad tools." Your iPhone schemas, queries, epochs, and acquisition methods all transfer. Only the *additive* surfaces are new.
- **Assuming the Simulator shows iPad behavior.** It shows iPad *layout*. There is no windowing compositor, no Jetsam, no swap, no FrontBoard, and no File Provider hardware in the Simulator. Never validate a memory/window/external-storage claim there.
- **Porting iPhone jetsam intuition to an M-series iPad.** Fewer low-memory kills on a swap-capable iPad is *normal*, not a sign of light use. Read JetsamEvent cadence against the device's memory model, which depends on the SoC tier from the device matrix.
- **Expecting swap in a logical backup.** Swap content only exists in a full-filesystem acquisition, and only on swap-capable M-series models. A Finder/iTunes backup will never contain it — choose the acquisition method up front.
- **Scope creep via external media.** An iPad can be the on/off-ramp for USB and SMB data. Authorization scoped to "the iPad" may not cover an attached drive; confirm authority and use the device's own attach logs to establish the link.
- **Quoting unverified paths.** Three things in this lesson have moved across iPadOS versions and *must* be confirmed against your target image, not asserted: the swap-file path under `/private/var/vm/`, the "On My iPad" / local File Provider storage path, and the `applicationState.db` / `PKDrawing` field layouts. Lead with the mechanism; verify the exact value.
- **Forgetting DMA is per-platform.** An EU iPad's install surface (alternative marketplaces, Web Distribution) is designated separately from iOS. Two same-model iPads — one EU, one not — can have completely different app provenance.
- **Confusing "Stage Manager is everywhere now" with "external desktop is everywhere now."** iPadOS 26 brought windowing/Stage Manager to every supported iPad, but *extended* external-display output is still M-series-only. A base iPad connected to a monitor mirrors; it does not extend. Don't infer M-series hardware from the mere fact that Stage Manager is enabled.
- **Reading a multi-window app as multiple installs.** One app with several `UIWindowScene`s is still one process and one container. Multiple scenes in `applicationState.db` are windows, not duplicate apps — don't double-count.
- **Assuming a logical backup captured the external/document surface.** Cloud File Provider items, externally mounted volumes, and some "On My iPad" storage may not land in a Finder/iTunes backup the way native app data does. If the document surface matters, plan a full-filesystem acquisition and image any attached media separately.

## Key takeaways

- iPadOS **is** iOS: same kernel, same security model, same containers, same artifact databases. Everything in Parts 07–08 parses an iPad image identically.
- The divergence is **additive UX/capability on top**: a real windowing system (`UIScene` composited by SpringBoard/FrontBoard), a Mac-style menu bar (`UIMenuBuilder`), pointer/trackpad, external displays, and the Files app as a true file manager with external storage.
- The lineup is **split by silicon**: A-series base iPad/mini behave like phones; M-series Air/Pro behave like Macs — most importantly, they have **Virtual Memory Swap**, which changes the [[memory-jetsam-app-lifecycle]] picture from "compress-then-kill" to "compress-then-page-then-kill."
- **Swap is an M-series-only memory-forensics surface** (full-filesystem acquisition only) and it shifts Jetsam-kill cadence — don't read iPhone termination assumptions onto it.
- Forensically, an iPad is **"iOS + extra evidence surface"**: external storage via File Provider, multi-window/scene state (`applicationState.db`, state restoration, `NSUserActivity`), and Apple Pencil handwriting (`PKDrawing` + Scribble text).
- **External media broadens scope** — confirm authorization extends to attached USB/SMB volumes, and use the device's attach logs to tie them to the iPad.
- **EU DMA is designated per-platform**: iPadOS got its own gatekeeper designation, so install provenance (App Store vs marketplace vs Web Distribution) is a separate question from iOS.
- Verify version-specific paths (swap, local File Provider storage, FrontBoard and PencilKit field layouts) against your actual image — lead with the durable mechanism, confirm the perishable detail.

## Terms introduced

| Term | Definition |
|---|---|
| iPadOS | Apple's iPad-targeted branch of the iOS code train; same kernel/security/SDK, with windowing and capability layers added on top (named since 2019). |
| `UIScene` / `UIWindowScene` | UIKit objects representing a discrete UI instance of an app; the unit SpringBoard composites into iPadOS windows. |
| SpringBoard / FrontBoard | The system-UI and scene-lifecycle daemons that own the home screen and manage app scenes/windows on iOS/iPadOS. |
| `applicationState.db` | SQLite store at `/private/var/mobile/Library/FrontBoard/applicationState.db` recording per-app background/foreground and scene state. |
| `UIMenuBuilder` / `UIMenuSystem` | The menu-command-tree API (since iOS/iPadOS 13.0) behind the iPad ⌘-key shortcut/discoverability HUD and Mac Catalyst menu bars; surfaced as the persistent iPad menu bar in iPadOS 26. |
| Windowed Apps | The default iPadOS 26 multitasking mode: freely placed, resizable, overlapping windows with macOS-style traffic-light controls. |
| Stage Manager | iPadOS multitasking mode grouping windows into "stages"; on the built-in display for all iPadOS 26 iPads, but extended-external-display use is M-series only. |
| Split View / Slide Over | Legacy iPad multitasking primitives (two tiled apps / a floating overlay app); in iPadOS 26 they are special cases of the unified scene compositor. |
| `BGContinuedProcessingTaskRequest` | iOS/iPadOS 26 user-initiated, foreground-started background task that continues after app-switch; the system draws a Live-Activity-style progress UI (Dynamic Island/banner on iPhone, progress indicator on iPad) and expires the task if it stops reporting progress. |
| Local Capture | iPadOS 26 on-device high-quality capture of your own camera + mic streams (recorded separately as an HEVC/FLAC MP4, with echo cancellation) while any video-conferencing app is running. |
| `UIDeviceFamily` | Info.plist key declaring supported device families (1 = iPhone, 2 = iPad, both = universal); the build-time companion to the runtime idiom trait. |
| Universal Control | iPad↔Mac Continuity feature: one keyboard/trackpad drives both, cursor crossing the bezel. |
| Sidecar | Continuity feature using the iPad as a secondary display / graphics tablet for a Mac. |
| Virtual Memory Swap | M-series iPad feature (since iPadOS 16) that pages compressed/dirty memory to backing-store swap files on flash, raising the effective working set; absent on iPhone and A-series iPads. |
| `vm_compressor` | The in-kernel memory compressor that compacts dirty pages before (on iPhone) termination or (on M-series iPad) swap. |
| Jetsam | The iOS/iPadOS low-memory killer that terminates low-priority apps under pressure; the *backstop* on swap-capable iPads rather than the first response. |
| File Provider extension | `NSFileProviderReplicatedExtension` that exposes a storage backend (iCloud Drive, local, third-party cloud, external volume) to the Files app, each with its own metadata DB. |
| PencilKit / `PKDrawing` | Apple Pencil ink framework; `PKDrawing` is the opaque, versioned serialized blob of vector stroke data (pressure, tilt, timing). |
| Scribble | Handwriting-to-text on iPadOS; recognized text lands in the normal text store, sometimes alongside the retained raw ink. |
| MarketplaceKit | The EU-DMA framework mediating installs from alternative app marketplaces / Web Distribution. |

## Further reading

- Apple — "iPadOS 26 introduces powerful new features that push iPad even further" (apple.com/newsroom, 2025-06) — windowing, menu bar, Background Tasks, Local Capture.
- Apple Developer — *Adopting the new multitasking and windowing behaviors*; `UIScene`, `UISceneSession`, state restoration, `buildMenu(with:)` docs.
- Apple Developer — *Performing long-running tasks on iOS and iPadOS* (`BGContinuedProcessingTaskRequest`, Live Activities for background work).
- Apple Developer — File Provider framework (`NSFileProviderReplicatedExtension`); PencilKit (`PKDrawing`, `PKCanvasView`); MarketplaceKit.
- Apple — "iPadOS 16 takes the versatility of iPad even further" + AppleInsider/MacRumors coverage of M1 Virtual Memory Swap requirements and the 256 GB gating.
- Apple — iPad Pro (M5) tech specs (support.apple.com) — RAM tiers, LPDDR5X.
- Apple Developer Support — "Update on apps distributed in the European Union"; European Commission DMA developer portal — iPadOS's separate gatekeeper designation.
- Apple — iPadOS 26 multitasking explainers (AppleInsider "what's new with iPad app windows"; MacRumors iPadOS 26 roundup) for the user-facing model behind the `UIScene` mechanics.
- Michael Tsai — "iPadOS Windows Mess Up Data Saving" (mjtsai.com, 2025-07) — the scene-disconnect / state-saving gotcha developers hit with the new windowing.
- Jonathan Levin, *MacOS and iOS Internals* — SpringBoard/FrontBoard, the VM subsystem, the compressor and jetsam (newosxbook.com).
- Sarah Edwards (mac4n6.com) / Alexis Brignoni (iLEAPP) / Ian Whiffin (d204n6.com) — iOS/iPadOS artifact parsing, FrontBoard and Notes/PencilKit research; Josh Hickman (thebinaryhick.blog) — reference images.
- `man simctl` (via `xcrun simctl help`); `ideviceinfo(1)` (libimobiledevice); `man sqlite3`.

---
*Related lessons: [[memory-jetsam-app-lifecycle]] | [[macos-to-ios-mental-model-reset]] | [[soc-lineup-and-device-matrix]] | [[files-external-storage-and-document-providers]] | [[windowing-multitasking-and-external-display]] | [[continuity-with-the-mac]] | [[full-file-system-acquisition]] | [[eu-dma-sideloading-and-alternative-marketplaces]] | [[mail-notes-calendar-reminders]] | [[the-ios-timestamp-zoo]]*
