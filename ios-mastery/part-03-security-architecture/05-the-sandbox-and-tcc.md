---
title: "The sandbox & TCC on iOS"
part: "03 — Security Architecture"
lesson: 05
est_time: "50 min read + 20 min labs"
prerequisites: [code-signing-amfi-entitlements, filesystem-layout-and-containers]
tags: [ios, sandbox, seatbelt, tcc, privacy, entitlements]
last_reviewed: 2026-06-26
---

# The sandbox & TCC on iOS

> **In one sentence:** On iOS the sandbox is mandatory and universal — every third-party process is confined at install time by a kernel-enforced *container* profile that no app can opt out of — and privacy-sensitive resources sit behind a second, orthogonal gate (TCC) that requires both an entitlement *and* a purpose string before the user is ever asked, with the API trapping the process dead if the purpose string is missing.

## Why this matters

You arrived from macOS, where the App Sandbox is **opt-in**: it exists only if a developer adds the `com.apple.security.app-sandbox` entitlement, the Mac App Store requires it, and a huge fraction of Developer-ID software (Homebrew, your own CLI tools, half of `/Applications`) runs completely unconfined. iOS inverts this. There is **no unsandboxed third-party code path** on a non-jailbroken device — the same `Sandbox.kext` you studied as an *option* on macOS is the *floor* on iOS, applied to every App Store app, every app extension, and almost every Apple daemon.

For the **builder**, this is the wall you keep hitting: why you cannot read another app's files, why a missing `NS…UsageDescription` string crashes your app on first camera access rather than showing a denial, why a file the user "gave" you via the document picker is readable but its siblings are not. For the **forensicator**, the sandbox is the *parsing skeleton* of the entire filesystem — apps live in UUID-named container directories that only become legible once you read their metadata — and TCC.db is a small, high-value artifact that answers "did this app ever have camera / microphone / contacts access, and when did that change?" This lesson is the mechanism behind both.

## Concepts

### Two orthogonal gates: confinement vs. consent

Keep these separate in your head from the start — conflating them is the classic mistake:

| Gate | Question it answers | Enforced by | Granularity | Default |
|---|---|---|---|---|
| **Sandbox (Seatbelt)** | "Which files / Mach services / syscalls may this *process* touch at all?" | `Sandbox.kext` (kernel, TrustedBSD MAC) | per-operation, per-path | **deny** outside the container |
| **TCC** | "May this *app* access this user's private *data class* (camera, mic, photos, contacts…)?" | `tccd` (userspace daemon) + framework checks | per-app, per-service | **prompt once, then remembered** |

The sandbox is a coarse, mandatory, kernel wall around a process's *filesystem and IPC reach*. TCC is a fine, consent-driven policy about *named privacy resources*, evaluated in userspace by the framework that owns each resource. An app can be perfectly inside its sandbox and still be denied the camera by TCC; conversely TCC never lets an app reach *another app's* container — that is the sandbox's job, and TCC is not even consulted.

> 🖥️ **macOS contrast:** On macOS these same two systems exist but both are softer. The sandbox is opt-in (most apps skip it); TCC has **two** databases — a per-user `~/Library/Application Support/com.apple.TCC/TCC.db` and a system `/Library/Application Support/com.apple.TCC/TCC.db`, both SIP-protected so even root needs Full Disk Access to read them. On iOS there is **one** TCC store and the sandbox is non-negotiable. The conceptual model you learned transfers; the universality and the file count change.

---

### Seatbelt / `Sandbox.kext`: where the policy actually lives

iOS sandboxing is implemented by **`Sandbox.kext`** (bundle id `com.apple.security.sandbox`), a **TrustedBSD MAC** (Mandatory Access Control) policy module registered into the kernel via `mac_policy_register`. "Seatbelt" is the historical name for this subsystem (the original `sandbox-exec`/`seatbelt` profile language from macOS 10.5). The kext installs MAC hooks on filesystem operations, Mach port lookups, network calls, IOKit user-clients, POSIX IPC, and process operations. When a confined process performs any of these, the kernel calls into Seatbelt, which evaluates the process's **profile** and returns allow/deny.

Profiles are authored in **SBPL** (Sandbox Profile Language — a TinyScheme/Lisp dialect of `(allow …)` / `(deny …)` rules over operations like `file-read*`, `file-write*`, `mach-lookup`, `network-outbound`, `iokit-open`). But SBPL is a *build-time* artifact. What ships is **compiled bytecode**: a profile is reduced to a compact state-machine the kernel can evaluate cheaply per operation.

The non-obvious iOS detail: **the compiled profiles are baked into the kext binary itself**, hard-coded into the `__TEXT.__const` segment of `Sandbox.kext` so they cannot be modified at runtime. There is **no directory of `.sb` files on the iOS filesystem** to read — unlike macOS, where you can `cat /System/Library/Sandbox/Profiles/*.sb` and `/usr/share/sandbox/*.sb` as plain text. To see an iOS profile you must pull the **kernelcache**, extract `com.apple.security.sandbox`, and decompile the bytecode (the community tool is **SandBlaster**; Cellebrite published a maintained fork in 2023 that reverses the proprietary bytecode back to readable SBPL).

```
SBPL source (.sb, build-time)
        │  compiled
        ▼
profile bytecode  ──baked into──▶  Sandbox.kext __TEXT.__const  (read-only, signed)
        │
        ▼  at exec()
   process gets a profile + parameters  ──▶  kernel evaluates per operation
```

> 🖥️ **macOS contrast:** macOS keeps its profiles as editable text on disk (`/System/Library/Sandbox/Profiles/`, plus `application.sb` the App Sandbox derives from). iOS compiles them into a signed kext — there is nothing on the data partition to grep, and you cannot drop a custom profile. The mechanism is the same TrustedBSD MAC; the *availability of the policy as a file* is the difference.

---

### The container profile: one profile, parameterized per app

Here is the part that surprises people: **every App Store app shares the *same* sandbox profile.** There is one generic profile, historically named **`container`** (you will also see the platform variant), and it is what confines all third-party code. The kernel does not compile a fresh profile per app at install time. Instead the *one* container profile is **parameterized** at launch with per-process values:

- the app's **home / data container path** (the UUID directory — see below), which the profile's rules reference as a parameter so each app's `file-read*`/`file-write*` allowances resolve to *its own* container only;
- the app's **entitlements**, which the profile consults to decide whether certain operations are permitted at all.

So the *rules* are identical across apps; what differs is the substituted container path and the entitlement set. This is why two apps cannot see each other's files even though they run the same profile — the path parameter is bound to each process's own container, and a `file-read*` on the neighbor's UUID directory is simply outside the allow-set.

Entitlements are how an app **widens** its container. They are not "permissions to ask the user"; they are claims the *sandbox itself* checks. Examples you will meet:

| Entitlement | What the sandbox grants |
|---|---|
| `com.apple.security.application-groups` | read/write to the shared App Group container(s) |
| `keychain-access-groups` | which keychain access groups the app may use (see [[keychain-on-ios]]) |
| `com.apple.developer.…` (HealthKit, HomeKit, etc.) | the Mach services / capability extensions for that framework |
| `com.apple.private.…` (Apple-only) | privileged operations reserved for platform binaries |

Entitlements are embedded in the **code signature** (the `Entitlements` blob inside the embedded signature `SuperBlob`) and are immutable after signing — covered in [[code-signing-amfi-entitlements]]. AMFI validates the signature at exec; the sandbox then reads the now-trusted entitlements to parameterize the profile.

#### When the profile is applied: the exec path

The container is locked in **at `exec`**, not lazily on first file touch, and not by the app's own code. The ordering matters because it explains why an app can never "escape before it's caged":

```
exec()  ─▶  AMFI: validate code signature, decide platform-binary, read Entitlements blob
        ─▶  Seatbelt MACF hook: select the 'container' profile, bind parameters
              (home/container path from containermanagerd, entitlement set from the signature)
        ─▶  process now confined  ─▶  main() runs already inside the sandbox
```

By the time `main()` executes, the profile is already installed and the entitlements already bound — there is no window in which the app runs unconfined to "set up" its sandbox. (Apps may *narrow* themselves further at runtime via `sandbox_init`-style calls, but they can never widen beyond the profile + entitlements granted at exec.) `libsystem_sandbox.dylib` exposes the userspace surface (`sandbox_check` to test an operation, `sandbox_extension_consume` to activate a token), but the *binding* is the kernel's, done once, up front.

---

### Platform profile vs. third-party (container) profile

Not everything runs the container profile. iOS roughly splits the world by the **platform binary** flag (an AMFI/`amfid` property set when a binary is signed by Apple's platform certificate and lives on the signed system volume):

- **Apple platform daemons** (`mediaserverd`, `locationd`, `cfprefsd`, `containermanagerd`, `tccd`, …) each run under their **own named profile** compiled into the kext — tailored, sometimes broad, but still confined. Many of these *are* the brokers that hand data across the sandbox (next sections).
- **Third-party App Store apps and their extensions** all run the generic **`container`** profile, parameterized as above. Third-party code is never a platform binary on a stock device, so it never gets a bespoke broad profile.

This split is *the* security boundary between "Apple's code, which mediates resources" and "your code, which must ask Apple's code." It also matters forensically: the daemons that *log* and *store* cross-container activity (TCC, location, pasteboard) are Apple platform processes with their own data stores you will learn to parse.

> 🖥️ **macOS contrast:** macOS has the same platform-binary concept (used by SIP, the AMFI `amfi_get_out_of_my_way` boot-arg, and `csops`), but because the sandbox is opt-in, "platform vs third-party" mostly governs SIP and library-validation, not a universal confinement split. On iOS the split *is* the confinement model.

---

### The container on disk: UUIDs, the metadata plist, and the parsing skeleton

A third-party app does not occupy a directory named after its bundle id. It is split across **three** container locations, each a **random UUID** directory (see [[filesystem-layout-and-containers]] for the full tour):

```
/private/var/containers/Bundle/Application/<UUID-A>/        ← the signed .app bundle (read-only)
        MyApp.app/, iTunesMetadata.plist, .com.apple.mobile_container_manager.metadata.plist

/private/var/mobile/Containers/Data/Application/<UUID-B>/   ← the writable data container
        Documents/ Library/ tmp/ SystemData/
        .com.apple.mobile_container_manager.metadata.plist

/private/var/mobile/Containers/Shared/AppGroup/<UUID-C>/    ← shared App Group container (if entitled)
        .com.apple.mobile_container_manager.metadata.plist
```

The UUIDs are **not** derivable from the bundle id and differ between bundle, data, and shared containers — so given a UUID directory you cannot tell which app it belongs to **until you read its metadata file**. At the root of *every* container sits:

```
.com.apple.mobile_container_manager.metadata.plist   (binary plist)
```

managed by **`containermanagerd`** (implementation in the private `ContainerManagerCommon.framework`). Its keys are the Rosetta Stone for mapping UUID → app:

| Key | Meaning |
|---|---|
| `MCMMetadataIdentifier` | the **bundle id** that owns this container (this is how you label a UUID) |
| `MCMMetadataInfo` | a dict of container metadata — notably the sandbox material |
| `…SandboxProfileData` | the **compiled sandbox profile** for this container, stored as base64 `CFData` |
| `…SandboxProfileDataValidationInfo` | validation/version info for that profile |

So `containermanagerd` records, *per container*, the exact compiled profile that was applied — which is why this metadata plist is the canonical starting point both for "what is this UUID directory?" and for recovering the profile that confined it.

> 🔬 **Forensics note:** This metadata plist is your **container map**. In a full-filesystem extraction, walk every `…/Application/<UUID>/.com.apple.mobile_container_manager.metadata.plist`, read `MCMMetadataIdentifier`, and you have a UUID→bundle-id table for the whole device — the index every downstream artifact parser (iLEAPP, mvt) builds first. The system also indexes this in `/private/var/mobile/Library/FrontBoard/applicationState.db` (SQLite: `application_identifier_tab` + `kvs`, the values being NSKeyedArchiver blobs that include the bundle and data container paths and live sandbox-extension tokens). Either source maps UUIDs to apps; the metadata plists are simpler and survive even when the app is uninstalled but its data was orphaned.

---

### What the sandbox forbids (and how it shows up)

Inside the container profile, the prohibitions you will actually feel:

- **No cross-container reads/writes.** App A cannot `open()` a path inside App B's Data container. The neighbor's UUID directory is outside A's parameterized allow-set; the kernel returns `EPERM` (often surfaced to you as a generic "file not found"/permission error).
- **No enumeration of other apps.** You cannot list `/var/mobile/Containers/Data/Application/` to discover what else is installed; even `installed apps` is gated. The legitimate query is the entitlement-gated `LSApplicationWorkspace` / `canOpenURL` scheme list (itself rate-limited and declared in `LSApplicationQueriesSchemes`).
- **No raw access to system stores.** `TCC.db`, the keychain `keychain-2.db`, other apps' SQLite — all outside your container.
- **Restricted IPC.** `mach-lookup` to most system services is denied unless the profile/entitlements allow that specific service name; this is how a confined app is kept from talking to privileged daemons directly.
- **Restricted IOKit / network / process ops** per the profile's `iokit-open`, `network-*`, and `process-*` rules.

A sandbox denial is **not** a TCC prompt. It is silent (an errno) — there is no UI, no "Allow?" dialog. That dialog belongs to TCC, a different gate entirely. Concretely:

```
App A (com.acme.notes)                         App B (com.evil.snoop)
 home → …/Data/Application/<UUID-A>/            home → …/Data/Application/<UUID-B>/
        │                                                │
        │ open("…/<UUID-A>/Documents/diary.txt")  ✅     │ open("…/<UUID-A>/Documents/diary.txt")  ❌ EPERM
        ▼                                                ▼
  inside own container parameter                  outside B's container parameter
  → file-read* allowed                            → Seatbelt denies; no prompt, just errno
```

Both processes execute the *same* `container` profile bytecode. The only thing that differs is the bound home-path **parameter** — A's resolves to `<UUID-A>`, B's to `<UUID-B>` — so B's read of A's path falls outside its allow-set. There is no rule to "ask"; the deny is structural.

---

### App extensions: separate sandboxes, shared by group

An app's **extensions** — widgets (WidgetKit), share/action extensions, the notification-service extension, a custom keyboard, a Files document provider — are **not** part of the host app's process or sandbox. Each extension is a **separate confined process** with its **own** Data container UUID and its own `container` profile instance, hosted by the system (e.g. `pluginkit`/`extensionkit` infrastructure), not by the app. The host app and its extensions therefore **cannot** see each other's Data containers directly — same wall as any two unrelated apps.

The sanctioned bridge between them is the **App Group**: host + extensions all declare the same `group.<reverse-dns>` and read/write the one `…/Shared/AppGroup/<UUID>/` container. That is why "share a database/defaults between my app and its widget" is *only* possible through an App Group (or the keychain access group) — there is no implicit kinship in the sandbox.

> 🔬 **Forensics note:** Because extensions are independent sandboxed processes, a custom **keyboard** extension's learned-words cache, a **share** extension's queued payloads, and a **notification-service** extension's decrypted notification bodies live in the extension's *own* container or the shared App Group — **not** the host app's Data container. Enumerate `pluginkit`-installed extensions and their containers separately, or you will miss data the user attributes to "the app."

---

### Sandbox extensions: entitlement-gated capability tokens

If apps are walled into their containers, how does the user ever hand one a file from *outside* — a PDF from iCloud Drive, a photo, a document from another app? Via **sandbox extensions**: time-or-scope-limited capability **tokens** that *temporarily widen* a process's sandbox to include a specific path or service it would otherwise be denied.

A broker (a platform daemon — the document picker's backing service, `fileproviderd`, the share infrastructure) **issues** a token for an exact resource and hands it to the app; the app's runtime **consumes** it (`sandbox_extension_consume`) to activate the grant. The token is essentially an HMAC'd string naming the resource and the class of access:

| Extension class | Grants |
|---|---|
| `com.apple.app-sandbox.read` | read a specific file/dir handed in by the user |
| `com.apple.app-sandbox.read-write` | read+write a specific file/dir |
| `com.apple.security.exception.*` (macOS-style) | named broadening exceptions |

The crucial properties: the grant is **per-resource** (one file, not its folder), it was **mediated by a trusted broker** (the user picked it in a system UI the app cannot script), and it can be **revoked / scoped** (security-scoped bookmarks let the app re-acquire it later via `startAccessingSecurityScopedResource`). This is the on-device mechanism behind "the user gave me *this* file and only this file."

> 🖥️ **macOS contrast:** This is exactly the **Powerbox** model you met on macOS — `NSOpenPanel`/`NSSavePanel` run out of process, the user's selection issues a sandbox extension into your app, and security-scoped bookmarks persist it. iOS uses the same `sandbox_extension_*` primitives; the broker is `UIDocumentPickerViewController` / the Files providers instead of `com.apple.appkit.xpc.openAndSavePanelService`.

---

### How data legitimately flows: the brokered exits

Because direct cross-container access is impossible, all legitimate inter-app and user→app data movement goes through **brokers** — Apple-owned platform processes that the app *requests*, the *user* (usually) confirms, and which issue a sandbox extension or copy data across the wall on the app's behalf:

```
   App A container ──┐                            ┌── App B container
                     │   (no direct path exists)  │
                     ▼                            ▼
   ┌──────────────────── brokered exits (platform daemons) ────────────────────┐
   │  Share sheet  (UIActivityViewController → share/extension infra)          │
   │  Document picker (UIDocumentPickerViewController → fileproviderd token)    │
   │  App Groups   (group.<id> shared container — same-vendor apps + extensions)│
   │  Pasteboard   (UIPasteboard via pasteboardd; cross-app read is consented)  │
   │  Open-in-place / openURL (LSApplicationWorkspace, scheme-gated)            │
   └───────────────────────────────────────────────────────────────────────────┘
```

- **Share sheet** (`UIActivityViewController`) and **app/share extensions** — the app never reads the peer's files; it hands a payload to the system, which routes it.
- **Document picker** (`UIDocumentPickerViewController`) — the user selects a file in a system UI; a `fileproviderd` broker issues a `com.apple.app-sandbox.read[-write]` extension for *that* file. This is the canonical "import from outside" path.
- **App Groups** — apps signed by the same team and declaring `com.apple.security.application-groups` with a matching `group.<reverse-dns>` id share a real container at `…/Shared/AppGroup/<UUID>/`. This is *not* user-mediated; it is the sanctioned way an app shares state with **its own extensions** (widget, share extension, keyboard, notification-service).
- **Pasteboard** (`UIPasteboard`, daemon `pasteboardd`) — the general pasteboard crosses containers, but since iOS 16 an app reading pasteboard contents it did **not** write triggers a system **"Allow Paste"** confirmation (and `UIPasteboard.DetectionPattern` lets an app check for a *type* of content without reading it, avoiding the prompt).

> 🔬 **Forensics note:** The **App Group shared container** (`…/Shared/AppGroup/<UUID>/`) is where evidence loves to hide. App extensions (keyboards, share/notification-service extensions, widgets) run in their *own* sandbox but read/write the *shared* container, so cached drafts, queued uploads, keyboard learning, and notification payloads often land there rather than in the app's Data container. Always parse `…/Shared/AppGroup/` containers, not just `…/Data/Application/` — and use the same `MCMMetadataIdentifier` trick to attribute them. Pasteboard contents and history are held by `pasteboardd` (cache under `/private/var/mobile/Library/Caches/com.apple.Pasteboard/`); a copied password or 2FA code can persist there.

---

### TCC on iOS: the entitlement **plus** purpose-string gate

Now the second, orthogonal gate. **TCC — Transparency, Consent, and Control** — governs access to named *privacy resources*: camera, microphone, contacts (address book), calendars, reminders, photos, Bluetooth, motion/fitness, speech recognition, local network, Focus status, HomeKit, and App Tracking Transparency, among others. Each is a **service** string like `kTCCServiceCamera`, `kTCCServiceMicrophone`, `kTCCServiceAddressBook`, `kTCCServicePhotos`.

The decision flow is the part that bites builders. To touch a TCC-protected resource, an app needs **both** of:

1. **The capability** — for some services an **entitlement** (e.g. `com.apple.developer.…`) or simply being able to link the framework; and
2. **A purpose string** — an `NS…UsageDescription` key in the app's `Info.plist` (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSContactsUsageDescription`, `NSPhotoLibraryUsageDescription`, …) whose value is the human-readable sentence shown in the consent prompt.

Then, and only then:

3. **User consent** — `tccd` shows the system prompt **once**; the user's answer is recorded in `TCC.db`; subsequent launches read the stored decision and never re-prompt (until the user changes it in Settings).

```
 app calls AVCaptureDevice / CNContactStore / PHPhotoLibrary …
        │
        ▼
 ┌─ purpose string present in Info.plist? ─ NO ─▶ ⛔ PROCESS KILLED
 │     (NS…UsageDescription)                      "Termination Reason: Namespace TCC, Code 0"
 │                                                — no prompt, no denial: a hard crash
 └─ YES
        │
        ▼
 prior decision in TCC.db?  ── yes ──▶ allowed / denied / limited (no prompt)
        │ no
        ▼
 tccd shows consent prompt (uses the purpose string) ──▶ records decision in TCC.db
```

The **trap before any prompt** is the headline behavior: if you call a privacy API and the matching `NS…UsageDescription` is **absent**, the OS does **not** present a denial — it **terminates the process** with `Termination Reason: Namespace TCC, Code 0` ("This app has crashed because it attempted to access privacy-sensitive data without a usage description"). This is enforced *before* `tccd` is even consulted. It is a developer-discipline mechanism: Apple forces a user-facing justification to exist for every privacy access, and the absence of one is a fatal bug, not a runtime denial. (A subtle corollary: a third-party SDK that references a privacy API can force you to ship a purpose string even if *your* code never calls it — the linker/`Info.plist` requirement is static.)

> 🖥️ **macOS contrast:** Same crash, same `NS…UsageDescription` requirement — you saw `kTCCServiceCamera` etc. in the macOS `TCC.db`. The difference is iOS's **single** TCC store and the universality: every iOS app is sandboxed *and* must carry purpose strings, whereas on macOS an unsandboxed Developer-ID app still needs the purpose strings for TCC services but isn't otherwise contained. The entitlement+purpose-string+consent triad is the through-line.

---

### TCC.db as an artifact

On iOS the TCC store is a single SQLite database:

```
/private/var/mobile/Library/TCC/TCC.db          (per-user; iOS is effectively single-user)
```

The workhorse table is **`access`**. The schema below is the macOS Big Sur+ `access` table that iOS converged onto; the core columns (`service` … `last_modified`) have been stable since Big Sur, while the trailing `pid` / `pid_version` / `boot_uuid` / `last_reminded` are later (Monterey/Ventura-era) additions whose presence varies by release:

```
service, client, client_type, auth_value, auth_reason, auth_version,
csreq, policy_id, indirect_object_identifier_type, indirect_object_identifier,
indirect_object_code_identity, flags, last_modified, pid, pid_version,
boot_uuid, last_reminded
```

The exact column set drifts across TCC versions and is **not** identical on every iOS release — run `PRAGMA table_info(access);` against your iOS 26 reference image before relying on any specific column being present (this column list is a verify-on-image baseline, not a guarantee).

The columns that carry forensic weight:

| Column | Meaning |
|---|---|
| `service` | the TCC service, e.g. `kTCCServiceCamera`, `kTCCServiceMicrophone`, `kTCCServicePhotos` |
| `client` | the **bundle id** (or binary path) the row is about |
| `client_type` | `0` = bundle identifier, `1` = absolute path |
| `auth_value` | the decision: **0 = denied, 1 = unknown, 2 = allowed, 3 = limited** (`limited` is the Photos limited-library grant) |
| `auth_reason` | *how* the decision was set — user consent vs. user-set-in-Settings vs. MDM policy vs. system policy vs. "missing usage string" (numeric codes; see caveat below) |
| `csreq` | the **code-signing requirement blob** the client must satisfy — anti-impersonation, so another binary reusing the bundle id can't inherit the grant |
| `last_modified` | when this row last changed — **Unix epoch seconds** (not Apple Absolute Time!) |

A copy-first query (always `cp` before `sqlite3` — even a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`; see [[app-sandbox-and-filesystem-layout]]):

```sql
SELECT
  service,
  client,
  CASE auth_value
    WHEN 0 THEN 'denied' WHEN 1 THEN 'unknown'
    WHEN 2 THEN 'allowed' WHEN 3 THEN 'limited' END AS decision,
  auth_reason,
  datetime(last_modified, 'unixepoch') AS changed_utc
FROM access
ORDER BY last_modified DESC;
```

This answers, per app: *which* privacy resources it was granted or denied, and *when that state last changed*. "Did this messaging app ever have microphone access, and was it revoked the day before the incident?" is a `last_modified` + `auth_value` question.

> 🔬 **Forensics note (timestamp zoo):** TCC.db's `last_modified` is **plain Unix epoch** — do **not** add the Apple Absolute Time offset `978307200` you use for `knowledgeC`/Safari/most iOS stores. Adding it silently shifts every TCC timestamp ~31 years into the future. TCC is one of the handful of iOS SQLite stores on the Unix epoch; this lands in [[the-ios-timestamp-zoo]]. iLEAPP and mvt both have TCC parsers; APOLLO has a TCC module that joins this against the unified log.

> ⚖️ **Authorization:** TCC.db proves an **authorization state and its change history** — that consent existed and when it flipped — **not** that the resource was *used*. "Camera was `allowed` since 2026-03-01" is not evidence a photo was taken at the incident; correlate with the camera roll (`Photos.sqlite`), the unified log (`tccd`/`mediaserverd` access events), and `knowledgeC`/Biome app-in-focus to show actual use. Keep that distinction explicit in any report, and confine your examination to the authorized scope — pulling `/var/mobile/Library/TCC/` is full-filesystem territory, which carries its own legal-authority and acquisition-method constraints (see [[ios-forensics-landscape-and-authorization]]).

> ⚠️ **ADVANCED:** Writing to a device's live `TCC.db` (to grant yourself access, or to plant/erase a row) requires defeating the sandbox + the signed system volume — i.e. a jailbreak — and on a non-jailbroken iOS 26 device it is simply not reachable. Don't model your understanding on "just edit the row"; on iOS that is a privileged exploit, not a config change. The legitimate way to flip a grant is Settings → Privacy & Security (which `tccd` writes), and the legitimate way to *read* the file for an exam is an authorized full-filesystem acquisition.

A caveat to stay honest: the **`auth_reason` numeric codes** (user consent, user set, system set, service policy, MDM policy, missing-usage-string, entitled, …) are not officially documented and have shifted across TCC versions. Read the *meaning* (was this user consent or policy?), and **confirm the exact integer→reason map against the current `tccd` on your reference image** rather than hard-coding it from memory.

---

### The location exception: not in TCC

A trap that catches macOS-trained examiners: **location authorization is *not* in `TCC.db`.** Location is owned by **`locationd`**, which keeps its own per-client authorization store:

```
/private/var/root/Library/Caches/locationd/clients.plist     (binary plist, locationd runs as root)
/private/var/mobile/Library/Preferences/com.apple.locationd.plist  (master Location Services on/off + state)
```

In `clients.plist`, each client (keyed by bundle id) carries an **`Authorization`** value — broadly `2` = while-in-use, `4` = always (system services also use `4`) — plus app-supplied keys. The purpose strings differ too: location uses `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription`, and the missing-string crash applies the same way, but the *decision record* lives in `locationd`, not `tccd`.

> 🔬 **Forensics note:** A short-lived **`TemporaryAuthorization`** key can appear in a client's `clients.plist` entry while the app is foregrounded and holding a one-time/"allow once" grant — and it is **deleted when the app closes**, so its *absence* does not prove the app never had location. To reconstruct "did this app have location and when," cross-reference `clients.plist` with `routined`'s location stores and the unified log; location-history parsing proper is [[location-history]]. The takeaway here: when you enumerate "what private resources did app X hold," remember location is a separate store with separate semantics.

## Hands-on

There is **no on-device shell** — everything below runs on the **Mac**, against the **Simulator** (real schemas, but no kernel sandbox/TCC *enforcement*) or against a **mounted full-filesystem sample image**.

### Map a Simulator app's containers (the UUID → app problem, made easy)

```bash
# Boot a simulator, then ask CoreSimulator for an app's container paths by bundle id:
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl get_app_container booted com.apple.mobilesafari app    # the .app bundle
xcrun simctl get_app_container booted com.apple.mobilesafari data   # the Data container
xcrun simctl get_app_container booted com.apple.mobilesafari groups # App Group container(s)
# → /Users/you/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<UUID>
```

On a **real image** you don't have `simctl` to resolve the UUID — you read the metadata plist instead:

```bash
# For each UUID container, recover its owning bundle id (the forensic container map):
plutil -extract MCMMetadataIdentifier raw \
  "/path/to/image/private/var/mobile/Containers/Data/Application/<UUID>/.com.apple.mobile_container_manager.metadata.plist"
# → com.burbn.instagram
```

### Read the Simulator's TCC.db and drive it with `simctl privacy`

The Simulator keeps a per-device TCC store under the device's `data/` tree (no SEP, no kernel TCC — it's a plain SQLite the host writes). Find and read it:

```bash
DEV=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
ROOT=~/Library/Developer/CoreSimulator/Devices/$DEV/data
find "$ROOT" -name TCC.db 2>/dev/null     # locate it; copy before querying
cp "$ROOT/Library/TCC/TCC.db" /tmp/sim_tcc.db
sqlite3 /tmp/sim_tcc.db \
  "SELECT service, client,
          CASE auth_value WHEN 0 THEN 'denied' WHEN 2 THEN 'allowed'
                          WHEN 3 THEN 'limited' ELSE 'unknown' END,
          datetime(last_modified,'unixepoch')
   FROM access ORDER BY last_modified DESC;"
```

Mutate consent the way `tccd` would, without any UI, then re-read the table to watch `auth_value` + `last_modified` change:

```bash
xcrun simctl privacy booted grant  photos     com.example.MyApp   # auth_value → 2
xcrun simctl privacy booted revoke microphone com.example.MyApp   # auth_value → 0
xcrun simctl privacy booted reset  all         com.example.MyApp   # row removed → next call re-prompts
```

### Prove the missing-purpose-string crash is structural, not a denial

```bash
# Extract entitlements + show the privacy purpose strings the app actually declares:
codesign -d --entitlements :- /path/to/Some.app 2>/dev/null        # entitlements (sandbox/keychain/app-groups)
plutil -p /path/to/Some.app/Info.plist | grep -i UsageDescription   # the NS…UsageDescription gate keys
# An app calling AVCaptureDevice with NO NSCameraUsageDescription terminates:
#   "Termination Reason: Namespace TCC, Code 0" — visible in the crash log, NOT a tccd denial row.
```

### Recover the compiled sandbox profile that confined an app

```bash
# The container metadata plist stores the per-container compiled profile as base64 CFData:
plutil -p "/path/to/image/.../Data/Application/<UUID>/.com.apple.mobile_container_manager.metadata.plist" \
  | grep -A2 SandboxProfileData
# For the kernelcache profiles themselves (the 'container' / platform profiles), pull the kernelcache and
# decompile Sandbox.kext bytecode with SandBlaster (Cellebrite fork) — see Labs/Further reading.
```

## 🧪 Labs

> The Simulator teaches **structure and schema** with real SQLite/plist formats, but it is **not** the enforcement model: there is **no `Sandbox.kext`, no kernel container confinement, no SEP, and no Data-Protection at rest** — the Simulator runs as ordinary macOS processes, so "sandbox denial" and "BFU/AFU decryptability" cannot be demonstrated there. For enforcement behavior, reason from a sample full-filesystem image (Josh Hickman / Digital Corpora) in the read-only walkthroughs.

### Lab 1 — Build a UUID → app container map (Simulator)

**Substrate: Xcode Simulator.** *Fidelity caveat: real container layout and metadata plists, but no kernel enforcement — this teaches the parsing skeleton, not confinement.*

1. Install two apps to a booted simulator (or use the built-ins). List Data containers:
   `ls ~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/`
2. For each `<UUID>`, `plutil -extract MCMMetadataIdentifier raw …/<UUID>/.com.apple.mobile_container_manager.metadata.plist` to recover its bundle id.
3. Build a two-column table (UUID, bundle id). Confirm the UUIDs are **not** derivable from the bundle ids and that the bundle vs. data containers for the *same* app have **different** UUIDs.
4. Repeat for `…/Containers/Shared/AppGroup/` — note which apps share a group container with their extensions.

### Lab 2 — Watch TCC decisions land in TCC.db (Simulator)

**Substrate: Xcode Simulator + `simctl privacy`.** *Fidelity caveat: the Simulator's `TCC.db` is a plain host SQLite with no `tccd`/SEP gating; the schema is real, the enforcement is not.*

1. Locate and **copy** the device `TCC.db` (`find … -name TCC.db`, then `cp`).
2. `xcrun simctl privacy booted grant photos <bundleid>`; re-query `access` and find the new row (`auth_value=2`).
3. `revoke microphone <bundleid>` and `reset all <bundleid>`; observe `auth_value` flip to `0` and the row disappear. Note that `last_modified` is **Unix epoch** — verify `datetime(last_modified,'unixepoch')` reads correctly and that adding `978307200` would push it to ~2057.
4. Record the `auth_reason` value `simctl` writes vs. a value you'd expect from a real user prompt; this is why the numeric map needs confirming per image.

### Lab 3 — Force and read the missing-purpose-string crash (Simulator)

**Substrate: Xcode Simulator + a throwaway Xcode app.** *Fidelity caveat: the *crash* is the real OS behavior (it's enforced in the framework, which the Simulator does run); only the at-rest encryption story is absent.*

1. In Xcode, make a trivial app that calls `AVCaptureDevice.requestAccess(for: .video)` on launch. **Omit** `NSCameraUsageDescription` from `Info.plist`.
2. Run on the simulator → it terminates with `Termination Reason: Namespace TCC, Code 0`. Read the crash log under `~/Library/Logs/DiagnosticReports/` (or Xcode's Devices & Simulators → View Device Logs).
3. Add `NSCameraUsageDescription` with a sentence; re-run → now you get a *prompt* (or a recorded decision), not a crash. You have demonstrated that the purpose string is a **pre-prompt structural gate**, not a consent step.

### Lab 4 — Read-only walkthrough: recover a real container's sandbox profile

**Substrate: read-only walkthrough over a public sample full-filesystem image.** *Fidelity caveat: device-only — you cannot reproduce a parameterized kernel profile on the Simulator; this is narration + offline artifact parsing.*

1. On a sample image, open any third-party `…/Data/Application/<UUID>/.com.apple.mobile_container_manager.metadata.plist` and extract `MCMMetadataInfo → SandboxProfileData` (base64).
2. Note that this is the **compiled** profile for *that* container — the generic `container` profile parameterized with this app's path/entitlements. To turn the generic kernelcache profiles into readable SBPL, the walkthrough is: pull the IPSW's kernelcache → extract `com.apple.security.sandbox` → run **SandBlaster** → read the `(allow file-read* (subpath …))` rules that reference the container parameter.
3. Without running anything device-side, write two sentences: what does the `container` profile let an app read inside its own UUID directory, and how does the path *parameter* keep App A out of App B?

### Lab 5 — Enumerate "what private resources did app X hold" across all stores

**Substrate: read-only walkthrough over a sample image.** *Fidelity caveat: device-only stores (`tccd`, `locationd`, `pasteboardd`) do not populate on the Simulator; use the sample image.*

1. From `TCC.db.access`, list every `service`/`auth_value`/`last_modified` for one target `client` bundle id.
2. Separately, open `…/locationd/clients.plist` and read that bundle id's `Authorization` value — prove to yourself location is a **different** store with different semantics.
3. Check the app's **App Group** shared container and `pasteboardd` cache for resource-bearing data the Data container lacks.
4. Produce a one-app "privacy posture" sheet: camera/mic/photos/contacts from TCC, location from locationd, and where each timestamp's epoch differs. This is the deliverable shape for [[third-party-app-methodology]].

## Pitfalls & gotchas

- **Sandbox ≠ TCC.** A "permission denied" from the sandbox is a silent `EPERM` with no UI; a TCC outcome is a one-time prompt then a stored decision. Treating a cross-container read failure as "a permissions dialog should appear" wastes hours — that wall is the sandbox, which never prompts.
- **Missing purpose string is a *crash*, not a denial.** `Namespace TCC, Code 0` kills the process *before* `tccd`. New builders read it as "permission denied" and look for a settings toggle; the fix is adding the `NS…UsageDescription` to `Info.plist`. And a third-party SDK can force a purpose string you didn't think you needed (static reference to a privacy API).
- **TCC.db `last_modified` is Unix epoch — not Apple Absolute Time.** Reflexively adding `978307200` (correct for `knowledgeC`, Safari, Messages) shifts every TCC timestamp ~31 years forward. This is the single most common TCC-parsing error.
- **Location is not in TCC.** If you grep `TCC.db` for a location grant you'll find nothing. It's in `locationd`'s `clients.plist`, with `Authorization` integers (2/4) and a *self-deleting* `TemporaryAuthorization` key — absence is not proof of "never granted."
- **UUID directories are opaque without the metadata plist.** Don't try to infer the app from the path; read `MCMMetadataIdentifier`. And map the **App Group** containers too — the Data container alone misses extension-written evidence.
- **`auth_value=3` is "limited," not a typo.** It's the Photos limited-library grant; treating only `2` as "had access" undercounts apps with partial photo access. And `auth_reason` numeric codes are undocumented/version-drifting — confirm them against your reference image, don't hard-code from memory.
- **The Simulator does not enforce any of this.** No `Sandbox.kext`, no real `tccd`, no SEP, no at-rest encryption. It is faithful for **schema and layout** and for the **purpose-string crash**, and worthless for demonstrating confinement or BFU/AFU decryptability — use sample images for those.
- **iOS profiles aren't files on disk.** There is no `/System/Library/Sandbox/Profiles/` to read; the compiled `container`/platform profiles live in `Sandbox.kext __TEXT.__const`. Recovering them means kernelcache extraction + SandBlaster, not a `cat`.
- **`csreq` defeats bundle-id spoofing.** A TCC grant is bound to the client's code-signing requirement, so re-signing a different binary with the victim's bundle id does **not** inherit its camera/mic grant — relevant when you're reasoning about whether a resigned/repackaged app could ride an existing consent.

## Key takeaways

- iOS confinement is **two orthogonal gates**: the **sandbox** (kernel, mandatory, walls a *process* into its container) and **TCC** (userspace `tccd`, consent-driven, governs *privacy data classes*). An app can be sandbox-legal yet TCC-denied, and TCC never mediates cross-container access — that's purely the sandbox.
- The sandbox is **universal and non-opt-out** on iOS (vs. opt-in on macOS). All third-party apps share **one** generic **`container`** profile, **parameterized** per process with the app's container path and entitlements; entitlements are how an app *widens* its sandbox, validated from the signed Entitlements blob.
- Compiled profiles live **inside `Sandbox.kext`** (`__TEXT.__const`), not as `.sb` files on disk; recovering an iOS profile means kernelcache extraction + **SandBlaster**.
- Containers are **UUID directories** (bundle / data / shared, each a different UUID); `.com.apple.mobile_container_manager.metadata.plist` (`MCMMetadataIdentifier`, `SandboxProfileData`) is the **UUID → app** map and the per-container compiled profile, written by `containermanagerd`.
- Data crosses the wall only through **brokers**: share sheet, **document picker** (issues `sandbox_extension` tokens for one file), **App Groups** (same-team app↔extension shared container), and the consented **pasteboard**. App Group containers are a top forensic hiding spot.
- **TCC's gate is entitlement *plus* `NS…UsageDescription`**: a missing purpose string **crashes** the process (`Namespace TCC, Code 0`) *before* any prompt — a structural developer requirement, not a runtime denial.
- **`TCC.db` (`/private/var/mobile/Library/TCC/TCC.db`, table `access`)** answers "did app X ever have camera/mic/contacts/photos, and when did it change?" via `service`/`client`/`auth_value`(0/1/2/3)/`last_modified` — and `last_modified` is **Unix epoch**, not Apple Absolute Time.
- **Location is the exception** — held by `locationd` in `clients.plist`, not TCC — and TCC.db proves *authorization state*, not *use*: correlate with the camera roll, unified log, and Biome/`knowledgeC` to show a resource was actually exercised.

## Terms introduced

| Term | Definition |
|---|---|
| Seatbelt / `Sandbox.kext` | The iOS sandbox: a TrustedBSD MAC kernel policy module (`com.apple.security.sandbox`) that evaluates a per-process profile on filesystem/IPC/network/IOKit operations |
| SBPL | Sandbox Profile Language — the Lisp-like source for sandbox rules; compiled to bytecode and baked into the kext, not shipped as text on iOS |
| `container` profile | The single generic sandbox profile applied to all third-party apps, parameterized per process with the app's container path and entitlements |
| Platform binary | A binary signed by Apple's platform cert on the signed system volume; Apple daemons get bespoke profiles, third-party code always gets `container` |
| Container metadata plist | `.com.apple.mobile_container_manager.metadata.plist` at each container root; `MCMMetadataIdentifier` maps UUID→bundle id, `SandboxProfileData` holds the compiled profile |
| `containermanagerd` | Daemon (ContainerManagerCommon.framework) that creates/manages app containers and writes the metadata plist |
| Sandbox extension | An entitlement/broker-issued capability token that temporarily widens a process's sandbox to one resource (`com.apple.app-sandbox.read[-write]`); consumed via `sandbox_extension_consume` |
| App Group | A shared container (`…/Shared/AppGroup/<UUID>/`) for same-team apps + their extensions, gated by `com.apple.security.application-groups` |
| TCC | Transparency, Consent & Control — userspace privacy-permission system (`tccd`) governing camera/mic/contacts/photos/etc. per app |
| Purpose string | An `NS…UsageDescription` Info.plist key required before a privacy API call; its **absence** crashes the process (`Namespace TCC, Code 0`) before any prompt |
| `TCC.db` (`access`) | `/private/var/mobile/Library/TCC/TCC.db`; the `access` table records per-app decisions (`service`, `client`, `auth_value` 0/1/2/3, `auth_reason`, `csreq`, `last_modified` in **Unix epoch**) |
| `auth_value` | TCC decision: 0=denied, 1=unknown, 2=allowed, 3=limited (Photos limited-library) |
| `csreq` | Code-signing requirement blob a TCC client must satisfy — binds a grant to a specific signed binary, defeating bundle-id spoofing |
| `locationd` `clients.plist` | `/private/var/root/Library/Caches/locationd/clients.plist` — per-app location authorization (`Authorization` 2=while-in-use/4=always), **not** in TCC |
| SandBlaster | Community/Cellebrite tool that decompiles iOS `Sandbox.kext` bytecode profiles back to readable SBPL |

## Further reading

- **Apple Platform Security Guide** — "App sandbox", "Protecting access to user's information / TCC", entitlements model (security.apple.com / developer.apple.com/documentation/security).
- **Apple Developer** — `NSCameraUsageDescription` (and the other `NS…UsageDescription` keys), `UIDocumentPickerViewController`, App Groups, `UIPasteboard` privacy (Information Property List / BundleResources docs).
- **Dionysus Blazakis, "The Apple Sandbox"** (ise.io) — the foundational reverse-engineering of Seatbelt/SBPL and profile compilation.
- **Jonathan Levin, *MacOS and iOS Internals* Vols I–III** + newosxbook.com `jtool2` — sandbox internals, MACF hooks, `containermanagerd`, kernelcache anatomy.
- **SandBlaster** (malus-security/sandblaster + Cellebrite's 2023 fork) — decompiling compiled iOS sandbox profiles; `8ksec.io` "Reading iOS Sandbox Profiles" and the `ios-sandbox-profiles` corpus for worked examples.
- **Nick Santoine, "A Worm's Look Inside: Apple's Sandboxing"** (nsantoine.dev) — container/metadata-plist and sandbox-extension mechanics.
- **Magnet Forensics / d204n6 (Ian Whiffin)** — "iOS: Tracking Bundle IDs for Containers, Shared Containers, and Plugins" — the forensic container-map methodology.
- **Sarah Edwards, mac4n6.com** — "You down with TCC?" (the APOLLO TCC module) and the unified-log TCC angle; **Alexis Brignoni, iLEAPP** — TCC + container parsers.
- **TheForensicScooter / DFIR Review** — "iOS Location Services and System Services ON or OFF?" — `locationd` `clients.plist` semantics and the `TemporaryAuthorization` pitfall.
- **HackTricks** (macOS sandbox / macOS TCC pages) and **Karol Mazurek, "Snake&Apple VIII — App Sandbox" / "IX — TCC"** — the modern `access` schema and column meanings.
- `man sandbox-exec`, `man codesign`, `man plutil`, `man sqlite3`; `xcrun simctl help privacy`.

---
*Related lessons: [[code-signing-amfi-entitlements]] | [[filesystem-layout-and-containers]] | [[app-sandbox-and-filesystem-layout]] | [[the-app-sandbox-from-the-developer-side]] | [[location-history]] | [[the-ios-timestamp-zoo]]*
