---
title: "Trackpad, keyboard & Apple Pencil"
part: "05 — iPadOS as a Computer"
lesson: 03
est_time: "40 min read + 15 min labs"
prerequisites: [how-ipados-diverges-from-ios]
tags: [ios, ipados, trackpad, keyboard, apple-pencil, pencilkit]
last_reviewed: 2026-06-26
---

# Trackpad, keyboard & Apple Pencil

> **In one sentence:** The three input planes that promote an iPad to a workstation — a system-drawn *adaptive* pointer, a full hardware-keyboard responder chain with a ⌘-hold discoverability HUD, and Apple Pencil ink captured by **PencilKit** as serialized `PKDrawing` vector data — are each both an engineering surface *and* a forensic one, because handwriting is user-authored evidence, the keyboard's learned lexicon persists typed text regardless of input source, and Pencil-driven workflows mint screenshot/markup artifacts you must know how to read.

## Why this matters

You finished `macos-mastery` fluent in the Mac's input model: a Force Touch trackpad, a hardware keyboard dispatched up the `NSResponder` chain, `NSMenu` validation, the arrow cursor that *never changes shape*. An iPad with a Magic Keyboard *looks* like that laptop, but underneath it is a different machine: the pointer is a **system-composited layer that morphs to the control beneath it** (the Mac's cursor is a dumb sprite), the menu/shortcut system is `UIResponder`-based rather than `NSResponder`-based, and there is an entire input modality the Mac does not have at all — **Apple Pencil**, whose strokes are captured with per-point pressure, tilt, and *timing* and stored as opaque vector blobs.

For a **builder**, this is the surface that decides whether your "universal" app feels like a real iPad citizen or a stretched phone app: pointer interactions, key commands that populate the menu bar and HUD, and PencilKit if you touch ink at all.

For a **forensicator**, every one of these planes leaves residue. Apple Pencil handwriting is *content that exists only because there is a Pencil* — a `PKDrawing` blob in a Notes row or a GoodNotes container is as much a document as a typed memo, and it carries **per-stroke creation timestamps** that yield a micro-timeline of when the page was actually written. The keyboard's predictive engine writes a **learned-lexicon** of typed words to disk that survives deletion and behaves like a partial keylogger — and it does so whether the user typed on glass or on a Magic Keyboard. And a Pencil-heavy iPad is a screenshot-and-markup factory, where each annotation is a non-destructive Photos adjustment you can peel back to the pristine original. This lesson maps all three planes mechanism-first, then tells you exactly where each lands on disk.

## Concepts

### Three input planes, one event pipeline

iPadOS routes every input source — touch, indirect pointer (trackpad/mouse), hardware keyboard, and Apple Pencil — into the **same UIKit event and responder machinery** you already know from iOS. Touches arrive as `UITouch`; the system distinguishes a finger from a Pencil by `UITouch.type` (`.direct` vs `.pencil`), and an indirect-pointer click by `.indirectPointer`. From there, hit-testing and the `UIResponder` chain are identical regardless of which physical thing generated the event. What differs is the *metadata* each source carries and the *system services* layered above the app:

```
 Finger ──┐
 Pencil ──┤                          ┌─ UIPointerInteraction (system-drawn cursor)
 Trackpad ┼─▶ UIKit event pipeline ──┼─ UIKeyCommand / buildMenu(with:) (HUD + menu bar)
 Keyboard ┘     (UITouch / UIPress)  ├─ UIScribbleInteraction (handwriting → text field)
                                     └─ PencilKit (PKCanvasView → PKDrawing data)
```

The system tags each event with its origin so the app can branch on it, and the *richness* of the attached metadata is exactly what makes one source forensically loud and another silent:

| Source | UIKit type / `UITouch.type` | Distinguishing metadata it carries | On-disk residue |
|---|---|---|---|
| Finger | `UITouch` `.direct` | location, phase, `majorRadius` | none directly |
| Trackpad / mouse | `UITouch` `.indirectPointer` + `UIPointerInteraction` | hover, scroll deltas, button mask | none (cursor is ephemeral) |
| Hardware keyboard | `UIPress` / `UIKeyCommand` / `GCKeyboard` | key + modifier chord | **learned lexicon** (`dynamic-text.dat` …) |
| Apple Pencil | `UITouch` `.pencil` → PencilKit | `force`, `azimuth`, `altitude`, roll, hover | **`PKDrawing`** vector blob (with timing) |

The load-bearing idea: the app rarely *draws* the pointer or *renders* the keyboard HUD — the **system** does, compositing above the app, and the app only declares *regions, styles, commands, and intent*. That separation is why these features feel consistent across apps, and it is why some of them (the cursor sprite, the HUD) leave little app-side trace while others (ink, learned text) leave a great deal.

### The adaptive pointer: a system layer, not an emulated finger

Since **iPadOS 13.4**, a connected trackpad or mouse drives a **real cursor**, not a synthetic touch. The default pointer is a translucent circle that **morphs** as it approaches interactive controls — Apple calls this *adaptive precision*: over a button the circle snaps to and becomes the button's shape; over text it becomes an I-beam; over a list it slides between rows. The cursor is rendered by the system in a layer composited *above* the app's content. The app participates through the **pointer-interaction API**:

- **`UIPointerInteraction`** — attach to a view with a `UIPointerInteractionDelegate`. The delegate vends a **`UIPointerStyle`** describing how the pointer should look/behave inside a **`UIPointerRegion`** of the view.
- **`UIPointerStyle`** combines a **pointer *effect*** (how the *content* reacts) with a **pointer *shape*** (what the *cursor* becomes):
  - **Effects:** `.highlight` (content tints/scales subtly, no shadow), `.lift` (content lifts with a drop shadow as the pointer fades), `.hover` (custom scale/tint/shadow, pointer shape unchanged).
  - **Shapes:** `.roundedRect`, `.path` (an arbitrary `UIBezierPath`), or morph-to-control.
- **`UIHoverGestureRecognizer`** — reports the pointer entering/moving/exiting a view *without a click*; this is the same recognizer that surfaces **Apple Pencil hover** (below). Hover did not exist on iOS before the pointer; it is a genuinely new input phase.

SwiftUI exposes the same machinery through `.hoverEffect(_:)` and `.onHover { ... }`.

**Trackpad gestures map onto existing UIKit recognizers, not a new API.** A two-finger trackpad scroll arrives as a `UIScrollView` content offset change; a two-finger pinch arrives through `UIPinchGestureRecognizer`; a two-finger rotate through `UIRotationGestureRecognizer` — all flagged `.indirectPointer` so an app can tune behavior for trackpad vs touch. The *system-level* trackpad gestures (three-finger swipe between apps/Spaces, four-finger pinch to Home, edge-push to reveal the Dock or menu bar) are owned by **SpringBoard** and never reach the app. The "natural"/inertia/scaling tuning lives in **Settings → General → Trackpad** and in Accessibility's **Pointer Control**, persisted as preference-domain plists — so trackpad *configuration* is recoverable even though pointer *motion* is not.

> 🖥️ **macOS contrast:** On the Mac, `NSCursor` is a fixed sprite you push/pop (`NSCursor.iBeam.set()`); the cursor never *becomes* the button. The Mac's analogue to hover is `NSTrackingArea` + `mouseEntered/Exited`. The iPad pointer is closer to a tvOS focus engine than to a Mac cursor: it is *magnetic and adaptive*, snapping to and reshaping around controls. Where AppKit gives you mouse coordinates and you decide everything, UIKit gives the *system* enough declarative information (regions + styles) to drive the cursor for you. Net: the iPad cursor is smarter and less under app control than the Mac's.

> 🔬 **Forensics note:** The pointer itself is ephemeral — there is no "cursor log." Its forensic relevance is indirect: pointer *presence* implies a paired trackpad/mouse (a Magic Keyboard, Magic Trackpad, or Bluetooth mouse), which shows up as a **Bluetooth/USB accessory pairing record** and in the unified log's HID-attach events. If you are reconstructing whether an iPad was being used "like a laptop" at a given time, accessory-pairing artifacts + keyboard-input lexicon growth are the durable signals, not the cursor.

### Hardware keyboard: the responder chain, key commands, the ⌘-hold HUD, and the menu bar

A hardware keyboard turns the iPad into a keyboard-navigable computer through three layered mechanisms:

**1. `UIKeyCommand` on the responder chain.** A responder declares shortcuts by overriding `keyCommands` (or registering `UIKeyCommand` objects) and the system dispatches a matching chord to the first responder that handles it — exactly the first-responder semantics you know. Each command has `input` (e.g. `"S"` or a special key constant), `modifierFlags` (`.command`, `.shift`, `.alternate`, `.control`), an `action` selector, and a **`title`** (the human-readable label). `wantsPriorityOverSystemBehavior` lets an app override a system default. Raw, game-style key events (every keydown/keyup, modifier state) are available separately through **`GCKeyboard`** in the **GameController** framework and through `UIPress`/`pressesBegan(_:with:)`.

**2. The ⌘-hold discoverability HUD.** Holding the **Command** key with a hardware keyboard attached pops a translucent overlay listing every currently-available shortcut — grouped by the menu/command tree. This "keyboard shortcut HUD" is built automatically from the `title`s of the `UIKeyCommand`s reachable on the current responder chain plus the menu system. It is the iPad's *discoverability* surface: an app that declares its commands well gets a free, always-current cheat-sheet.

**3. The command/menu tree (`UIMenuBuilder`).** Since iOS/iPadOS 13, an app builds its command hierarchy by overriding `buildMenu(with:)`, populating **`UIMenuSystem.main`** with `UIMenu`/`UICommand`/`UIKeyCommand` nodes. On iPad this same tree drives (a) the ⌘-hold HUD, (b) the **persistent menu bar** that iPadOS 26 surfaced at the top of every window (revealed by swiping down or pushing the pointer to the top edge — see [[how-ipados-diverges-from-ios]] and [[windowing-multitasking-and-external-display]]), and (c) the real Mac menu bar when the app runs under Mac Catalyst. One declaration, three renderings.

Beyond app shortcuts, the **system** owns a layer of global shortcuts that apps cannot intercept: **Globe key** (the dedicated key on Apple's iPad keyboards) opens a system shortcut sheet and drives input-source switching; ⌘-Space (Spotlight), ⌘-Tab (app switcher), ⌘-H (Home), and the window/tiling shortcuts are handled by SpringBoard, not the foreground app. **Full Keyboard Access** (Accessibility) extends this to *complete* keyboard navigation of every control — a genuine power-user mode, and an accessibility feature repurposed as a productivity tool.

The ownership split is worth holding in your head, because it decides who can intercept what:

| Layer | Owner | Examples | Interceptable by an app? |
|---|---|---|---|
| System / window mgmt | SpringBoard | ⌘-Space, ⌘-Tab, ⌘-H, Globe sheet, tiling | No |
| Menu-bar / app commands | App via `buildMenu(with:)` | ⌘N/⌘S/⌘F, app menus | Yes (own commands) |
| Ad-hoc shortcuts | App via `keyCommands` | view-local chords | Yes (`wantsPriorityOverSystemBehavior` to win conflicts) |
| Raw key events | App via `GCKeyboard`/`UIPress` | games, custom editors | Yes (every key up/down) |

> 🖥️ **macOS contrast:** `buildMenu(with:)` + `UIKeyCommand` is UIKit's port of `NSMenu` + `NSResponder`'s `validateMenuItem(_:)`. On macOS, menu actions travel up the `NSResponder` chain and `validateMenuItem(_:)` enables/disables them; on iPadOS, `UICommand`/`UIAction` travel up the `UIResponder` chain and you validate via `validate(_:)` / `canPerformAction(_:withSender:)`. The ⌘-hold HUD has *no* Mac equivalent — the Mac shows shortcuts inline in the menus instead. The Globe key is the iPad's stand-in for the Mac's `fn`/Globe key behavior.

> 🔬 **Forensics note:** The keyboard's *content* residue is independent of whether the keys were physical or on-screen — the predictive/learning engine logs typed words the same way (see "The forensic surface" below). What a hardware keyboard *adds* to the timeline is its **pairing/attach record**: a Magic Keyboard attaches over the Smart Connector (a HID device, visible in the unified log and IORegistry-style attach events), a Bluetooth keyboard leaves a pairing record. Establishing "a hardware keyboard was attached during this window" can corroborate a burst of typed-text lexicon growth or a long composition session.

### Apple Pencil: the hardware generations and their sensors

"Apple Pencil" is a family, and the generation gates which sensor data your `PKStrokePoint`s can ever contain — which matters both to a builder and to anyone interpreting ink in evidence:

| Model | Pairing / charge | Key sensing | Distinguishing inputs |
|---|---|---|---|
| Apple Pencil (1st gen) | Lightning plug / USB-C adapter | pressure, tilt | — |
| Apple Pencil (2nd gen) | magnetic attach, inductive charge | pressure, tilt | **double-tap** (toggle tool); **hover** (only on the M2 iPad Pro — the M4 Pro pairs with Pencil Pro/USB-C, not the 2nd gen) |
| **Apple Pencil Pro** | magnetic attach, inductive charge | pressure, tilt | **squeeze** (gesture/tool palette), **barrel roll** (gyroscope → roll angle), **haptics**, **hover**, **Find My** |
| Apple Pencil (USB-C) | USB-C cable | tilt (**no pressure**) | hover on supported iPads; no pressure sensitivity and no double-tap |

The forensically interesting ones are the *sensors that reach the stroke data*:

- **Hover** (Apple Pencil 2/Pro/USB-C on hover-capable iPads — M2-and-later iPad Pro and iPad Air, plus the A17 Pro iPad mini) previews the landing point and tool shadow before the tip touches; it surfaces through `UIHoverGestureRecognizer` and a Pencil-specific hover phase.
- **Double-tap** (2nd gen) and **squeeze** (Pro) are *user-configurable* actions set in **Settings → Apple Pencil**; by default they switch tools or open the tool picker. PencilKit/`UIPencilInteraction` reports them; the chosen action is a user preference (a plist), not stroke data.
- **Barrel roll** (Pro) uses a gyroscope so rotating the barrel rotates shaped/flat brush tools — exposed per-point as a roll angle (confirm the exact `PKStrokePoint` property name against your PencilKit version before quoting it in a report).
- **Find My** (Pro) registers the Pencil as a **Find My accessory** — a Bluetooth offline-finding beacon (see [[find-my-and-the-ble-mesh]]). That makes the Pencil itself a *trackable item* with a registry entry, not just a stylus.

> 🔬 **Forensics note:** A paired Pencil is a Bluetooth accessory with a pairing record on the device (Bluetooth device plists / accessory registry — confirm the exact path on your target image; the Bluetooth store has moved across iOS versions). Two payoffs: (1) the presence of a paired Pencil *corroborates* that handwriting/markup evidence on the device is plausibly first-party rather than imported; (2) an **Apple Pencil Pro** registered with **Find My** is a location-bearing accessory — its Find My registration is a small additional location surface tied to the device's iCloud account.

### PencilKit: how ink becomes data

When the user draws, **PencilKit** captures it. The object graph is small and worth memorizing because it *is* the evidence schema:

```
PKDrawing
 └─ strokes: [PKStroke]
      ├─ ink:  PKInk                 ── inkType (.pen/.pencil/.marker/.monoline/
      │                                  .fountainPen/.watercolor/.crayon/.reed* ...),
      │                                  color (UIColor)
      ├─ transform: CGAffineTransform
      ├─ mask / maskedPathRanges / randomSeed
      └─ path: PKStrokePath
           ├─ creationDate: Date     ←─ wall-clock time the stroke was drawn
           └─ control points: [PKStrokePoint]
                ├─ location  (CGPoint)
                ├─ timeOffset (TimeInterval, relative to creationDate)
                ├─ force / opacity / size
                └─ azimuth / altitude   (Pencil tilt; + roll on Pencil Pro*)
```
*`reed` pen added to the tool palette in **iPadOS 26**; per-point roll exposed for Apple Pencil Pro — verify exact API names per PencilKit version.*

The container, **`PKCanvasView`**, hosts a **`PKDrawing`** and a **`PKToolPicker`** (the floating palette). The drawing serializes through two interchangeable mechanisms:

- **`drawing.dataRepresentation() -> Data`** and **`PKDrawing(data:)`** — the canonical on-disk form.
- `PKDrawing` conforms to **`NSSecureCoding`** *and* **`Codable`**, so it can be archived into Core Data / SwiftData / a plist / JSON like any value.

Critically for parsing: **`dataRepresentation()` is an opaque, *versioned*, internally *compressed* serialized blob — not plain text and not a documented byte layout.** Historically the payload is a zlib/gzip-compressed, Protocol-Buffers-like encoding of the stroke array, fronted by a **content-version** field — `PKContentVersion`, an enum *surfaced in iOS/iPadOS 17* that tags a drawing by the ink-feature era it requires: **`.version1`** = the original iOS 13 ink set, **`.version2`** = the iOS 17 expanded tools (monoline / fountain-pen / watercolor / crayon), **`.version3`** = Apple Pencil Pro barrel-roll (iOS 17.4), **`.version4`** = the iPadOS 26 additions (e.g. the reed pen) — so newer ink types degrade gracefully on older OSes (a drawing advertises its floor via `PKDrawing.requiredContentVersion`, iOS 17+). The exact serialized schema is **not** publicly documented and has drifted across releases — so parse defensively: detect the compression, inflate, then decode the inner structure heuristically, and **confirm field meanings against the PencilKit version that produced the blob** rather than asserting offsets.

The whole round-trip — and the per-stroke timing you will mine forensically — is small enough to hold in one snippet:

```swift
// Persist ink:
let data = canvas.drawing.dataRepresentation()        // opaque, versioned, compressed
try data.write(to: url)                                 // or archive into Core Data / SwiftData

// Reload + read the micro-timeline:
let drawing = try PKDrawing(data: Data(contentsOf: url))
for stroke in drawing.strokes {
    let started = stroke.path.creationDate              // wall-clock time of this stroke
    let span    = stroke.path.last?.timeOffset ?? 0     // seconds from start to last point
    print(stroke.ink.inkType, started, "+\(span)s", stroke.path.count, "points")
}
let png = drawing.image(from: drawing.bounds, scale: 2).pngData()  // DERIVED exhibit
```

Where the blob *lands* depends on the app:
- **Notes** embeds the `PKDrawing` inline in the note's body — the gzipped-protobuf rich-text payload in `ZICNOTEDATA.ZDATA` inside `NoteStore.sqlite` (the lineage you dissect in [[mail-notes-calendar-reminders]]); rendered previews live under the Notes group container's media directories.
- **Freeform**, **Markup** (screenshot/PDF annotation), and many first-party canvases use PencilKit, so the same `PKDrawing` form recurs.
- **Third-party note apps** (GoodNotes, Notability) store ink in their *own* containers — some wrap `PKDrawing`, some roll a proprietary stroke format. Always name the app before asserting a format; see [[third-party-app-methodology]].

> 🖥️ **macOS contrast:** The Mac has no native pen-ink framework with a stored vector format like this — the closest analogue is `PDFKit` annotations or an app's own drawing model. PencilKit is genuinely iPad-native (it exists on macOS only via Catalyst/Sidecar). So `PKDrawing` blobs are an **iPad-class artifact with no iPhone *and* no native-Mac equivalent** — when you find one, you are almost certainly looking at iPad-authored content.

> 🔬 **Forensics note:** The gem in this schema is **`PKStrokePath.creationDate` + per-point `timeOffset`**. Each stroke carries a wall-clock creation time, and each control point an offset within the stroke — so a single handwritten note yields a **micro-timeline**: the order strokes were laid down and the seconds between them. That can establish authored-here-and-now vs pasted, distinguish one sitting from many, and (against the note row's own `ZCREATIONDATE`/`ZMODIFICATIONDATE`) flag a later edit when the newest stroke post-dates or pre-dates the note metadata. The legible *content*, though, is not in the blob as text — you must **render** the `PKDrawing` (PencilKit can rasterize it to an image) or run handwriting recognition over it.

> ⚖️ **Authorization:** A rendered handwriting image is a **derived** exhibit, not the primary evidence. The primary evidence is the raw `PKDrawing` bytes (and the row that held them); the PNG you produce depends on the PencilKit *renderer version*, antialiasing, and scale. Preserve and hash the raw blob, record the exact tool/OS version used to rasterize, and treat the image as an interpretation — the same discipline you'd apply to transcoding any proprietary container for court.

> 🔬 **Forensics note:** The stroke micro-timeline becomes far stronger when **correlated with the device's pattern-of-life stores**. The `PKStrokePath.creationDate` window (say, a note written 14:02–14:09) should line up with an **app-in-focus interval for the note app** in `knowledgeC`/Biome (`/app/inFocus`) and with display-on/unlock state — see [[notifications-keyboard-and-misc-stores]] and [[the-ios-timestamp-zoo]]. A drawing whose stroke times fall *outside* any recorded focus/unlock window for that app is a contradiction worth chasing (clock manipulation, sync from another device, or imported content). Treat the ink timeline as one track in a multi-source timeline, not in isolation.

### Scribble and on-device handwriting recognition

**Scribble** converts handwriting in *any text field* to typed text. A developer adopts **`UIScribbleInteraction`** (or `UIIndirectScribbleInteraction` for non-text views that should accept handwriting), whose delegate can disable Scribble on a view, delay first-responder until handwriting pauses, or observe when handwriting begins/ends. The conversion runs **entirely on-device** — the ink is recognized locally and the *resulting text* is committed to the field exactly as if typed.

That last point is the forensic crux: **Scribble output lands in the normal text store** (the field's text, the note's text column, the message draft) — it is indistinguishable downstream from keyboard input, and it *also* feeds the same learned-lexicon described next. Whether the *raw ink* is retained depends on the app: a plain text field keeps only the recognized text; a notes canvas may keep both.

Looking forward (announced at **WWDC 2026**, session *"Read between the strokes with PencilKit,"* for the **iOS/iPadOS/macOS/visionOS 27** cycle, *not yet shipped* as of this writing — current is 26.5): PencilKit gains a public **`PKStrokeRecognizer`** handwriting-recognition API — an on-device Swift `actor` (recognize a whole drawing or a subset of `strokeID`s), ~29 languages via a configurable `preferredLanguages` set, plus `PKStrokePath` B-spline↔Bézier conversion so any Bézier-stored canvas can feed the recognizer. Mechanism for the forensic reader: handwriting-to-text recognition is becoming a *first-class, scriptable* capability — relevant because the same on-device recognizer that converts ink for the user can, in principle, be the thing that produces a recognized-text rendering of evidentiary ink. Treat this as a *forward* note and verify availability at author time.

> 🔬 **Forensics note:** Do not assume opaque-looking ink means unreadable content. If Scribble (or an app's recognizer) ran, the **recognized text may already be sitting in a normal text column** even when the `PKDrawing` blob looks impenetrable. Always check the text store first — it is the cheapest path to legible content, and it ties the handwriting into the keyboard lexicon and any draft/autosave artifacts.

### Text-interaction gestures (briefly)

Selection and editing on iPad ride **`UITextInteraction`** and a set of system gestures: tap to place the caret, the magnifier loupe (touch-and-hold), double-tap to select a word, triple-tap a sentence/paragraph, drag the selection handles, and the **three-finger pinch/spread** for copy/cut/paste and the **three-finger swipe** for undo/redo (iPadOS 13+). The editing menu itself moved from the old `UIMenuController` to **`UIEditMenuInteraction`** (iOS 16+). These are mostly transient, but two leave traces worth knowing: **cut/copy/paste flows through the system pasteboard** (a cross-device, Continuity-aware surface — see [[continuity-with-the-mac]] and [[notifications-keyboard-and-misc-stores]]), and selection of recognized handwriting feeds the same draft/autosave machinery as typing.

### Accessibility features as power tools

Several Accessibility settings are, in practice, the most powerful input controls on the device:

- **Full Keyboard Access** — drive the *entire* UI from a hardware keyboard (tab/arrow focus, a command mode), beyond per-app `UIKeyCommand`s.
- **AssistiveTouch** — connect a pointing device or switch and synthesize touches; also enables on-screen pointer dwell.
- **Voice Control** — full spoken command + dictation control of the device (a power dictation tool, not just an a11y feature).
- **Pointer Control** — tune cursor size, color, contrast, and trackpad inertia/scaling.

> 🔬 **Forensics note:** Accessibility configuration is a **behavioral fingerprint** and lives in preference plists (the Accessibility/`UniversalAccess`/keyboard-preference domains). Enabled Voice Control, Full Keyboard Access, or AssistiveTouch tells you *how* the device was driven, which can corroborate or contradict claims about who used it and how. Confirm the exact preference domain/keys on your target version before quoting them.

### The forensic surface: what each input plane leaves on disk

Pulling the planes together, here is where input residue actually lands. Everything below is **device-only** (a full-filesystem acquisition in at least AFU state — see [[full-file-system-acquisition]] and [[bfu-vs-afu-and-data-protection-classes]]) and is **identical on iPad and iPhone** unless noted; the iPad simply generates *more* of it (Pencil) and from more sources (hardware keyboard).

**1. The keyboard learned lexicon — `/private/var/mobile/Library/Keyboard/`.** The predictive/autocorrect engine persists what the user types so it can learn:

| Artifact | Path (under `…/Keyboard/`) | Contents |
|---|---|---|
| Dynamic lexicon | `dynamic-text.dat` (and per-language `<lang>-dynamic-text.dat`, e.g. `en_US-dynamic-text.dat`) | Binary cache of learned/typed words — historically ~hundreds of words per language; hex/`strings`-viewable. A near-keylogger of distinctive terms. |
| Swipe traces | `shapestore.db` (iOS 13+) | SQLite store backing QuickPath/swipe-typing; overlaps the dynamic lexicon's vocabulary. |
| User dictionary | `UserDictionary.sqlite` | User-defined **Text Replacement** shortcuts and learned entries. |

These persist **independently of the source app** and often survive deletion of the originating message/note — frequently the *only* place a distinctive term survives. Crucially for this lesson: **the lexicon grows the same whether the user typed on glass or on a Magic Keyboard**, and **Scribble-recognized handwriting feeds it too** — so on a Pencil-heavy, keyboard-equipped iPad the lexicon is *richer*, not bypassed. Full treatment in [[notifications-keyboard-and-misc-stores]].

**2. Apple Pencil handwriting — `PKDrawing` blobs.** As above: inline in `NoteStore.sqlite` for Notes (`ZICNOTEDATA.ZDATA`), in Freeform, and in third-party note-app containers. Per-stroke timing inside; render or recognize for content.

**3. Screenshots and markup — the Photos library.** User screenshots are **PNG**s in the camera roll (and the **Screenshots** smart album), with deliberately **minimal EXIF** — capture time and pixel dimensions, but **no GPS, no camera/lens make/model** (because no camera was involved). That absence is itself diagnostic: a "photo" with no camera EXIF and PNG encoding is almost certainly a screenshot, not an original capture. In `Photos.sqlite` (the `ZASSET` table on iOS 14+, formerly `ZGENERICASSET`) a screenshot is flagged by a saved-asset-type / kind-subtype column (confirm the exact column on your schema version — it has changed). **Markup** — the Pencil/finger annotation layer on a screenshot or photo — is itself **PencilKit**, applied as a **non-destructive Photos adjustment**: the library keeps the **original** image plus an **adjustment** record (`ZUNMANAGEDADJUSTMENT` / adjustment-data blob) and a rendered **derivative**. That means you can recover the *pre-markup* original *and* prove an annotation was added (and often when). Distinct from these are the system's **app-snapshot `.ktx`** files (the last-screen images SpringBoard caches for the app switcher under each app's `Library/…/Snapshots/`) — not user screenshots, but a related "what was on screen" surface (Brignoni's iOS Snapshots Triage Parser).

**4. Pointer / keyboard / Pencil *pairing*.** Bluetooth/HID accessory records for the trackpad, keyboard, and Pencil; the Apple Pencil Pro's Find My accessory registration. These establish *which* input hardware the device used and when it attached.

> 🖥️ **macOS contrast:** The Mac has a directly comparable learned-text surface — the spelling/autocorrect learned words and `~/Library/Spelling/` / the `LocalDictionary` — but nothing as centralized or as forensically rich as iOS's `dynamic-text.dat`. And the Mac's screenshots default to PNG on the Desktop with their own EXIF minimalism, but markup there is `PDFKit`/Preview annotation, not PencilKit. The iOS keyboard lexicon is the closest thing iOS has to a "what did this person type" oracle, and it has no equally tidy Mac twin.

> ⚠️ **ADVANCED (device-only acquisition):** None of the four surfaces above appear in an iTunes/Finder *logical* backup in full — the keyboard lexicon files, the raw `PKDrawing` blobs in some apps, the Photos adjustment derivatives, and the snapshot `.ktx` caches require a **full-filesystem acquisition** (BootROM-exploit on A8–A13, or an agent path on A14+), and only in at least **AFU** lock state with the right keys. Plan the method around the artifact you need; you cannot retroactively pull a learned lexicon or a snapshot cache out of a backup that never contained it.

## Hands-on

There is **no on-device shell**, and the iPad's most distinctive input behaviors (real Pencil sensors — force/tilt/azimuth/roll, hover, squeeze, barrel roll; the learned-lexicon daemons; accessory pairing) **do not exist in the Simulator**. So the Mac-side plan is: (a) use the Simulator to exercise the *APIs and the serialized data structures* (PencilKit ink → bytes, the ⌘-hold HUD, pointer effects), and (b) use **public sample images** for the device-only on-disk residue (keyboard lexicon, screenshot/markup, pairing).

**Enumerate iPad simulators (the substrate for the API labs):**
```bash
xcrun simctl list devicetypes | grep -i ipad
#   iPad Pro 13-inch (M4) (com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4)
#   iPad Air 11-inch (M3) (com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3)
#   iPad mini (A17 Pro)   (com.apple.CoreSimulator.SimDeviceType.iPad-mini-A17-Pro)

DEV=$(xcrun simctl create "input-lab" \
  com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4)
xcrun simctl boot "$DEV"
```

**Capture a `PKDrawing` to disk from a Simulator app, then dissect it on the Mac.** Build a minimal PencilKit app (a `PKCanvasView`) that, on a button tap, writes `canvas.drawing.dataRepresentation()` to a file in its container. Draw a few strokes *with the mouse*, then locate and inspect the blob:
```bash
# Find the freshest file your app wrote inside its data container:
DATA=~/Library/Developer/CoreSimulator/Devices/$DEV/data
BLOB=$(find "$DATA/Containers/Data/Application" -name 'drawing*.dat' -print 2>/dev/null | tail -1)

file "$BLOB"                 # generic "data" — opaque, as expected
xxd "$BLOB" | head           # inspect the leading bytes / magic
# Detect & inflate the (historically zlib/gzip) payload, then try a raw protobuf decode:
python3 - "$BLOB" <<'PY'
import sys, zlib
raw = open(sys.argv[1],'rb').read()
for wbits in (47, -15, 15):            # gzip / raw-deflate / zlib
    try:
        out = zlib.decompress(raw, wbits); print("inflated", len(out), "bytes"); 
        open("/tmp/pkdrawing.inner","wb").write(out); break
    except Exception as e: pass
else: print("not zlib/gzip framed — inspect with xxd")
PY
protoc --decode_raw < /tmp/pkdrawing.inner 2>/dev/null | head -40 || \
  echo "decode_raw failed — framing/version-specific; parse heuristically"
```
The point is not a clean parse (the schema is undocumented and version-bound) — it is to *see* that ink is a compressed, versioned vector structure and to confirm whether `protoc --decode_raw` finds field tags. **Fidelity caveat:** the Simulator has no Pencil, so every `PKStrokePoint` will carry synthetic defaults for `force`/`azimuth`/`altitude` (mouse input) — the *structure* is real, the *sensor values* are not.

**Surface Pencil handwriting from a Notes store (sample image; copy-first — a `SELECT` write-locks SQLite and spawns `-wal`/`-shm`):**
```bash
NS=/path/to/extraction/.../group.com.apple.notes/NoteStore.sqlite
cp "$NS" /tmp/notestore.db
sqlite3 /tmp/notestore.db "
  SELECT Z_PK, ZTITLE1,
         datetime(ZCREATIONDATE1 + 978307200,'unixepoch','localtime') AS created,
         datetime(ZMODIFICATIONDATE1 + 978307200,'unixepoch','localtime') AS modified
  FROM ZICCLOUDSYNCINGOBJECT
  WHERE ZTITLE1 IS NOT NULL ORDER BY ZMODIFICATIONDATE1 DESC LIMIT 20;"
# Body protobuf with embedded PKDrawing rides in ZICNOTEDATA.ZDATA (gzipped). Confirm the
# table/column lineage against the NoteStore schema for the image's iOS version, then
# gunzip + parse, locate the PKDrawing, and read PKStrokePath.creationDate per stroke.
```
The Apple epoch (`+ 978307200`, Mac Absolute Time) is the same one you used across macOS and in [[the-ios-timestamp-zoo]].

**Read the keyboard learned lexicon (sample image; device-only artifact):**
```bash
KB=/path/to/extraction/private/var/mobile/Library/Keyboard
strings -n 4 "$KB/dynamic-text.dat" | head -50            # learned/typed words
strings -n 4 "$KB"/*-dynamic-text.dat 2>/dev/null | head  # per-language variants
cp "$KB/shapestore.db" /tmp/shapestore.db && sqlite3 /tmp/shapestore.db ".tables"
cp "$KB/UserDictionary.sqlite" /tmp/userdict.db && \
  sqlite3 /tmp/userdict.db ".schema" && \
  sqlite3 /tmp/userdict.db "SELECT * FROM <table> LIMIT 20;"   # text-replacement shortcuts
```

**Screenshot vs camera-original triage, and markup recovery:**
```bash
# EXIF contrast: a screenshot has no camera/GPS tags, PNG encoding, capture time only.
exiftool -Make -Model -GPSLatitude -FileType -CreateDate screenshot.png camera.jpg
# Photos catalog: flag screenshots + find markup (non-destructive) adjustments. Copy first.
cp /path/to/extraction/.../Photos.sqlite /tmp/photos.db
sqlite3 /tmp/photos.db "
  SELECT Z_PK, ZFILENAME,
         datetime(ZDATECREATED + 978307200,'unixepoch','localtime') AS created
  FROM ZASSET
  WHERE ZFILENAME LIKE '%.PNG' OR ZFILENAME LIKE 'IMG%.PNG'
  ORDER BY ZDATECREATED DESC LIMIT 30;"
# The screenshot subtype flag and the markup/adjustment columns (e.g. ZUNMANAGEDADJUSTMENT)
# vary by schema version — dump .schema for ZASSET / ZADDITIONALASSETATTRIBUTES first.
```

**Look for input-hardware pairing (sample image; path is version-specific):**
```bash
# Bluetooth accessory records (keyboard / trackpad / Pencil) — confirm the path on your image:
find /path/to/extraction -iname '*MobileBluetooth*' -o -iname '*bluetooth*.plist' 2>/dev/null
# Then plutil -p / a plist parser to read paired-accessory names + addresses.
```

## 🧪 Labs

> ⚠️ **Substrate honesty up front:** Labs 1–3 run on the **Xcode Simulator** and teach *API + data structure only* — the Simulator has **no Apple Pencil sensors** (force/tilt/azimuth/roll), **no hover/squeeze/barrel-roll**, **no learned-lexicon daemons**, and **no accessory pairing**. Labs 4–6 use a **public iOS/iPadOS sample image** (Josh Hickman / Digital Corpora, or iLEAPP/mvt test data) or a **read-only walkthrough** for the device-only on-disk residue. Anything to do with real Pencil pressure, the keyboard lexicon files, or pairing is device/image-only.

### Lab 1 — PencilKit ink → bytes *(substrate: Xcode Simulator; caveat: mouse strokes ⇒ synthetic `force`/`azimuth`/`altitude`; no real Pencil)*
1. Build a one-screen app with a `PKCanvasView` + `PKToolPicker`; add a button that writes `canvas.drawing.dataRepresentation()` to a file in the app container.
2. Draw three distinct strokes (with the mouse), tap save.
3. Find the blob under `…/Devices/<UDID>/data/Containers/Data/Application/…`, run `file`/`xxd`, then inflate + `protoc --decode_raw` per the Hands-on snippet.
4. **Conclusion to internalize:** ink is a *compressed, versioned vector structure*, not an image and not text — recovering content needs rendering or recognition, and the on-disk layout is version-bound.

### Lab 2 — Read per-stroke timing from a `PKDrawing` *(substrate: Lab 1 bytes, or a Notes drawing in a sample image; caveat: byte layout undocumented/version-specific)*
1. From Lab 1's app, also dump, for each `PKStroke`, `stroke.path.creationDate` and the first/last `PKStrokePoint.timeOffset` (log them, or write a CSV).
2. Order the strokes by `creationDate`; compute the gaps. Note how three quick strokes cluster vs. a deliberate pause.
3. On a *sample image*, repeat conceptually against a Notes-embedded drawing, and compare the newest stroke's time to the note row's `ZMODIFICATIONDATE1`. Explain in one line what a *later* modification timestamp implies (a post-drawing edit — text added, drawing moved).

### Lab 3 — The ⌘-hold HUD and the key-command responder chain *(substrate: Simulator with "Connect Hardware Keyboard"; caveat: HUD renders, but system/Globe-key global shortcuts are SpringBoard-owned and not fully modeled)*
1. In a Simulator app, override `keyCommands` (or `buildMenu(with:)`) to declare 3–4 `UIKeyCommand`s with `title`s (e.g. ⌘N, ⌘F, ⌘⇧S).
2. Simulator → I/O → Keyboard → **Connect Hardware Keyboard**. Hold **⌘**. Observe the discoverability HUD list your titled commands.
3. Move the same commands between two responders (a view controller vs. a focused subview) and watch which appear — first-responder semantics in action.
4. Write down the mapping: `UIKeyCommand.title` → HUD label → (on iPadOS 26) menu-bar item. One declaration, three surfaces.

### Lab 4 — The keyboard learned lexicon *(substrate: public iOS/iPadOS sample image; caveat: the Simulator does NOT populate these files — device-only)*
1. In the image, `strings` the `dynamic-text.dat` (and any `<lang>-dynamic-text.dat`). Pick out distinctive proper nouns/terms.
2. Cross-check a term against the Messages/Notes content — confirm the lexicon retained a word whose source you can (or *cannot*) still find. The lexicon-only term is the forensic payoff.
3. Schema-dump and query `shapestore.db` and `UserDictionary.sqlite`. Note the user's Text Replacement shortcuts.
4. State the input-source insight: this residue is identical whether the user typed on glass, on a Magic Keyboard, or via Scribble.

### Lab 5 — Screenshot vs original, and peel back a markup *(substrate: sample image, or your own exported screenshot + a real photo; caveat: Simulator screenshots are synthetic)*
1. `exiftool` a screenshot PNG against a camera JPG. List which tags are *absent* on the screenshot (Make/Model/GPS/lens) — that absence is the screenshot tell.
2. In `Photos.sqlite` (copy first), dump the `ZASSET` schema; find the screenshot subtype flag and a row with a markup/`ZUNMANAGEDADJUSTMENT` adjustment.
3. Articulate the recovery: the **original** is preserved and the markup is a **non-destructive adjustment** — so you can produce both the annotated derivative *and* the pristine pre-markup image, and prove an annotation was added.

### Lab 6 — Input-hardware pairing (Pencil / keyboard / trackpad) *(substrate: read-only walkthrough + sample image; caveat: pairing is device-only; Bluetooth store path is version-specific)*
1. In a sample image, locate the Bluetooth accessory records; enumerate paired devices and identify any keyboard/trackpad/**Apple Pencil**.
2. If an **Apple Pencil Pro** is present, note that it may also carry a **Find My accessory** registration (a location-bearing beacon — see [[find-my-and-the-ble-mesh]]).
3. Tie it to the handwriting evidence: a paired Pencil corroborates that `PKDrawing` content on the device is plausibly first-party. Document the path/keys you used and flag them as version-specific.

## Pitfalls & gotchas

- **Treating a `PKDrawing` as an image or as text.** It is neither — it is a compressed, versioned vector blob. You must render it (PencilKit can rasterize) or run handwriting recognition; and the rendered PNG is a *derived* exhibit, so preserve and hash the raw bytes first.
- **Asserting the `PKDrawing` byte layout.** The serialization is undocumented and **version-bound** (`PKContentVersion`). Detect compression, inflate, decode heuristically, and confirm against the producing PencilKit version. Do not quote offsets/field numbers as if stable.
- **Believing the Simulator's ink.** Mouse strokes mean `force`/`azimuth`/`altitude`/roll are synthetic. The *structure* is faithful; the *sensor fields* are not — never characterize pressure/tilt behavior from a Simulator capture.
- **Assuming opaque ink = unreadable.** If Scribble or an app recognizer ran, the **recognized text may already be in a plain text column**. Check the text store before fighting the blob.
- **Thinking a hardware keyboard bypasses the lexicon.** It does not — `dynamic-text.dat`/`shapestore.db`/`UserDictionary.sqlite` learn from physical-keyboard and Scribble input the same as on-screen typing. A Magic-Keyboard-driven iPad has a *richer* lexicon, not an absent one.
- **Confusing user screenshots with app-snapshot `.ktx` caches.** The `.ktx` files are SpringBoard's app-switcher snapshots (a separate "what was on screen" surface), not the PNGs in the camera roll. Different paths, different meaning.
- **Missing the pristine original under a markup.** Markup is a non-destructive Photos adjustment — the un-annotated original is still there. Recover it; don't report only the marked-up derivative.
- **Reading the cursor as an artifact.** The adaptive pointer leaves no log; its only forensic value is *inferred* from accessory pairing + lexicon activity. Don't hunt for a "pointer history."
- **Expecting these surfaces in a logical backup.** Keyboard lexicon, raw ink in some apps, Photos adjustment derivatives, and `.ktx` caches need a **full-filesystem acquisition** in ≥AFU state. Choose the method up front.
- **Quoting unverified paths/columns.** Confirm against your target image, not memory: the Bluetooth accessory store path, the `Photos.sqlite` screenshot-subtype and adjustment columns, the `NoteStore` body-column lineage, and the Pencil-Pro roll `PKStrokePoint` property name.

## Key takeaways

- iPadOS routes touch, indirect pointer, hardware keyboard, and Apple Pencil through **one UIKit event/responder pipeline**; what differs is per-source metadata and the *system services* layered on top (the cursor, the HUD, Scribble, PencilKit).
- The **adaptive pointer** is a **system-drawn, morphing layer** (`UIPointerInteraction` + effects/shapes), not a Mac-style fixed sprite and not an emulated finger — it leaves no log of its own.
- Hardware keyboard support is the `UIResponder` analogue of `NSResponder`: **`UIKeyCommand` + `buildMenu(with:)`** feed the **⌘-hold discoverability HUD** *and* the iPadOS 26 menu bar from one declaration.
- **Apple Pencil ink is captured by PencilKit as a `PKDrawing`** — an opaque, versioned, compressed vector blob — and is an iPad-class artifact with no iPhone and no native-Mac twin.
- **`PKStrokePath.creationDate` + per-point `timeOffset` give handwriting a micro-timeline** — stroke order and inter-stroke gaps — that can corroborate or contradict the note's own metadata.
- **Scribble output and learned text land in the normal text store** and feed the **keyboard learned lexicon** (`dynamic-text.dat`, `shapestore.db`, `UserDictionary.sqlite`) — a near-keylogger that survives deletion and grows regardless of input source.
- **Screenshots are PNGs with no camera/GPS EXIF; markup is a non-destructive Photos adjustment** — so you can recover the pristine original and prove the annotation.
- All of this on-disk residue is **device-only** (full-filesystem, ≥AFU) and **schema/path version-bound** — lead with the mechanism, verify the perishable detail against the image.

## Terms introduced

| Term | Definition |
|---|---|
| `UIPointerInteraction` | UIKit API (iPadOS 13.4+) that lets a view declare pointer regions and styles so the system can drive the adaptive cursor. |
| `UIPointerStyle` / effect / shape | The pointer's declared appearance: an *effect* (`.highlight`/`.lift`/`.hover`) on the content + a *shape* (rounded-rect/path/morph) for the cursor. |
| Adaptive precision | The behavior where the iPad pointer snaps to and reshapes around controls under it. |
| `UIHoverGestureRecognizer` | Reports pointer/Pencil hover (enter/move/exit) without a click; the basis of Apple Pencil hover. |
| `UIKeyCommand` | A hardware-keyboard chord (input + modifierFlags + action + title) dispatched up the responder chain. |
| `buildMenu(with:)` / `UIMenuBuilder` / `UIMenuSystem.main` | The command-tree API (iOS/iPadOS 13+) feeding the ⌘-hold HUD, the iPadOS 26 menu bar, and Mac Catalyst menus. |
| ⌘-hold discoverability HUD | The translucent overlay listing currently-available titled shortcuts when Command is held with a hardware keyboard attached. |
| Full Keyboard Access | Accessibility mode giving complete hardware-keyboard navigation/control of the UI. |
| Apple Pencil Pro | Pencil generation adding squeeze, barrel roll (gyroscope/roll angle), haptics, hover, and Find My. |
| PencilKit | Apple's pen-ink framework: `PKCanvasView`, `PKDrawing`, `PKStroke`, `PKToolPicker`. |
| `PKDrawing` | The serialized drawing: an opaque, versioned, compressed vector blob (`dataRepresentation()` / `PKDrawing(data:)`; `NSSecureCoding` + `Codable`). |
| `PKStroke` / `PKStrokePath` / `PKStrokePoint` | A stroke, its interpolated path (with `creationDate`), and its control points (location, `timeOffset`, force, size, azimuth/altitude/roll). |
| `PKContentVersion` | PencilKit's content-version enum (surfaced iOS 17+) tagging a serialized drawing by ink-feature era (`.version1` = iOS 13 inks → `.version4` = iPadOS 26) for forward/backward compatibility; a drawing's floor is `PKDrawing.requiredContentVersion`. |
| Scribble / `UIScribbleInteraction` | On-device handwriting-to-text in any text field; recognized text commits to the normal text store. |
| `PKStrokeRecognizer` | WWDC 2026 (iOS/iPadOS/macOS/visionOS 27 cycle, not yet shipped) public on-device handwriting-recognition API in PencilKit. |
| `dynamic-text.dat` | Binary keyboard learned-lexicon at `/private/var/mobile/Library/Keyboard/` (+ per-language variants); persists typed/learned words. |
| `shapestore.db` / `UserDictionary.sqlite` | SQLite swipe-typing store (iOS 13+) and the user's Text-Replacement/learned dictionary, alongside `dynamic-text.dat`. |
| Markup (Photos adjustment) | PencilKit-based annotation applied as a non-destructive Photos adjustment, preserving the original + a derivative. |

## Further reading

- Apple Developer — *Integrating pointer interactions into your iPad app*; *Build for the iPadOS pointer* / *Design for the iPadOS pointer* (WWDC20). `UIPointerInteraction`, `UIPointerStyle`, `UIHoverGestureRecognizer`.
- Apple Developer — `UIKeyCommand`, `buildMenu(with:)`, `UIMenuSystem`, `UIResponder`; *Adding hardware keyboard support to your app*; GameController `GCKeyboard`.
- Apple Developer — PencilKit: `PKCanvasView`, `PKDrawing`, `PKStroke`/`PKStrokePath`/`PKStrokePoint`, `PKInk`, `PKToolPicker`; WWDC20 *What's new in PencilKit* and *Inspect, modify, and construct PencilKit drawings*; WWDC26 *Read between the strokes with PencilKit* (`PKStrokeRecognizer`, stroke↔Bézier, slicing).
- Apple Developer — `UIScribbleInteraction` / `UIIndirectScribbleInteraction`; WWDC20 *Meet Scribble for iPad*.
- Apple Support — Apple Pencil Pro tech specs (support.apple.com/120123); *Enter text with Scribble on iPad*.
- Sarah Edwards (mac4n6.com) — keyboard `dynamic-text.dat`/`shapestore.db` and iOS artifact research; Alexis Brignoni (abrignoni.blogspot.com / iLEAPP) — *iOS Snapshots Triage Parser* (`.ktx`), swipe-to-type research; Ian Whiffin (d204n6.com) — Photos/Notes/PencilKit parsing.
- *Practical Mobile Forensics* (Packt) — iOS keyboard cache (`dynamic-text.dat`), Photos and screenshot artifacts.
- The Metadata Perspective — "Camera Original Photos vs. Screenshots in Court" (screenshot EXIF minimalism, evidentiary handling).
- Josh Hickman, thebinaryhick.blog / Digital Corpora — public iOS/iPadOS reference images for the device-only labs.
- `man strings`, `man sqlite3`, `exiftool` (Phil Harvey), `protoc --decode_raw` — always confirm flag semantics for your tool versions.

---
*Related lessons: [[how-ipados-diverges-from-ios]] | [[windowing-multitasking-and-external-display]] | [[mail-notes-calendar-reminders]] | [[notifications-keyboard-and-misc-stores]] | [[photos-and-the-camera-roll]] | [[the-ios-timestamp-zoo]] | [[full-file-system-acquisition]] | [[find-my-and-the-ble-mesh]] | [[third-party-app-methodology]] | [[continuity-with-the-mac]]*
