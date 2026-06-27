---
title: "Shortcuts & the automation surface"
part: "06 — Automation & Operations"
lesson: 00
est_time: "45 min read + 20 min labs"
prerequisites: [app-sandbox-and-filesystem-layout]
tags: [ios, automation, shortcuts, app-intents, forensics]
last_reviewed: 2026-06-26
---

# Shortcuts & the automation surface

> **In one sentence:** iOS automation is a single, sandboxed, broker-mediated action graph — Shortcuts — where every capability must be *declaratively exposed* by an entitled app or the system (no shell, no AppleScript underneath), and the workflows, their triggers, and their run history are all on-disk artifacts that reveal user-set behavior and can themselves be instruments of anti-forensics.

## Why this matters

On macOS you had three overlapping automation stacks with a real interpreter under each: Automator workflows, AppleScript/JXA via `osascript`, and (since Monterey) Shortcuts as a friendly front door that could still "Run Shell Script". On iOS, **only the last one survives, and the interpreter is gone.** There is no `osascript`, no `/bin/sh` a user can reach, no `Run AppleScript` action. Shortcuts *is* the automation surface, and it is a brokered graph of pre-vetted actions executed by a system daemon on the user's behalf.

For the builder, that reframes "how do I script the phone?" into "how do I make my app's capabilities *eligible* to be scripted?" — the App Intents framework. For the forensic examiner, the Shortcuts subsystem is an underexploited goldmine: the set of shortcuts and **automations** a user configured is a direct readout of intent and habit (a "scan this NFC tag → unlock the safe app" automation is evidence of behavior), the workflows are stored in a parseable Core Data store, and a malicious automation triggered by arrival/Focus/NFC can be a **dead-man's switch** that deletes data or alerts the suspect the moment an examiner does something observable. You need to find these before you trip one.

## Concepts

### The automation surface: one brokered graph, no shell

Think of iOS automation as a directed acyclic graph of *actions*. Each action is a typed function with input ports and output ports; the runner walks the graph, passing each action's output forward as the next action's input (or into a named **variable**). Crucially, **an app process never executes another app's code.** When a shortcut step belongs to Maps or to a third-party app, the runner hands that step off, over XPC, to the providing process (or to a system daemon), which performs it inside *its own* sandbox and returns a result. The Shortcuts app is a conductor, not an interpreter.

This is the single most important mental-model reset from macOS:

> 🖥️ **macOS contrast:** On macOS, Shortcuts is one of *several* automation engines, and several of its actions are escape hatches to a real interpreter: `Run Shell Script` (→ `/bin/zsh`), `Run AppleScript` (→ `osascript`/`appleeventsd`), `Run JavaScript for Automation`. Automator workflows and raw AppleScript/JXA exist beside it. **None of that exists on iOS.** There is no user-reachable shell, no `osascript`, no Apple Events bus, and the iOS Shortcuts action catalog has *no* "run script" primitive. Every capability on iOS must be surfaced as a vetted action by an entitled app or the OS. iOS Shortcuts is therefore the *complete* user-facing automation API — narrow, sandboxed, and brokered — where macOS Shortcuts is a convenience layer over an open automation substrate.

### Anatomy of the Shortcuts stack

The same engine — **WorkflowKit.framework** (`/System/Library/PrivateFrameworks/WorkflowKit.framework`) — backs Shortcuts on iOS, iPadOS, *and* macOS. The lineage matters for everything that follows: Apple bought the third-party app **Workflow** in 2017 and rebranded it Shortcuts, which is why the entire stack is littered with the reverse-domain prefix `is.workflow.*` and the bundle/group identifier `is.workflow.my.app`. When you see `is.workflow.actions.gettext` in 2026, you are looking at a 2014 startup's namespace fossilized into Apple's OS.

The runtime pieces you care about:

| Component | Role |
|---|---|
| `Shortcuts.app` (`com.apple.shortcuts`) | The editor + "My Shortcuts"/"Automation"/"Gallery" UI. Just a front-end. |
| `WorkflowKit.framework` | The model (workflow/action/parameter types), the runner, the action catalog (`WFActions.plist`), import/signing. Shared across platforms. |
| `siriactionsd` | The background daemon that **runs and syncs** shortcuts, evaluates automation triggers, and brokers action hand-offs. The closest thing to "the Shortcuts engine running headless." |
| `siriknowledged` | Siri/Suggestions knowledge graph that feeds shortcut & action suggestions (ties into the Biome/knowledge stack). |
| `WorkflowExtensions` / `ActionExtensions` | App- and system-provided extensions that *implement* individual actions, invoked over XPC by the runner. |
| App Intents providers | The modern way apps contribute actions — see below. The runner discovers them via system intent metadata, not a per-app extension. |

```
                 user taps "Run" / a trigger fires
                              │
                         Shortcuts.app  ──── edits ────┐
                              │ (XPC)                  ▼
                          siriactionsd  ◄──── reads Shortcuts.sqlite
                       (the WFRunner loop)            (Core Data store)
                              │
          ┌───────────────────┼───────────────────────────┐
          ▼ (XPC)             ▼ (XPC)                        ▼ (XPC)
   is.workflow.actions.*   App's AppIntent.perform()   System extension
   (built-in, in-proc)     (runs IN the app's sandbox)  (Maps, Files, …)
```

> 🔬 **Forensics note:** `siriactionsd` is the process that *executes* automations, so it is your best execution-evidence source. Its activity surfaces in the **unified log** (subsystem `com.apple.siri` / process `siriactionsd`) and shortcut runs are reflected in the **Biome/SEGB** and (pre-iOS-17) **knowledgeC** behavioural streams — i.e. a shortcut that fired leaves traces *outside* the Shortcuts store itself, which lets you corroborate (or contradict) the run-count metadata inside `Shortcuts.sqlite`. See [[biome-and-segb-streams]] and [[unified-logs-sysdiagnose-crash-network]].

### The action model: `is.workflow.actions.*` and the App Intents shift

Every step in a workflow is identified by a **`WFWorkflowActionIdentifier`** — a reverse-DNS string. There are two populations:

- **Built-in / first-party actions:** `is.workflow.actions.<name>`, e.g. `is.workflow.actions.gettext`, `is.workflow.actions.conditional`, `is.workflow.actions.repeat.count`, `is.workflow.actions.url`, `is.workflow.actions.downloadurl` ("Get Contents of URL"), `is.workflow.actions.notification`, `is.workflow.actions.delete.files`, `is.workflow.actions.deletephotos`. The full catalog ships as a property list inside WorkflowKit: `/System/Library/PrivateFrameworks/WorkflowKit.framework/WFActions.plist` — this is the authoritative dictionary mapping each identifier to its parameter schema, input/output types, and required entitlements.
- **App-contributed actions:** identified by the *contributing app's* bundle prefix. Historically these came through SiriKit/`INIntent` "donations"; in 2026 they come almost entirely through **App Intents** (next section). The runner resolves them to the providing process at run time.

A short field guide to the **high-signal built-in identifiers** you'll grep for when triaging a workflow (the "opcodes" that matter to an examiner):

| Action identifier | What it does | Why it's interesting |
|---|---|---|
| `is.workflow.actions.downloadurl` | Get Contents of URL (HTTP) | Network egress / webhook; the URL + body are literals. |
| `is.workflow.actions.url` | URL literal | Hard-coded endpoints, deeplinks. |
| `is.workflow.actions.runworkflow` | Run another shortcut | Chaining; resolve the callee to follow logic. |
| `is.workflow.actions.notification` | Show Notification | The alert text is a literal. |
| `is.workflow.actions.sendmessage` / `…sendemail` | Send Message / Email | Outbound comms with literal recipients/body. |
| `is.workflow.actions.deletephotos` | Delete Photos | **Destructive** — anti-forensic primitive. |
| `is.workflow.actions.delete.files` | Delete Files | **Destructive**. |
| `is.workflow.actions.setclipboard` | Set/Clear Clipboard | Clipboard wipe (anti-forensic) or stage. |
| `is.workflow.actions.conditional` | If / Else / End If | Control flow (mode 0/1/2). |
| `is.workflow.actions.repeat.count` / `…repeat.each` | Repeat / Repeat with Each | Loops. |
| `is.workflow.actions.choosefrommenu` | Choose from Menu | Interactive branch. |
| `is.workflow.actions.setvariable` / `…appendvariable` | Named variables | Explicit data staging. |
| `is.workflow.actions.gettext` / `…getvariable` | Text / Get Variable | Data plumbing. |
| `is.workflow.actions.runsshscript` | Run script over SSH | **Remote** exec — note: runs on a *remote host*, not the phone. |

A workflow is just an ordered array of these action dictionaries (`WFWorkflowActions`), each with an identifier and a `WFWorkflowActionParameters` dictionary. Data flow between actions and control flow (if/repeat/menu) are encoded *in the parameters*, not in any separate structure — covered under the file format below.

### The runner's data model: magic variables, the content graph, and type coercion

The thing that makes Shortcuts more than a macro recorder is its **content-item type system** — the heir to Workflow's "Content Graph". Every value flowing through the graph is a *typed content item* (text, number, image, file, URL, contact, date, dictionary, rich `AppEntity`, …). The runner performs **type coercion** at each edge: ask for the "text" of an image and it yields the filename; ask for the "date" of a file and it yields the modification date; ask for the "URL" of contact and it yields a derived link. This is why a shortcut author can wire almost any output into almost any input — the runner negotiates the conversion.

Three variable flavors carry these items between actions, and they appear differently on disk:

- **Magic Variables** — every action's *output* is implicitly available downstream as a token. No "set variable" action is emitted; instead, a later action's parameter value embeds a **`WFTokenAttachment`/`WFVariable`** reference keyed on the producing action's **`UUID`**. Parameter strings that mix literal text with variable references are stored as an *attributed-string* structure (a base string plus a runs/attachments array marking where each token sits).
- **Named (manual) variables** — created by `is.workflow.actions.setvariable` / `appendvariable`; referenced by name. These leave an explicit action in `WFWorkflowActions`.
- **Special/global variables** — `Shortcut Input`, `Clipboard`, `Current Date`, `Device Details`, etc. — synthesized by the runtime, referenced like any token.

> 🔬 **Forensics note:** Reconstructing a workflow's *logic* requires resolving these `UUID`-keyed token attachments back to the actions that produced them — exactly the same join you do for `GroupingIdentifier` control-flow blocks. The payoff: literal parameter values (a hard-coded webhook URL in a `Get Contents of URL` action, the text of a message to be sent, a file path to delete, an **LLM prompt** — see Apple Intelligence below) are stored *verbatim* in `WFWorkflowActionParameters`. You read the suspect's intent in plaintext, straight out of the plist, with no execution required.

### App Intents — how apps declaratively expose actions

App Intents (introduced iOS 16, the standard in 2026) is the framework that lets a third-party or first-party app contribute actions to the *entire* system automation surface — Shortcuts, Siri, Spotlight, the Action button, Control Center, interactive widgets, Focus filters — from **one Swift declaration**. It is the successor to SiriKit's `INIntent`/Intents-extension model and the old "intent donation" dance.

The defining property is **write-once, surface-everywhere** — one `AppIntent` declaration is harvested by the OS and projected onto every automation surface at once:

```
                      ┌──────────── Shortcuts app (custom workflows)
                      ├──────────── Siri / Apple Intelligence (voice + reasoning)
   one AppIntent  ───►├──────────── Spotlight (quick actions from search)
   + AppShortcut      ├──────────── Action button / Control Center
   declaration        ├──────────── Interactive widgets & Live Activities
                      └──────────── Focus filters
```

The core types (you'll meet these again in [[swift-swiftui-uikit-and-app-architecture]] and [[app-lifecycle-scenes-and-background-execution]]):

| Type | What it is |
|---|---|
| `AppIntent` | One action. Declares typed `@Parameter` inputs and a `perform() async throws -> some IntentResult` method that runs **in-process, in the app's own sandbox**. |
| `AppEntity` | A noun the system can reason about and pass between intents (a note, a track, a project) — gives Siri/Shortcuts referencable objects with stable IDs. |
| `AppShortcut` | Binds an `AppIntent` to natural-language trigger phrases and surfaces it system-wide **with zero user setup**. |
| `AppShortcutsProvider` | The app's manifest of `AppShortcut`s; the system harvests it at install time. |

The mechanism that matters forensically and for RE: when you build an app that adopts App Intents, the compiler emits a **`Metadata.appintents/`** bundle *inside the `.app`* (alongside the binary). It contains a machine-readable description of every intent, entity, parameter, and app-shortcut the app exposes — extractable from a distributed `.ipa` *without running anything*. (The internal filenames — e.g. an `extract.actionsdata` JSON blob plus a version/manifest — are tooling-version-dependent; **verify the exact layout against the bundle you're examining.**) This is the static-analysis hook: you can enumerate an app's *entire scriptable attack/automation surface* from its bundle. See [[the-app-bundle-and-ipa-structure]] and [[static-analysis-class-dump-and-disassemblers]].

> 🖥️ **macOS contrast:** On macOS you reverse-engineered an app's scriptability by reading its **`.sdef`** (scripting definition) and its Cocoa Scripting `NSScriptCommand` classes. `Metadata.appintents` is the iOS-era equivalent: a declarative, machine-readable manifest of everything the app lets the outside world invoke — but cross-platform (the same bundle drives macOS Shortcuts too) and tied to in-process `perform()` execution rather than the Apple Events dispatch you knew.

> ⚖️ **Authorization:** App Intents `perform()` runs with the *app's* entitlements and data-access grants, not the user's broad authority. An automation that "reads my medical app's entries" only works because that app chose to expose an `AppEntity`/`AppIntent` for it. When you assess what an automation *could* have exfiltrated or altered, scope it to the union of the contributing apps' entitlements — don't assume Shortcuts has god-mode. It is a broker, and the broker honors each provider's sandbox.

### Apple Intelligence in Shortcuts (iOS 26)

> ⚠️ The following is **iOS/iPadOS/macOS 26-era and fast-moving — re-verify capabilities and routing per release.**

iOS 26 wired Apple Intelligence into the automation surface from both directions:

- **The `Use Model` action.** A built-in Shortcuts action that prompts a large language model inline and returns the result as a content item. The author picks the backend: the **on-device foundation model** (~3B params, runs locally, works offline), the larger **Private Cloud Compute (PCC)** model, or **ChatGPT**. An optional follow-up mode keeps a conversational context. For builders this is the no-code front door to the same on-device model the **FoundationModels** framework exposes to apps.
- **Assistant schemas (`@AssistantIntent` / `@AssistantEntity`).** App Intents gained *schema* conformances — Apple-defined structures (mail, photos, files, etc.) that the rebuilt Siri/Apple Intelligence reasoning model recognizes, so an app's actions become invocable by natural-language assistant requests, not just explicit Shortcuts wiring.

> 🔬 **Forensics note:** A `Use Model` action is a **data-egress and intent artifact**. The *prompt text* is a literal in `WFWorkflowActionParameters` (recoverable from the store/export with no execution), and the *backend selector* tells you whether that data stayed on-device, went to PCC, or was sent to **ChatGPT** — a third-party egress channel with materially different discovery, retention, and privacy implications. An automation that pipes message/photo/location content into a `Use Model → ChatGPT` step is an exfiltration path worth flagging; the responses themselves are not persisted in the workflow, but the conversation may surface in `siriactionsd`/Apple-Intelligence unified-log entries or the provider's records. Treat model routing as a chain-of-custody fact, not a detail.

### Automation triggers — the part that has no macOS analogue

A bare *shortcut* runs when the user taps it. An **automation** is a shortcut bound to a **trigger** so it runs on an event. iOS splits these into **personal automations** (device events) and **Home automations** (HomeKit events). This is the richest forensic seam because the *trigger configuration is a statement of behavior*.

Personal-automation triggers (iOS/iPadOS 26 era — re-verify the exact set per release):

| Trigger | Fires when | Why an examiner cares |
|---|---|---|
| Time of Day | A clock time / sunrise / sunset | Scheduled, recurring behavior; a daily "cleanup" automation. |
| Alarm | An alarm is stopped/snoozed | Wake-time routines. |
| Sleep / Wake (Sleep Focus) | Sleep schedule boundaries | Daily rhythm. |
| Arrive / Leave (Location) | Entering/leaving a geofence | **Place-bound behavior** — "when I leave the office, wipe X". Encodes a meaningful location. |
| Before I Commute | Predicted commute time | Routine + a learned location pair. |
| NFC | A specific NFC tag is scanned | **Only the tag's UID is matched; tag contents are ignored.** A registered tag UID is a physical-token binding (a safe, a car mount, a hidden tag). |
| Wi-Fi | Joins a named network | Network-bound behavior; an SSID is a location proxy. |
| Bluetooth | Connects to a device | Pairs behavior to a car, headset, peripheral. |
| CarPlay | Connects/disconnects CarPlay | In-vehicle routines. |
| Focus | A Focus turns on/off | "When Work Focus turns off, …". |
| App | A named app is opened/closed | **"When app X opens, run Y"** — classic tripwire/anti-forensic hook. |
| Battery / Charger / Low Power | Level thresholds, plug/unplug | "On unplug, …". |
| Email/Message received, Reminder, Weather, etc. | Inbound events / conditions | Content-reactive behavior. |

Each automation also carries a **run mode**: *Run Immediately* (with *Ask Before Running* OFF) makes it fully hands-free; otherwise iOS shows a confirmation banner. The hands-free flag is the single most forensically significant property of an automation — it is the difference between a convenience and a silent tripwire.

**Home automations** are the second family. Bound to HomeKit events rather than device sensors, they fire on: *people arrive / leave* (the Home's geofence, evaluated per household member), *a time of day* (sunrise/sunset/clock), *an accessory is controlled* (a switch flipped, a lock operated), or *a sensor detects something* (motion, contact, a door opens, occupancy). These run through the Home stack (`homed`/HomeKit) and persist in the Home configuration as well as the Shortcuts store. Forensically they bind behavior to a **physical place and its occupants** — "when everyone leaves, run X" or "when the front-door lock is opened after 1am, notify Y" — and the accessory/sensor identifiers in the trigger localize the event to a specific room/device.

> 🔬 **Forensics note:** The list of configured automations, their triggers (the *specific* SSID, geofence coordinates, NFC tag UID, or app bundle ID), and the run-mode flag are persisted alongside the workflows. Enumerate every automation early in an exam: a "When app **Settings** opens → Run Immediately, Ask-Before-Running OFF → [Delete Files / Clear Clipboard / Get Contents of URL → attacker webhook]" automation is a **dead-man's switch**, and you may trip it by *touching the device at all*. This is a primary reason to acquire before you explore (see [[acquisition-sop-and-chain-of-custody]]).

### Where shortcuts run, and the consent model

A workflow declares *where it's allowed to appear and run* via `WFWorkflowTypes` — the same shortcut can be a tap-to-run tile, a Share Sheet extension, a Home Screen Quick Action, a widget tap target, an Apple Watch complication, a menu-bar item (macOS), or an automation body. Each context imposes its own constraints: a background-fired automation runs without UI, so any action that *needs* interaction (Choose from Menu, Show Alert) will stall or be skipped unless the automation is interactive.

Crucially, the broker still enforces **per-resource consent**. The first time a shortcut runs an action that touches a protected resource — Location, Photos, Contacts, Health, Files outside its own scope, a third-party app's `AppIntent`, or a *cross-app data hand-off* — the system prompts the user (a TCC-style grant), and for some sensitive cross-app flows iOS prompts **every time** unless the user opts to "Always Allow". This is why a malicious imported shortcut cannot silently vacuum your Photos on first run: it must clear the consent gate.

> 🔬 **Forensics note:** Those consent decisions are persisted (TCC and the per-app grant stores; see [[the-sandbox-and-tcc]]). A shortcut that *would* read Location or Photos but whose grant was never given may have been authored-but-never-effective — an important distinction between "capability present" and "capability exercised." Conversely, a granted prompt for an unusual action ("Allow this shortcut to access Health?") is itself a dated artifact of when the workflow first ran against that resource.

### Where Shortcuts live on disk

WorkflowKit persists workflows in a **Core Data SQLite store**. On macOS — which runs the *identical* WorkflowKit engine — it is here, and you can read it today:

```
~/Library/Shortcuts/Shortcuts.sqlite          (+ -wal / -shm sidecars)
```

On iOS/iPadOS the same store lives inside the **WorkflowKit shared app-group container** (`group.is.workflow.my.app`) under `/private/var/mobile/Containers/Shared/AppGroup/<UUID>/`. The exact subpath and filename are **OS-version-dependent — confirm against your acquired image rather than hard-coding a path** (the macOS path above is the stable, verifiable reference for the *schema*). The schema is recognizably Core Data (`Z`-prefixed tables and columns):

| Table | Holds |
|---|---|
| `ZSHORTCUT` | One row per shortcut: `ZNAME`, `ZWORKFLOWID` (stable UUID), `ZCREATIONDATE` / `ZMODIFICATIONDATE` / `ZLASTRUNEVENTDATE`, the denormalized `ZRUNEVENTSCOUNT` / `ZTRIGGERCOUNT`, `ZMINIMUMCLIENTVERSION`, and the rest of the `WFWorkflow`-dict metadata as discrete columns/blobs (`ZICON` FK, `ZIMPORTQUESTIONSDATA`, `ZINPUTCLASSESDATA`, `ZOUTPUTCLASSESDATA`). |
| `ZSHORTCUTACTIONS` | The serialized action graph — a **binary-plist blob in the `ZDATA` column** whose root is the bare `WFWorkflowActions` *array* (the same action array that sits inside a `.shortcut`'s `WFWorkflow` dict), linked to its shortcut by the `ZSHORTCUT` FK. |
| `ZTRIGGER` | One row per automation trigger: `ZENABLED`, **`ZSHOULDPROMPT`** (the "Ask Before Running" flag), `ZSHOULDNOTIFY` / `ZSHOULDRECUR`, `ZSOURCE`, `ZDISABLEMENTREASON`, and a `ZDATA` blob carrying the *trigger configuration* — the geofence, SSID, NFC tag UID, or app bundle ID. This is the behavior-as-evidence seam. |
| `ZTRIGGEREVENT` | Per-firing records for a trigger (`ZDATECREATED`, an `ZEVENTINFO` blob) — *when the condition was actually observed*. |
| `ZSHORTCUTRUNEVENT` | One row **per execution**: `ZDATE`, `ZOUTCOME`, `ZSOURCE`, plus a `ZTRIGGER` FK tying a run to the trigger that fired it. The real run history; `ZSHORTCUT`'s run counts are rollups of these. |

(Column names above are macOS-26-verified; the iOS Core Data model is the same family but **confirm every column via `.schema` against your image** — Core Data renames across model versions.)

> 🔬 **Forensics note:** Because `ZSHORTCUTACTIONS` is a binary-plist blob of the *action array*, you recover the full workflow logic — every `is.workflow.actions.*` identifier and its parameters — straight from the device store, **no `.shortcut` export needed and no signature to defeat.** Dump the blob, `plutil -convert xml1`, and read it like any other plist. Core Data `Z…DATE` columns are **Apple Cocoa / Mac Absolute Time** (seconds since 2001-01-01 UTC) — add **978307200** to convert to Unix epoch. Don't assume column names; run `.schema ZSHORTCUT` against your copy and map them, because Core Data renames columns across model versions. See [[the-ios-timestamp-zoo]].

**iCloud / CloudKit sync.** Shortcuts sync via **CloudKit** (the private database of the user's iCloud account), which is why a single Shortcuts library appears on all the user's devices and why a *cloud* acquisition can recover shortcuts even from a device you don't have. There is also a legacy iCloud-Drive footprint under the `iCloud~is~workflow` ubiquity container. This matters for scope:

> ⚖️ **Authorization:** Shortcuts are part of the iCloud-synced data set. Pulling them from CloudKit is a **cloud acquisition** governed by separate legal authority from a device seizure, and if the account has **Advanced Data Protection** enabled the relevant CloudKit data is end-to-end encrypted and not server-recoverable. Scope your warrant/consent to the cloud account explicitly, and don't assume "I have the phone" extends to "I have the cloud copy." See [[icloud-acquisition-and-advanced-data-protection]].

### The `.shortcut` export: AEA signing + the WFWorkflow plist

When a user *exports/shares* a shortcut, they get a `.shortcut` file. Its history is a two-era story:

- **Pre-iOS 15:** a plain **binary property list** — the `WFWorkflow` dictionary, directly. Rename to `.plist`, `plutil -p`, done.
- **iOS 15 → today:** the shareable `.shortcut` is an **Apple Encrypted Archive (AEA)**. For shortcuts the relevant profile is **profile 0 — *signed but not encrypted***. The container's auth-data field (`AEA_CONTEXT_FIELD_AUTH_DATA`) is a binary plist carrying the **signing certificate and the chain up to Apple's root**; the payload is an **LZFSE-compressed Apple Archive (`.aar`)** that, once extracted, contains the same `WFWorkflow` plist as before. Signing exists to make tampering with a shared shortcut detectable (Apple co-signs cloud-shared shortcuts), *not* to hide the contents — profile 0 means the bytes are readable once you peel the AEA wrapper. (Apple's `shortcuts sign` CLI and tools like `shortcut-sign` produce/round-trip these.)

The `WFWorkflow` dictionary — the shape of the **export payload** and the in-memory / iCloud record — has a stable top level. (The on-device Core Data store *decomposes* this dict: the `WFWorkflowActions` array lands in `ZSHORTCUTACTIONS.ZDATA` while the surrounding keys below are spread across `ZSHORTCUT` columns; it's reassembled into one dict only on export.) Its top-level shape:

| Key | Meaning |
|---|---|
| `WFWorkflowActions` | The ordered array of action dictionaries — the program. |
| `WFWorkflowClientVersion` / `WFWorkflowClientRelease` | The Shortcuts build/release that authored it (an authoring-environment fingerprint). |
| `WFWorkflowMinimumClientVersion` / `…VersionString` | Minimum Shortcuts version required to run it. |
| `WFWorkflowImportQuestions` | Prompts shown at import (the "ask the importer to fill in X" setup). |
| `WFWorkflowIcon` | Glyph + color (a small dict, not an image). |
| `WFWorkflowInputContentItemClasses` | What input types the shortcut accepts (Share Sheet typing). |
| `WFWorkflowTypes` | Where it's allowed to appear (e.g. `Watch`, `MenuBar`, `QuickActions`, `ActionExtension`, `NCWidget`). |
| `WFWorkflowName` | Display name (often absent in the payload; the name lives in `ZSHORTCUT`). |

Each element of `WFWorkflowActions` is `{ WFWorkflowActionIdentifier, WFWorkflowActionParameters }`. **Control flow is encoded in parameters, not structure.** An `if`/`repeat`/`choose-from-menu` block is *three* (or more) flat actions sharing a `GroupingIdentifier` (a UUID), distinguished by a `WFControlFlowMode` parameter: **`0` = start (the `if`/`repeat`/`menu` head), `1` = a middle branch (`else` / a menu item), `2` = end (`endif`/`endrepeat`)**. Data flow between actions uses per-action **`UUID`**s: an action that produces output gets a `UUID`, and a later action references that output as a *variable token* keyed on that UUID inside its parameter values. To read a workflow correctly you must reassemble these flat lists into the nested control structure by `GroupingIdentifier`.

```
WFWorkflowActions (flat array)            reconstructed logic
────────────────────────────────         ───────────────────
0  is.workflow.actions.conditional        if  <cond>
     WFControlFlowMode = 0                 │
     GroupingIdentifier = G1              │
1  is.workflow.actions.deletephotos       │   Delete Photos
2  is.workflow.actions.conditional        else
     WFControlFlowMode = 1                 │
     GroupingIdentifier = G1              │
3  is.workflow.actions.notification        │   Show Notification
4  is.workflow.actions.conditional        endif
     WFControlFlowMode = 2
     GroupingIdentifier = G1
```

### Shortcuts as evidence — and as anti-forensics

Two investigative framings, both important:

**As evidence of intent and behavior.** A user's shortcut/automation set is a curated description of what they wanted the phone to do *automatically*. "When I arrive at <coords> → set Focus, open <app>" geolocates a routine. "When NFC tag <UID> is scanned → unlock <app>" proves a physical token exists and what it gates. A `Get Contents of URL` action pointed at a webhook documents an exfil/notify channel and often a hard-coded endpoint. Run-count/last-run metadata in `ZSHORTCUT` (corroborated against `siriactionsd` unified-log entries and Biome streams) shows whether a given workflow was *actually used* and when.

**As an anti-forensic instrument.** Because automations can be **hands-free** (Run Immediately + Ask-Before-Running OFF) and triggered by observable examiner actions, a suspect can wire a tripwire: *on* a trigger like "App **Photos**/`Settings` opened", "Wi-Fi joins <lab SSID>", "**charger connected**" (you just plugged in to acquire), or "Focus changes", run actions that **delete photos/files/notes, clear the clipboard, send a message, or call a webhook to alert them.** What Shortcuts *cannot* do is bound the threat: there is **no Shortcuts action that factory-erases the device** or wipes another app's protected container wholesale — the blast radius is the data those actions can reach (Photos, Files in granted scopes, Notes, Reminders, the contributing apps' `AppEntity`s) plus any network notification. That's still enough to destroy case data and to burn your covertness.

### Execution evidence: where a shortcut run leaves traces

Whether a workflow *ran* (and when, and how often) is corroborated outside the Shortcuts store — useful both to prove use and to detect an automation that fired during your exam:

- **`Shortcuts.sqlite`** — the **`ZSHORTCUTRUNEVENT`** table is the per-execution record (`ZDATE`, `ZOUTCOME`, `ZSOURCE`, a `ZTRIGGER` FK to the trigger that fired it), and `ZSHORTCUT`'s `ZLASTRUNEVENTDATE` / `ZRUNEVENTSCOUNT` are denormalized rollups of it (column names version-dependent; confirm via `.schema`). This is the *claimed* history, editable by anyone who can write the store.
- **Unified log** — `siriactionsd` (and the Shortcuts/Apple-Intelligence subsystems) log run lifecycle and action hand-offs. On a reproducible macOS host, `log stream --predicate 'process == "siriactionsd"' --info`; on an iOS `sysdiagnose`/log capture, filter the same process. This is harder to forge than the store metadata. See [[unified-logs-sysdiagnose-crash-network]].
- **Biome / SEGB streams** (iOS 17+) and legacy **knowledgeC** — the pattern-of-life stack records app/intent activity that shortcut runs touch; cross-reference against the store's last-run claims. See [[biome-and-segb-streams]] and [[knowledgec-db-deep-dive]].
- **Downstream side effects** — a `downloadurl` step shows in the app's network artifacts; a `deletephotos` step shows as deletions in the Photos store and its trash; a `sendmessage` step shows in `sms.db`. Triangulate the workflow's *declared* actions against the stores they would have touched.

> 🔬 **Forensics note:** Discrepancies are the tell. If `ZSHORTCUT` says a destructive automation "never ran" but `siriactionsd` log entries or Biome streams show execution at the moment a charger was connected, you have both **evidence the tripwire fired** and **evidence the store metadata was tampered with**. Conversely, an automation with a real trigger and a high run count but no corroborating side effects may be inert or staged. Never trust the Shortcuts store's own run history in isolation.

> ⚠️ **ADVANCED — handle before you explore:** Treat configured automations as live ordnance until proven inert. The defensive sequence: acquire first (you want the workflows *and* their trigger config captured), and before any hands-on examination put the device in a state that starves the triggers — **Airplane mode / Faraday** (kills Wi-Fi, Bluetooth, cellular, arrival, and webhook-exfil triggers), avoid charger plug/unplug if a charger trigger exists, and disable automations only via an authorized, documented procedure. Never *run* a downloaded/unknown shortcut to "see what it does" on an evidence device or your own analysis Mac — it executes with real reach. Inspect it statically (below) instead.

## Hands-on

There is no on-device shell, so everything is Mac-side: the macOS Shortcuts store (the faithful schema twin), the `shortcuts` CLI, `plutil`/`aea` on exported `.shortcut` files, and `sqlite3` on a copy.

**1. Enumerate the macOS Shortcuts store (identical WorkflowKit schema to iOS):**

```bash
# COPY first — even a SELECT write-locks SQLite and spawns -wal/-shm.
cp ~/Library/Shortcuts/Shortcuts.sqlite /tmp/sc.sqlite

# Discover the real columns — Core Data renames across model versions.
sqlite3 /tmp/sc.sqlite '.schema ZSHORTCUT'

# Names + dates (Mac Absolute Time → add 978307200 for local time).
sqlite3 -header -column /tmp/sc.sqlite "
SELECT Z_PK,
       ZNAME,
       datetime(ZCREATIONDATE     + 978307200,'unixepoch','localtime') AS created,
       datetime(ZMODIFICATIONDATE + 978307200,'unixepoch','localtime') AS modified
FROM ZSHORTCUT ORDER BY ZMODIFICATIONDATE DESC;"
# (Column names vary by version — map them from the .schema output first.)
```

**2. Dump a shortcut's action graph straight from the store (no export, no signature):**

```bash
# The action array is a binary-plist blob in the ZSHORTCUTACTIONS.ZDATA column
# (confirm the column from .schema — it is ZDATA on macOS 26; may differ by version).
sqlite3 /tmp/sc.sqlite \
  "SELECT writefile('/tmp/actions.bplist', ZDATA) FROM ZSHORTCUTACTIONS WHERE Z_PK=1;"
plutil -p /tmp/actions.bplist | head -60      # human-readable action list

# Pull just the action identifiers (the program's opcodes):
plutil -convert xml1 -o - /tmp/actions.bplist \
  | grep -A1 WFWorkflowActionIdentifier | grep '<string>'
```

**3. Inspect an exported `.shortcut` (the two eras):**

```bash
file MyShortcut.shortcut
# iOS15+ signed → "Apple Encrypted Archive" (AEA, profile 0: signed, NOT encrypted)
# pre-iOS15    → "Apple binary property list"

# Pre-iOS15 (or any unsigned payload): read directly.
plutil -p MyShortcut.shortcut

# iOS15+ signed AEA → peel the wrapper, then read the inner Apple Archive.
#   profile 0 carries no decryption key; you extract, you don't decrypt.
aea decrypt -i MyShortcut.shortcut -o /tmp/inner.aar    # verify+unwrap (flags vary by toolset)
aa extract -i /tmp/inner.aar -d /tmp/sc_payload/        # → WFWorkflow plist inside
plutil -p /tmp/sc_payload/*                              # confirm exact filenames per version
```

**4. The macOS `shortcuts` CLI (front-end automation, not a parser):**

```bash
shortcuts list                       # names of all shortcuts (no GUI launch)
shortcuts view "My Shortcut"         # opens it in the editor (launches the GUI)
shortcuts sign --mode anyone -i in.shortcut -o out.shortcut   # produce a signed AEA (modes: anyone | people-who-know-me)
# 'run' executes a shortcut for real — NOT for evidence shortcuts.
```

**5. Watch the runner execute (unified log, on macOS where you can reproduce):**

```bash
log stream --predicate 'process == "siriactionsd"' --info
# Trigger a shortcut in the GUI; observe the action-by-action hand-off entries.
```

**6. Enumerate an app's App-Intents surface from its bundle (RE / triage):**

```bash
# The compiler embeds a declarative manifest of every exposed intent/entity/shortcut.
# Bundle path differs: iOS flat bundle → MyApp.app/Metadata.appintents/ ;
#                      macOS .app     → MyApp.app/Contents/Resources/Metadata.appintents/
ls "MyApp.app/Contents/Resources/Metadata.appintents/"   # extract.actionsdata (JSON) + version.json
plutil -p "MyApp.app/Contents/Resources/Metadata.appintents/extract.actionsdata" 2>/dev/null | head -40
# This lists the app's scriptable surface WITHOUT running anything.
```

**7. Automated parsing of a full extraction (iLEAPP):** for a logical/full-file-system extraction, point **iLEAPP** at the image — its Shortcuts/automation parsers enumerate the workflows, identifiers, and (where present) trigger/automation metadata into the HTML/SQLite report, so you triage in minutes instead of hand-dumping blobs:

```bash
python3 ileapp.py -t fs -i /path/to/extraction/ -o /tmp/ileapp_out/
# Open the report; jump to the Shortcuts / automation section.
# Still pull the raw ZSHORTCUTACTIONS blob yourself for anything that matters in court.
```

## 🧪 Labs

> All labs are device-free. The macOS Shortcuts store and `shortcuts` CLI run the **identical WorkflowKit engine** to iOS, so they faithfully teach the *schema, file format, and action model*. They do **not** reproduce the iOS-only pieces: macOS has **no personal-automation triggers** (NFC/arrival/Focus/CarPlay/App-opened), no `siriactionsd` trigger evaluation against device sensors, and a different CloudKit-sync state. For those, use a public sample iOS image / read-only walkthrough as noted per lab. The iOS **Simulator does not ship Shortcuts.app at all**, so it is *not* a substrate here.

### Lab 1 — Dissect the WFWorkflow file format from your own Mac (substrate: macOS Shortcuts live store; fidelity: schema/format identical to iOS, no triggers)

1. In macOS Shortcuts, build a throwaway shortcut with an `if`/`else` and a `Repeat`, e.g. *If <text> contains "x" → Show Notification, else → Get Contents of URL → Repeat 2 times*.
2. `cp ~/Library/Shortcuts/Shortcuts.sqlite /tmp/sc.sqlite`, then `.schema ZSHORTCUT` and `.schema ZSHORTCUTACTIONS` — write down the real date columns and the blob column.
3. `writefile` the action blob, `plutil -p` it, and **reconstruct the control flow by hand**: group the `is.workflow.actions.conditional` / `…repeat.*` actions by their `GroupingIdentifier` and read off `WFControlFlowMode` (0/1/2). Confirm your nested logic matches the GUI.
4. Find the per-action `UUID`s and trace how the `Get Contents of URL` output is referenced as a variable token by a later action's parameters.

### Lab 2 — Peel a signed `.shortcut` export (substrate: a real signed AEA export; fidelity: exact production format)

1. From macOS Shortcuts, **File → Export** (or `shortcuts sign`) to produce a `.shortcut`. Run `file` on it — confirm it's an Apple Encrypted Archive.
2. Identify it as **profile 0** (signed, not encrypted): the payload is recoverable without a key. Unwrap with `aea`/`aa` (flags vary — read `aea --help`) until you reach the inner `WFWorkflow` plist.
3. `plutil -p` the inner plist. Find `WFWorkflowClientVersion` and `WFWorkflowMinimumClientVersionString` — note how the export fingerprints the authoring Shortcuts build.
4. Compare the inner `WFWorkflowActions` to the `ZSHORTCUTACTIONS.ZDATA` blob you dumped in Lab 1 — confirm the action arrays are identical (the export bundles into one `WFWorkflow` dict what the Core Data store splits across `ZSHORTCUTACTIONS` + the `ZSHORTCUT` columns).

### Lab 3 — Enumerate an app's scriptable surface without running it (substrate: any installed `.app` / extracted `.ipa`; fidelity: static, full)

1. Pick a Mac `.app` that adopts App Intents (many Apple and third-party apps do) and `ls` its `Contents/Resources/Metadata.appintents/` directory (on an iOS flat bundle it sits at the `.app` root instead). You'll find `extract.actionsdata` (JSON) + `version.json`.
2. `plutil -p` the actions-data blob and enumerate the declared `AppIntent`s, `AppEntity`s, and `AppShortcut` phrases.
3. Write one sentence per intent describing *what an automation built on this app could do* — i.e. the app's automation attack surface — and note which would require which entitlements/data grants (tie back to [[the-app-bundle-and-ipa-structure]]).

### Lab 4 — Model an anti-forensic automation (substrate: read-only walkthrough + macOS analysis; fidelity: trigger semantics are iOS-only)

> ⚠️ **ADVANCED:** Design and analyze only. Do **not** wire a destructive automation to a live trigger on a device you care about, and never run an unknown shortcut on an evidence device or your analysis Mac.

1. On paper, design a dead-man's switch: trigger = "App **Settings** opens" (or "Wi-Fi joins <lab SSID>"), run-mode = *Run Immediately, Ask-Before-Running OFF*, actions = `Delete Photos` → `Clear Clipboard` → `Get Contents of URL` (webhook alert).
2. Write the `WFWorkflowActions` array for it by hand (you know the identifiers and the control-flow encoding from Lab 1): `is.workflow.actions.deletephotos`, `is.workflow.actions.setclipboard`, `is.workflow.actions.downloadurl`.
3. Now flip to examiner mode: list every *defensive* step that neutralizes each trigger before hands-on (Faraday/Airplane mode, charger-handling, acquire-then-disable), and explain why **acquisition must precede exploration** here. Cross-check against [[acquisition-sop-and-chain-of-custody]].

### Lab 5 — Resolve magic variables and an LLM-egress step (substrate: macOS Shortcuts live store; fidelity: schema/format identical; `Use Model` requires Apple Intelligence enabled)

1. Build a shortcut: `Get Contents of URL` (point it at a harmless test URL) → `Use Model` (On-Device) with a prompt that references the previous step's output as a **magic variable** → `Show Result`.
2. Dump the action blob (`writefile` from `ZSHORTCUTACTIONS`, as in Lab 1) and `plutil -convert xml1`. Locate the `Use Model` action's parameters and read the **prompt literal**. Then find the **`UUID`/`WFTokenAttachment`** in that prompt string that points back to the `downloadurl` action's output — manually resolve the magic-variable reference.
3. Record the `Use Model` **backend selector** (On-Device vs PCC vs ChatGPT) from the parameters. Write the one-line chain-of-custody statement you'd file describing where this shortcut's data goes.
4. (If you also have a sample iOS image) compare: does the iOS store hold the same `WFWorkflowActions` structure for an equivalent shortcut? Confirm the engine is the same; note what's *missing* on macOS (trigger linkage).

## Pitfalls & gotchas

- **Don't expect a shell.** Reflexively reaching for `Run Shell Script`/`osascript` on iOS is the #1 macOS-carryover error — those actions don't exist. Every capability is an exposed action; if no app exposed it, an iOS shortcut cannot do it.
- **The Simulator has no Shortcuts.app.** It is not a substrate for this subsystem. Use macOS Shortcuts (same engine) for schema/format and a sample iOS image for triggers/run-history.
- **macOS has no personal-automation triggers.** The macOS store will teach you the workflow format perfectly but will be *empty* of NFC/arrival/Focus/App-opened automations — don't conclude "the user had no automations" from a clean macOS-style store; on iOS, look for the trigger linkage in `ZSHORTCUT` and the automation entries specifically.
- **Wrong epoch = 31-year error.** Core Data `Z…DATE` columns are Mac Absolute Time (2001 epoch, add 978307200), *not* Unix and *not* the nanosecond variant some other Apple stores use. Convert deliberately. See [[the-ios-timestamp-zoo]].
- **Don't hard-code the iOS path or column names.** The on-device container subpath, the store filename, and the Core Data column names all drift across iOS versions. Anchor on the *macOS* path for the schema and **verify the iOS specifics against your acquired image** every time.
- **"Signed" ≠ "encrypted".** A signed `.shortcut` (AEA profile 0) is fully readable once unwrapped — the signature is integrity, not confidentiality. Don't report a shared shortcut as "encrypted/unrecoverable"; extract it.
- **You don't need the export to read the logic.** `ZSHORTCUTACTIONS` already holds the action array as a plist blob; the signature on `.shortcut` files is irrelevant to on-device recovery.
- **CloudKit + ADP changes scope.** Shortcuts sync via CloudKit; with Advanced Data Protection the cloud copy is E2EE and not server-recoverable, and cloud acquisition is separately authorized from device seizure.
- **Tripwires fire on *your* actions.** Charger-connect, app-open, and Wi-Fi-join automations can trigger during acquisition. Faraday/Airplane mode first; acquire before you explore.
- **NFC triggers match the tag UID, not its contents.** Don't waste time decoding what's "written" on a registered tag — only its unique identifier is the key the automation matches on.
- **`Run script over SSH` runs on a *remote* host.** `is.workflow.actions.runsshscript` is not a local shell — it's an SSH client. It does not contradict "no shell on iOS"; it proves the phone reached *out* to a server, and the host/credentials are in the parameters.
- **Don't trust the store's run history.** `ZSHORTCUT` run/last-run fields are writable; corroborate execution against `siriactionsd` logs, Biome/SEGB, and downstream store side effects before asserting a workflow did or didn't run.
- **`Use Model` routing is a privacy fork.** The same action can keep data on-device or ship it to ChatGPT — never report "the shortcut used AI" without naming the backend; the egress destination changes the legal and privacy analysis.
- **Magic-variable references look like noise in raw text.** Parameter strings are attributed structures; a value that reads as plain text in `plutil -p` may actually embed `UUID`-keyed token attachments. Resolve them before concluding a parameter is a static literal.

## Key takeaways

- iOS automation is **one brokered action graph (Shortcuts)** with **no shell/AppleScript/JXA underneath** — the macOS escape hatches are gone; every capability must be *declaratively exposed* by an entitled app or the OS.
- The whole stack is **WorkflowKit.framework**, shared across iOS/iPadOS/macOS, executed headless by **`siriactionsd`**; the `is.workflow.*` namespace is a fossil of the acquired *Workflow* app.
- **App Intents** (`AppIntent`/`AppEntity`/`AppShortcut`/`AppShortcutsProvider`) is how apps contribute actions in 2026 — one Swift declaration lights up Shortcuts/Siri/Spotlight/Action button/widgets; `perform()` runs **in the app's own sandbox**, and the bundle ships a static **`Metadata.appintents`** manifest you can enumerate.
- Workflows persist in a **Core Data SQLite store** (`~/Library/Shortcuts/Shortcuts.sqlite` on macOS; the WorkflowKit app-group container on iOS), with the action graph as a **binary-plist blob in `ZSHORTCUTACTIONS`** — recoverable on-device with **no signature to defeat**.
- The `.shortcut` export is an **AEA (profile 0: signed, not encrypted)** wrapping an LZFSE Apple Archive of the same `WFWorkflow` plist; **signed ≠ secret** — unwrap and read it.
- In the `WFWorkflow` plist, **control flow is encoded in parameters**: blocks share a `GroupingIdentifier` and are sequenced by `WFControlFlowMode` (0 start / 1 middle / 2 end); data flows via per-action `UUID` variable tokens.
- **Automations + triggers are behavior-as-evidence** (geofences, SSIDs, NFC UIDs, app-open hooks) and, when hands-free, **anti-forensic tripwires** — acquire first, Faraday/Airplane before hands-on, never run an unknown shortcut on evidence.
- Shortcuts **sync via CloudKit**; **ADP** makes that cloud copy E2EE/unrecoverable, and cloud acquisition is a separately authorized scope from the device.

## Terms introduced

| Term | Definition |
|---|---|
| WorkflowKit.framework | Apple's private framework backing Shortcuts on iOS/iPadOS/macOS — model, runner, action catalog (`WFActions.plist`), import/signing. |
| `siriactionsd` | Background daemon that runs/syncs shortcuts and evaluates automation triggers; primary shortcut-execution evidence source. |
| `siriknowledged` | Siri/Suggestions knowledge daemon feeding shortcut & action suggestions. |
| Shortcut vs. Automation | A *shortcut* is a user-run workflow; an *automation* is a shortcut bound to a trigger (personal/device or Home/HomeKit). |
| Personal automation trigger | A device event that fires an automation: time, alarm, arrive/leave, NFC, Wi-Fi/Bluetooth, CarPlay, Focus, app open/close, battery/charger, etc. |
| Run Immediately / Ask Before Running | The hands-free flag on an automation; OFF "Ask Before Running" + "Run Immediately" = silent execution (tripwire-capable). |
| `is.workflow.actions.*` | Reverse-DNS identifier namespace for built-in Shortcuts actions (legacy *Workflow* prefix). |
| `WFActions.plist` | Authoritative action catalog inside WorkflowKit mapping action IDs → parameter schema/types/entitlements. |
| App Intents | Modern framework (iOS 16+) for apps to declaratively expose actions/data system-wide; successor to SiriKit `INIntent` donations. |
| `AppIntent` / `AppEntity` / `AppShortcut` / `AppShortcutsProvider` | The App Intents types: an action with `perform()`, a referencable noun, a zero-setup system-surfaced binding, and the app's manifest of bindings. |
| `Metadata.appintents` | Compiler-emitted bundle inside a `.app` declaring its intents/entities/app-shortcuts — statically enumerable without running the app. |
| `Shortcuts.sqlite` | The WorkflowKit Core Data store; key tables `ZSHORTCUT` (metadata), `ZSHORTCUTACTIONS` (`ZDATA` binary-plist action graph), `ZTRIGGER` (automation trigger config + the Ask-Before-Running flag), and `ZSHORTCUTRUNEVENT` (per-execution history). |
| `WFWorkflow` dictionary | The plist shape of a shortcut: `WFWorkflowActions`, client/min-version, import questions, icon, input classes, types. |
| `WFWorkflowActionIdentifier` / `WFWorkflowActionParameters` | Per-action identifier + parameter dict; the two keys of each element of `WFWorkflowActions`. |
| `GroupingIdentifier` / `WFControlFlowMode` | How if/repeat/menu blocks are encoded flat: shared grouping UUID + mode 0 (start) / 1 (middle) / 2 (end). |
| AEA (Apple Encrypted Archive) | The iOS-15+ `.shortcut` container; **profile 0 = signed, not encrypted** — LZFSE Apple Archive payload, cert chain in auth-data. |
| Mac Absolute Time | Apple Cocoa Core Data epoch: seconds since 2001-01-01 UTC; add 978307200 to convert to Unix epoch. |
| Magic Variable | An implicit token for an action's output, referenced downstream via a `UUID`-keyed `WFTokenAttachment`/`WFVariable` in another action's parameters. |
| Content graph / type coercion | The runner's typed content-item system that auto-converts values between types (e.g. image→filename) so outputs can feed arbitrary inputs. |
| `Use Model` action | iOS/macOS 26 Shortcuts action prompting an LLM — on-device foundation model, Private Cloud Compute, or ChatGPT; prompt text is a literal parameter. |
| Assistant schema (`@AssistantIntent`/`@AssistantEntity`) | App Intents conformances to Apple-defined structures that make app actions invocable by the Apple Intelligence/Siri reasoning model. |
| Private Cloud Compute (PCC) | Apple's stateless, attested server-side Apple-Intelligence backend; one of the `Use Model` routing targets. |

## Further reading

- Apple — *Secure features in the Shortcuts app* (support.apple.com/guide/security/secec043bdae) and *Setting triggers in Shortcuts* (support.apple.com/guide/shortcuts).
- Apple Developer — *App Intents* documentation (developer.apple.com/documentation/appintents); WWDC22 "Dive into App Intents" (10032); WWDC25 "Get to know App Intents" (244); WWDC21 "Meet Shortcuts for macOS" (10232).
- Apple Developer — *FoundationModels* framework + *Apple Intelligence* (developer.apple.com/apple-intelligence); Apple — *Use Apple Intelligence in Shortcuts* (support.apple.com/guide/iphone/iph78c41eaf8). MacStories — "The (Great) 'Use Model' Action in Shortcuts" (macstories.net) for the on-device/PCC/ChatGPT routing breakdown.
- Apple — *Run shortcuts from the command line* (the `shortcuts` CLI: `list`/`run`/`view`/`sign`); `ss64.com/mac/shortcuts.html`.
- TheAppleWiki — *Dev:WorkflowKit.framework* and *Apple Encrypted Archive* (theapplewiki.com / theiphonewiki.com) — AEA profiles, auth-data layout, LZFSE/Apple Archive structure.
- Shortcuts file-format references — `zachary7829.github.io/blog/shortcuts/fileformat`; `github.com/sebj/iOS-Shortcuts-Reference`; 0xilis, *Reversing signed shortcuts* + `github.com/0xilis/shortcut-sign`; `gist.github.com/0xdevalias/27d9aea9529be7b6ce59055332a94477`.
- Forensics — Alexis Brignoni / iLEAPP (`github.com/abrignoni/iLEAPP`) for Shortcuts/automation parsing; the RealityNet *iOS-Forensics-References* index; mac4n6 (Sarah Edwards) for the Biome/knowledge correlation of shortcut runs.
- `man siriactionsd`, `man plutil`, `man sqlite3`, `man aea` / `man aa` — exact flag semantics on your target macOS version.

---
*Related lessons: [[app-sandbox-and-filesystem-layout]] | [[biome-and-segb-streams]] | [[the-ios-timestamp-zoo]] | [[icloud-acquisition-and-advanced-data-protection]] | [[the-app-bundle-and-ipa-structure]] | [[static-analysis-class-dump-and-disassemblers]] | [[acquisition-sop-and-chain-of-custody]]*
