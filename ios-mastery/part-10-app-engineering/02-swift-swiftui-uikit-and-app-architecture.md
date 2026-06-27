---
title: "Swift, SwiftUI, UIKit & app architecture"
part: "10 — iOS App Engineering"
lesson: 02
est_time: "45 min read + 20 min labs"
prerequisites: [ios-xcode-and-the-build-system]
tags: [ios, dev, swift, swiftui, uikit, architecture]
last_reviewed: 2026-06-26
---

# Swift, SwiftUI, UIKit & app architecture

> **In one sentence:** Every iOS app is one of three architectural species — a UIKit imperative app, a SwiftUI declarative app, or a hybrid — and the species, the lifecycle it chose, and the state framework it uses all leave *distinct, machine-readable fingerprints* in the Mach-O (the `__swift5_*` metadata sections, the Obj-C class list, the load commands, the `Info.plist` scene manifest) that a reverser reads before opening a single function.

## Why this matters

You already know Swift the language from `macos-mastery`. What changes on iOS is the *plumbing around* the language: which UI framework owns the screen, which lifecycle owns the process, and which state-propagation framework owns your data. Those three choices are not just developer ergonomics — they determine the binary's shape. A SwiftUI screen is a `struct` conforming to a protocol and emits **zero** Obj-C class metadata; the equivalent UIKit screen is an `NSObject`-derived class that shows up in `__objc_classlist` with a mangled name and a method list you can dump statically. As a reverser you triage a binary by reading those fingerprints in seconds; as a builder you need to know *why* they exist so you can predict what a tool like Hopper, `dsdump`, or Frida will and won't recover. This lesson is the bridge between the two roles — the architecture, and the artifact it leaves.

It is deliberately *condensed* — you build apps already, so this is not a SwiftUI tutorial. It is the architectural spine plus the part the macOS course couldn't give you: how each design decision (UI framework, lifecycle, state, persistence, concurrency) becomes an on-disk fingerprint, and where that fingerprint lives in the Mach-O and the app container. Read it once as an engineer; reach for the fingerprint tables when you're triaging.

## Concepts

### The three species (and SwiftData, the fourth axis)

An iOS UI is built with **UIKit**, **SwiftUI**, or both. Persistence is an orthogonal choice — **Core Data**, **SwiftData**, raw SQLite/GRDB, or files. Don't conflate the UI axis with the persistence axis; a SwiftUI app can use Core Data, and a UIKit app can use SwiftData.

| | UIKit | SwiftUI | SwiftData |
|---|---|---|---|
| **Paradigm** | Imperative, retained-mode view tree | Declarative, value-type view *descriptions* | Declarative persistence (`@Model`) |
| **Core unit** | `UIView`/`UIViewController` (`class`, `NSObject`-derived) | `View` (`struct`, no class) | `@Model` class (a Swift `PersistentModel` class) |
| **Shipped since** | iOS 2 (2008) | iOS 13 (2019) | iOS 17 (2023) |
| **Obj-C runtime exposure** | Heavy — every view/VC is an Obj-C class | None for views (structs) | None *statically* — the `@Model` class is plain Swift (conforms to `PersistentModel`/`Observable`); the `NSManagedObject` is a runtime backing object, not the class's superclass |
| **Underlying storage** | n/a | n/a | Core Data stack → SQLite (`default.store`) |
| **When to reach for it** | Fine-grained control: custom drawing, complex collection layouts, camera/`AVFoundation` UI, legacy codebases, anything SwiftUI can't express yet | New screens, the default for greenfield in 2026, cross-Apple-platform UI | New-project persistence; replaces Core Data boilerplate |

The 2026 default stack for a new app is **SwiftUI views + `@Observable` state + SwiftData persistence + `NavigationStack` routing**. But "SwiftUI app" almost always means *hybrid*: SwiftUI is built on top of UIKit (`UIHostingController` bridges a SwiftUI view hierarchy into a `UIViewController`), so even a pure-SwiftUI app links and runs UIKit underneath, and most real apps drop to UIKit (`UIViewControllerRepresentable`) for the 5% SwiftUI can't do. This hybrid reality is exactly why binary triage matters: you can't assume from the App Store description which framework drew a given screen.

> 🖥️ **macOS contrast:** UIKit is the iOS counterpart of **AppKit** — `UIApplication`↔`NSApplication`, `UIViewController`↔`NSViewController`, `UIView`↔`NSView`, `UIResponder`↔`NSResponder`, `UIWindow`↔`NSWindow`. The mental shift: AppKit was *never* rebuilt for declarative scenes the way UIKit was, so AppKit has no `UIScene` analogue (macOS multi-window is `NSWindowController`/`NSDocument`). SwiftUI is the *same framework* on both platforms — the `View` protocol, `@State`, `@Observable` are identical source — but the scene plumbing diverges (`WindowGroup`/`Settings`/`MenuBarExtra` on macOS vs. the iOS scene/`scenePhase` model below).

### Swift modules and ABI stability — why an app binary is small and where the runtime lives

Swift reached **ABI stability** in **Swift 5.0 (March 2019)** on Apple platforms. That single event reshaped what an iOS app binary contains:

- **The Swift runtime and standard library ship *in the OS*.** `libswiftCore.dylib` and friends live in the **dyld shared cache** (see [[02-the-dyld-shared-cache]]), not in your app. Pre-5.0 apps embedded `@rpath/libswift*.dylib` copies in `MyApp.app/Frameworks/` (tens of MB). Post-5.0 they link against the OS copy. A reverser sees this in `otool -L`: a 2026 app lists `/usr/lib/swift/libswiftCore.dylib` with no bundled Swift dylibs.
- **The calling convention, metadata layout, and name mangling are frozen.** This is what makes static Swift analysis tractable at all: the `__swift5_*` section formats below are stable contracts, so tools like `dsdump`, `class-dump-swift`, and Ghidra's Swift loader can decode any modern binary.
- **Module stability** (Swift 5.1) added the textual `.swiftinterface` and enabled binary frameworks (`.xcframework`) usable across compiler versions, via **library evolution mode** (`-enable-library-evolution`) and `@frozen`/`@usableFromInline`. Most apps build their *own* modules non-resilient (whole-module optimization inlines aggressively), which is why an app's own types are often *more* aggressively optimized — and harder to recover — than the system frameworks they call.

> 🗓️ **Dated (verify at author time):** Toolchain is **Xcode 26.4 / Swift 6.3** (released 2026-03-24). Swift 6.3 is a "Swift everywhere" release (finalized Embedded Swift, WebAssembly/WASI, Android, preview FreeBSD) plus codegen attributes — `@specialize`, `@inline(always)`, `@export(implementation)` for ABI-stable libraries, `@c` for C-ABI export (SE-0495), `weak let` (SE-0481). None of this changes the *metadata* story below; the `__swift5_*` contract is the durable layer.

### The two lifecycles

There are two ways an iOS app boots and tracks foreground/background state. Knowing which one a binary uses tells you where the entry point is and what delegate methods to hook.

**1. The classic UIKit lifecycle** — `UIApplicationMain` → `UIApplicationDelegate` → (since iOS 13) `UISceneDelegate`:

```
            UIApplicationMain(argc, argv, nil, "AppDelegate")
                              │
                   ┌──────────▼──────────┐
                   │  UIApplication       │  (the singleton, .shared)
                   └──────────┬──────────┘
                              │ application(_:didFinishLaunchingWithOptions:)
                   ┌──────────▼──────────┐
                   │  UIApplicationDelegate │  process-level events:
                   │  (AppDelegate)        │  launch, APNs token, memory warning
                   └──────────┬──────────┘
                              │ scene(_:willConnectTo:options:)
                   ┌──────────▼──────────┐
                   │  UISceneDelegate     │  per-window UI lifecycle:
                   │  (SceneDelegate)     │  foreground/background, URL open,
                   └──────────┬──────────┘  owns the UIWindow
                              ▼
                       window.rootViewController
```

The split (iOS 13+) is the important part: **the `AppDelegate` owns *process* events; the `SceneDelegate` owns *UI* events** and owns the `UIWindow`. A single process can have multiple scenes (the basis of iPad multi-window — see [[01-windowing-multitasking-and-external-display]]). Scenes are declared in `Info.plist` under the `UIApplicationSceneManifest` key.

> 🗓️ **Dated (verify at author time):** This split is now being *enforced*. In **iOS 26** an app built without scene adoption logs the console warning *"UIScene lifecycle will soon be required"*, and `application(_:open:options:)` is **deprecated** (URL handling moved to `UISceneDelegate`). Apple's stated plan (TN3187) is that with the **next major SDK (iOS 27-era)** a UIKit app that hasn't adopted `UIScene` **will not launch**. APNs registration callbacks stay in `AppDelegate` (there is no scene equivalent). Forensically and for RE this means: a 2026+ binary almost certainly has a populated `UIApplicationSceneManifest` and a `UISceneDelegate` class — its absence dates the app or flags a stale build.

**2. The SwiftUI lifecycle** — the `App`/`Scene` protocols, no delegate required:

```swift
@main
struct MyApp: App {                 // App protocol; @main synthesizes the entry point
    @State private var model = AppModel()
    var body: some Scene {          // Scene, not View
        WindowGroup {               // a Scene that vends windows
            ContentView()
                .environment(model)
        }
    }
}
```

`@main` on an `App`-conforming struct makes the compiler **synthesize a `static func main()`** and a top-level `main` that hands control to SwiftUI's app runner — *there is no `UIApplicationMain` call and no `AppDelegate` by default*. Foreground/background state arrives declaratively via `@Environment(\.scenePhase)` (`.active` / `.inactive` / `.background`) rather than delegate callbacks. When you *do* need UIKit delegate hooks (APNs, third-party SDK init), you bridge with the property wrappers `@UIApplicationDelegateAdaptor` (and, increasingly, `@UISceneDelegateAdaptor`):

```swift
@main
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene { WindowGroup { ContentView() } }
}
```

| | UIKit lifecycle | SwiftUI lifecycle |
|---|---|---|
| Entry point | `UIApplicationMain` (via `@main` on the delegate or legacy `@UIApplicationMain`) | synthesized `main` → SwiftUI app runner (`@main` on `App` struct) |
| Process events | `UIApplicationDelegate` | `@UIApplicationDelegateAdaptor` (opt-in) |
| UI/window events | `UISceneDelegate` | `Scene` types + `@Environment(\.scenePhase)` |
| Window ownership | `UIWindow` (held by scene) | `WindowGroup` / `Window` scenes |
| Binary signal | `_UIApplicationMain` import; `AppDelegate`/`SceneDelegate` in `__objc_classlist` | conformances to `SwiftUI.App`/`SwiftUI.Scene` in `__swift5_proto`; SwiftUI in `LC_LOAD_DYLIB` |

> 🖥️ **macOS contrast:** The SwiftUI lifecycle is shared — `@main struct App` works identically on macOS — but the adaptor is `@NSApplicationDelegateAdaptor` and the scenes differ (`Settings`, `MenuBarExtra`, `Window` vs. iOS's `WindowGroup`+scene manifest). On macOS there is no `UIScene` and no scene manifest at all; `NSApplication` never got the scene retrofit, so a macOS reverser never looks for `UIApplicationSceneManifest`.

### The responder chain

Both UIKit and (under the hood) SwiftUI route events — touches, keyboard, menu commands, motion — through the **responder chain**: a linked list of `UIResponder` objects. An event not handled by the first responder bubbles up `next` until something handles it or it falls off the end.

```
UIView (where the touch landed)
   │ .next
UIView (superview) … up the view tree …
   │ .next
UIViewController (managing that view)
   │ .next
UIWindow
   │ .next
UIApplication
   │ .next
UIApplicationDelegate   ← end of the line; unhandled events die here
```

Two mechanics worth internalizing:

- **Hit-testing** (`hitTest(_:with:)` → `point(inside:with:)`) runs *first*, top-down, to find which view the touch is over and thus the *start* of the chain. Then handling runs *bottom-up* via `next`.
- **First responder** is the object that gets keyboard input and the target of `nil`-targeted actions (`sendAction(_:to:nil:from:for:)` with `to: nil` walks the chain). `becomeFirstResponder()`/`resignFirstResponder()` move it.

SwiftUI doesn't expose the chain directly — you use `.onTapGesture`, `FocusState`, `.focusable()`, `@FocusState`, and `.commands` — but the underlying `UIHostingController` *is* in the chain, and SwiftUI's gesture system ultimately sits on UIKit's event delivery. This is why a SwiftUI app embedded in UIKit still respects `canBecomeFirstResponder` on the host.

> 🖥️ **macOS contrast:** AppKit's responder chain is `NSResponder`-based and conceptually identical, but it extends through `NSWindow` → `NSWindowController` → `NSApplication` → `NSApplicationDelegate`, and crucially through the **menu bar** (menu items send first-responder actions). The "send to `nil`" target/action pattern is the same idiom you saw in AppKit.

### Navigation and routing

UIKit navigation is *imperative*: a `UINavigationController` owns a stack you `pushViewController(_:animated:)` / `popViewController(animated:)`, or a storyboard segue wires transitions declaratively-in-the-XML. The modern SwiftUI equivalent is **`NavigationStack` with value-based routing**: you bind a `path` (an array of `Hashable` route values, often a typed enum), and `.navigationDestination(for:)` maps each value type to a destination view. Pushing a screen is appending to the array; deep-linking is just *setting* the array. This is the basis for state-restoration and URL/`NSUserActivity` handling, which (post-iOS-26) flows through `UISceneDelegate`/`onOpenURL` rather than the deprecated `application(_:open:options:)`.

> 🔬 **Forensics note:** A value-based route path is `Codable` state an app can persist for restoration — look for the system-held per-scene restoration state (each scene's `stateRestorationActivity`/`NSUserActivity`, persisted by the system — the iOS analogue of macOS's `~/Library/Saved Application State/`, though iOS keeps no equivalently-named folder in the app container) and for declared deep-link/Universal-Link routes in the `Info.plist` (`CFBundleURLTypes` for custom schemes; the `com.apple.developer.associated-domains` entitlement for Universal Links). Those declarations enumerate the app's reachable entry points — a useful map of "what external input can drive this app," and a pivot for both triage and capability analysis ([[00-app-sandbox-and-filesystem-layout]], [[13-notifications-keyboard-and-misc-stores]]).

### MVVM and the Observation framework (`@Observable`)

The dominant SwiftUI architecture is **MVVM** — a `View` (dumb, declarative), a **view model** holding state and logic, and a **model** (your data/persistence). Since iOS 17 the view model is an `@Observable` class, and this is a *macro*, not a protocol-conformance-by-hand. Understanding the macro expansion matters because it is exactly what you see in a disassembly.

**The old way** (`ObservableObject` + `@Published` + `@ObservedObject`/`@StateObject`) wrapped each property in a `Published.Publisher` and republished the *whole object* on any change — every observing view re-rendered when *any* property changed.

**The `@Observable` macro** (the `Observation` framework) is finer-grained. At compile time the macro:

1. Conforms the class to the `Observation.Observable` protocol.
2. Adds a stored `private let _$observationRegistrar = ObservationRegistrar()`.
3. Rewrites each stored property into a computed property whose **getter calls `access(self, keyPath:)`** and whose **setter wraps the write in `withMutation(of:keyPath:)`**, with the real value moved to an `@ObservationIgnored` backing field.

SwiftUI's `body` evaluation runs inside `withObservationTracking { … } onChange: { … }`, so a view only subscribes to the *exact* key paths its `body` actually read. Change a property no visible view read → **no re-render**. That's the performance story, and it's also a *reversing* story: the synthesized `access`/`withMutation` calls and the `ObservationRegistrar` field are visible in the binary, so an `@Observable` model is recognizable even after stripping.

In views you bind to it with `@State` (the view *owns* the instance), `@Bindable` (two-way bindings into a passed-in `@Observable`), and `@Environment` (dependency-injected). There is no more `@StateObject`/`@ObservedObject` for new code. The full property-wrapper vocabulary, and which era each belongs to:

| Wrapper | Holds | Era | Use |
|---|---|---|---|
| `@State` | value type *or* `@Observable` instance the view **owns** | both | source-of-truth local to a view; storage lives in the view graph, not the struct |
| `@Binding` | a two-way reference to state owned elsewhere | both | child reads/writes a parent's value |
| `@Bindable` | an `@Observable` passed in, to derive `Binding`s | Observation | `$model.title` bindings into an injected model |
| `@Environment` | a value injected down the tree | both | dependency injection / system values (`\.scenePhase`, `\.colorScheme`) |
| `@StateObject` / `@ObservedObject` | an `ObservableObject` | **legacy** | pre-iOS-17; *will not track `@Observable`* — mixing them is the classic "view won't update" bug |

> 🖥️ **macOS contrast:** This property-wrapper set is identical across iOS and macOS SwiftUI — `@State`/`@Binding`/`@Observable` are the same source on both. The only divergence is the *scene* and *environment* values exposed (e.g. `\.openWindow`, `\.controlActiveState` on macOS), not the state machinery itself.

> 🔬 **Forensics note:** `@Observable` view models are *runtime* state — they don't persist. But the **SwiftData** models they often wrap *do*. SwiftData (`@Model`) is a thin declarative skin over the **Core Data** stack, so on disk it is a SQLite database — by default `default.store` (plus `default.store-wal` / `default.store-shm`) in the app container's `Library/Application Support/`. The schema uses Core Data's classic conventions: tables named `Z<MODELNAME>` (e.g. `ZTASK`), bookkeeping tables `Z_PRIMARYKEY`, `Z_METADATA`, `Z_MODELCACHE`, and `Z`-prefixed columns. Everything you learned about parsing Core Data / Apple SQLite stores (copy-before-query, `-wal` handling, the Mac Absolute Time epoch on date columns) applies unchanged — see [[11-third-party-app-methodology]] and [[00-app-sandbox-and-filesystem-layout]]. The practical upshot: as SwiftData adoption grows through 2026, third-party app stores you triage are increasingly Core-Data-shaped SQLite even when the developer never typed "Core Data."

### SwiftUI's value-type view tree, identity, and AttributeGraph

A UIKit view hierarchy is **retained-mode**: each `UIView` is a long-lived reference object you mutate in place (`label.text = "…"`). A SwiftUI view hierarchy is the opposite — the `struct`s conforming to `View` are *cheap, ephemeral descriptions* recreated constantly; `body` is a (conceptually) pure function from state to a new description. SwiftUI **diffs** the new description against the old and applies only the minimal changes to the real backing layers. This is why a `View` has no stored identity of its own and why mutating a `View` struct's property directly does nothing — the struct is throwaway.

Three mechanics fall out of this and matter for both building and reversing:

- **`@ViewBuilder`** is a result builder (the `buildBlock`/`buildEither`/`buildOptional` family) that turns the declarative body — including `if`/`switch`/`ForEach` — into a single statically-typed, deeply-nested generic return type (`some View`). That opaque return type is why SwiftUI view bodies disassemble into towering generic specializations rather than flat method calls.
- **Identity** decides what "the same view across updates" means. *Structural identity* comes from the view's position in the `@ViewBuilder` tree; *explicit identity* comes from `.id(_:)` and `ForEach`'s `id:`. Identity controls state lifetime and transitions — get it wrong and `@State` resets or animations break.
- **Where `@State` actually lives.** The value is **not** stored in the struct (which is recreated every update). SwiftUI stores it in a persistent side table — the **view graph**, backed by the private **`AttributeGraph`** framework (a dependency graph / incremental-computation engine). `@State` is a handle into that graph; `@Observable` tracking, `@Environment` propagation, and `body` re-evaluation are all graph node invalidations.

> 🔬 **Forensics / RE note:** `AttributeGraph` is the strongest *positive* SwiftUI fingerprint in the load commands — `otool -L` on any SwiftUI app lists `/System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph` alongside `SwiftUI.framework`. Because the view graph is opaque private state, you cannot recover a SwiftUI screen's *runtime* tree the way you'd dump a UIKit `UIView` hierarchy with `recursiveDescription`; static recovery falls back to the `__swift5_*` type/conformance data. Presence of `AttributeGraph` + `SwiftUI` + a barren Obj-C class list is the high-confidence "SwiftUI app" triple.

> 🖥️ **macOS contrast:** Same `AttributeGraph` engine backs SwiftUI on macOS — it is the cross-platform heart of SwiftUI's reactivity, independent of UIKit/AppKit. AppKit itself, like UIKit, remains retained-mode (`NSView` you mutate in place); only the SwiftUI layer is graph-driven.

### Concurrency in the UI layer: `@MainActor` and structured concurrency

Modern iOS architecture is also a *concurrency* architecture. The UI layer is **main-actor-isolated**: `UIView`, `UIViewController`, the SwiftUI `View` protocol, and `@Observable` view models are (by inference or annotation) `@MainActor`, meaning their methods and stored properties may only be touched from the main actor's executor. Background work is structured concurrency — `async`/`await`, `Task { }`, `TaskGroup`, `async let` — and results hop *back* to the main actor (`await MainActor.run { … }` or simply calling a `@MainActor` method) before mutating UI state.

Under **Swift 6 strict concurrency** (the default since Swift 6.0; the toolchain here is 6.3) this isolation is *compiler-enforced*: crossing an actor boundary requires `Sendable` types, and a data race that used to be a runtime crash is now a build error. Architecturally this pushes apps toward a clean split — `@MainActor` view models holding UI state, `actor`-isolated or `Sendable` services doing I/O — which is exactly the MVVM boundary above, now with teeth.

> 🔬 **Forensics / RE note:** Concurrency leaves runtime-call fingerprints. The Swift concurrency runtime (`libswift_Concurrency.dylib`, also in the dyld shared cache) exposes symbols like `swift_task_create`, `swift_task_switch`, and `swift_job_run`; main-actor hops compile to `swift_task_switch` onto the `MainActor.shared` executor. A binary dense in these calls is doing structured concurrency; their *absence* in a UI-heavy app suggests an older GCD/`DispatchQueue.main.async` codebase. When instrumenting with Frida, an `await` is not a single call you can trivially hook — the function is split into a state machine across continuation resume points, so name-based hooks land on the *partial* functions, not the logical method.

### The RE hook — what each architecture writes into the Mach-O

This is the payoff. The Swift compiler emits **reflection and type metadata** into a family of sections inside the `__TEXT` segment, and the Obj-C compiler emits class metadata into `__DATA`/`__DATA_CONST`. Reading which sections are populated, and how, classifies a binary before you disassemble anything.

**The Swift metadata sections** (all in `__TEXT`, each an array of 32-bit *relative* pointers to descriptor structures elsewhere in the binary):

| Section | Contents |
|---|---|
| `__swift5_types` | **Type context descriptors** — one per nominal type (every `struct`/`class`/`enum`). The master list of "what types this binary defines." |
| `__swift5_proto` | **Protocol conformance descriptors** — one per *type↔protocol* pair. This is where `: View`, `: App`, `: Observable` conformances live. |
| `__swift5_protos` | **Protocol descriptors** — protocols the binary *defines*. |
| `__swift5_fieldmd` | **Field descriptors** — stored-property names and types (reflection). The richest source for recovering a `struct`'s shape. |
| `__swift5_reflstr` | Reflection **strings** (field/type names referenced by `__swift5_fieldmd`). |
| `__swift5_typeref`, `__swift5_assocty`, `__swift5_capture`, `__swift5_builtin`, `__swift5_mpenum` | Type references, associated-type witnesses, closure-capture layouts, builtin and multi-payload-enum descriptors. |

**The Obj-C metadata sections** (modern toolchains place the read-only ones in `__DATA_CONST`):

| Section | Contents |
|---|---|
| `__objc_classlist` | Pointer list of every **Obj-C-visible class** the binary defines. |
| `__objc_classrefs` / `__objc_superrefs` | Classes/superclasses referenced. |
| `__objc_selrefs` / `__objc_methname` (in `__TEXT`) | Referenced selectors / method-name strings. |
| `__objc_protolist`, `__objc_catlist`, `__objc_ivar` | Protocols, categories, ivars. |

Now the classification heuristics — **the part you actually use**:

```
Pure-Swift CLI / logic-only binary
   __swift5_types  : POPULATED        __objc_classlist : empty / tiny
   no UIKit, no SwiftUI in LC_LOAD_DYLIB

UIKit app
   __swift5_types  : POPULATED        __objc_classlist : POPULATED  ← UIViewController/UIView
                                                                       subclasses ARE Obj-C classes
   LC_LOAD_DYLIB   : UIKit            Info.plist       : UIApplicationSceneManifest,
   imports _UIApplicationMain                            often UILaunchStoryboardName / Main.storyboardc

SwiftUI app
   __swift5_types  : POPULATED        __objc_classlist : sparse  ← Views are STRUCTS, no Obj-C class
   __swift5_proto  : conformances to SwiftUI.View / SwiftUI.App / SwiftUI.Scene
   LC_LOAD_DYLIB   : SwiftUI (+ UIKit underneath)
   no _UIApplicationMain; synthesized main → SwiftUI runner
```

The load-bearing insight: **a SwiftUI `View` is a `struct`, and structs are not Obj-C classes.** So a screen built in SwiftUI emits a `__swift5_types` descriptor and a `__swift5_proto` conformance to `SwiftUI.View` — but **nothing** in `__objc_classlist`, and **no `@objc` selectors** you could hook by name. The same screen in UIKit is a `UIViewController` subclass: it appears in `__objc_classlist` with a mangled Swift class name (`_TtC6MyApp14DetailVC`-style or the `$s`-prefixed form), exposes its action methods as Obj-C selectors, and is hookable by name with Frida's `ObjC` API. This is *why* SwiftUI apps are harder to instrument dynamically (you fall back to Swift-interpose / `swift_*` runtime hooks, covered in [[05-dynamic-analysis-with-frida]] and [[04-static-analysis-class-dump-and-disassemblers]]) and why class-dumping a SwiftUI app yields almost nothing useful from the Obj-C side.

A second tell: anything a Swift class marks `@objc`/`@objcMembers`, or that subclasses `NSObject`, *re-enters* the Obj-C class list. So classic `NSManagedObject` subclasses (Core Data with `@objc(Entity)` codegen) and `@objc` view models show up Obj-C-side even in an otherwise "pure Swift" binary. **Note the SwiftData counterexample:** a `@Model` class is *not* `NSObject`-derived — it's a plain Swift class the macro conforms to `SwiftData.PersistentModel`/`Observation.Observable`, so it lands in `__swift5_types`/`__swift5_proto` (recognizable by its `PersistentModel` conformance) and **not** in `__objc_classlist`; its Core Data `NSManagedObject` backing is materialized dynamically at runtime (wrapped in `_DefaultBackingData`), never emitted as a static class in your binary. The presence of a handful of `@objc` classes amid rich `__swift5_*` data is itself a fingerprint of "modern Swift app that touches an Obj-C-backed framework."

**Reading the mangled names.** Modern Swift symbols start with `$s` (older: `_T0`); the `__swift5_*` descriptors reference the same mangled type names. You don't decode them by hand — pipe to `xcrun swift-demangle` — but a few prefixes let you classify symbols at a glance because the module name is length-prefixed:

| Mangled fragment | Meaning |
|---|---|
| `$s7SwiftUI…` | a symbol in the **SwiftUI** module (`7` = length of "SwiftUI") |
| `$s5UIKit…` | a symbol in the **UIKit** module |
| `$s…V` / `$s…C` / `$s…O` | the type-kind suffix: **V**alue type (struct), **C**lass, or `O` = enum (an arbitrary letter, not mnemonic) |
| `$s7SwiftUI4ViewP` / `…Mp` | the SwiftUI `View` **P**rotocol / a protocol descriptor (`Mp`) |
| `…4bodyQrvp` | a `body` property returning an opaque (`Qr`) result — the SwiftUI view-body tell |

So in a conformance dump, a `__swift5_proto` record whose protocol demangles to `SwiftUI.View` and whose conforming type is a struct (`…V`) in *your app's* module is, unambiguously, an app-defined SwiftUI screen — recovered with zero Obj-C metadata.

> ⚖️ **Authorization:** Statically reading these sections in *your own* builds or in OS frameworks is unrestricted. The moment you analyze a **third-party App Store binary** you hit two gates: the binary is **FairPlay-encrypted** (the `__TEXT` you'd parse is ciphertext until decrypted on a device — see [[03-fairplay-encryption-and-decrypting-app-store-apps]]), and decrypting/reverse-engineering someone else's app may breach the App Store license and anti-circumvention law (DMCA §1201; analogous regimes elsewhere). Keep RE work to binaries you authored, OS components, or images you are lawfully authorized to examine.

> 🔬 **Forensics note:** Architecture fingerprinting is triage, not just curiosity. Before allocating hours to an unknown app in an investigation, `otool`/`jtool2` the Mach-O: a populated `__objc_classlist` with descriptive class names (`PaymentManager`, `MessageStore`) tells you a `class-dump` will yield a readable class/method map and Frida-by-name hooking will work; a SwiftUI-heavy binary with a barren class list tells you to budget for `__swift5_fieldmd` parsing and Swift-runtime instrumentation instead. The `Info.plist` (`UIApplicationSceneManifest` present? `UILaunchStoryboardName`? `DTPlatformVersion`/`MinimumOSVersion`?) and `LC_LOAD_DYLIB` list date the build and reveal the framework mix in seconds.

## Hands-on

All commands run **on the Mac** — there is no on-device shell. The substrate is a Simulator-built `.app` (unencrypted, real metadata) unless noted.

```bash
# Build a Simulator app, then locate its executable inside the .app bundle.
# (Build in Xcode for the Simulator, or `xcodebuild -sdk iphonesimulator`.)
APP=~/Library/Developer/Xcode/DerivedData/MyApp-*/Build/Products/Debug-iphonesimulator/MyApp.app
BIN="$APP/MyApp"
file "$BIN"
#   MyApp: Mach-O 64-bit executable arm64

# 1) Which UI frameworks are linked? (the fastest first signal)
otool -L "$BIN" | grep -Ei 'UIKit|SwiftUI|AttributeGraph|swiftCore'
#   /System/.../UIKit.framework/UIKit ...
#   /System/.../SwiftUI.framework/SwiftUI ...                       ← declarative UI
#   /System/.../PrivateFrameworks/AttributeGraph.framework/...      ← high-confidence SwiftUI tell
#   /usr/lib/swift/libswiftCore.dylib ...            ← ABI-stable runtime in the OS, not bundled

# 2) Which metadata sections exist, and how big? (Swift-side vs Obj-C-side density)
otool -l "$BIN" | grep -A2 -E 'sectname __swift5_(types|proto|fieldmd)|sectname __objc_classlist'
#   compare the `size` fields: rich __swift5_* + tiny __objc_classlist  → SwiftUI-leaning

# 3) Dump the Obj-C class list (UIKit screens, @objc, NSObject/NSManagedObject subclasses)
#    NOTE: SwiftData @Model classes are plain Swift — they do NOT appear here (see step 4).
#    nm shows the class symbols; otool dumps the raw section.
nm "$BIN" | grep -E '_OBJC_CLASS_\$_' | head
otool -o "$BIN" 2>/dev/null | grep -E 'name ' | head     # parsed Obj-C metadata

# 4) Demangle Swift symbols to read the type/protocol names
nm "$BIN" | grep ' t ' | grep '_\$s' | head
xcrun swift-demangle '$s5MyApp11ContentViewV4bodyQrvp'
#   MyApp.ContentView.body : some   ← a SwiftUI View's body computed property

# 5) Confirm the lifecycle: UIKit apps import UIApplicationMain; SwiftUI apps don't
nm -u "$BIN" | grep -i UIApplicationMain
#   (no output on a pure-SwiftUI app)

# 6) Read the scene manifest + framework dating from the bundle's Info.plist
plutil -extract UIApplicationSceneManifest xml1 -o - "$APP/Info.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :DTPlatformVersion' "$APP/Info.plist"

# 7) Bundle resources corroborate the UI story:
ls "$APP"
#   Main.storyboardc / *.nib / Base.lproj   → storyboard/XIB-driven UIKit
#   (no storyboard, just Assets.car + the binary) → programmatic UIKit or SwiftUI
```

For richer Swift type recovery than `nm`, use a Swift-aware dumper (covered in depth in [[04-static-analysis-class-dump-and-disassemblers]]):

```bash
# Derek Selander's dsdump parses BOTH the Obj-C class list AND the __swift5_* sections.
dsdump --swift --objc --color "$BIN" | head -80
#   prints reconstructed Swift type decls (from __swift5_types/_fieldmd) +
#   the Obj-C class/method map (from __objc_classlist) side by side
```

To watch the `@Observable` macro expand — i.e. see the exact `access`/`withMutation`/`ObservationRegistrar` code you'll meet in a disassembly — expand the macro at the source level:

```bash
# In Xcode: right-click an @Observable type → "Expand Macro".
# Or from the CLI, dump frontend macro expansions:
xcrun swiftc -dump-macro-expansions Model.swift 2>&1 | sed -n '1,60p'
#   shows the synthesized: private let _$observationRegistrar = ObservationRegistrar()
#   and each property rewritten to call access(self, keyPath:) / withMutation(...)
```

A SwiftData store is plain SQLite on disk. On a *running Simulator* the app container is unencrypted on the Mac — find the store and read its Core-Data-shaped schema (copy first, exactly as on macOS):

```bash
# Locate a Simulator app's data container, then its SwiftData store
xcrun simctl get_app_container booted com.example.MyApp data
#   /Users/.../CoreSimulator/Devices/<UDID>/data/Containers/Data/Application/<GUID>
STORE="$(xcrun simctl get_app_container booted com.example.MyApp data)/Library/Application Support/default.store"
ls -l "$STORE"*                       # default.store, default.store-wal, default.store-shm

cp "$STORE"* /tmp/                     # COPY before query — never open the live store
sqlite3 /tmp/default.store '.tables'   # ZTASK, Z_PRIMARYKEY, Z_METADATA, Z_MODELCACHE …
sqlite3 /tmp/default.store 'SELECT name FROM sqlite_master WHERE type="table";'
```

## 🧪 Labs

> All labs are **device-free**. The substrate is a Simulator-built `.app` and/or your own source. **Fidelity caveat:** Simulator binaries carry **identical** Swift/Obj-C metadata sections to device builds, so architecture fingerprinting is faithful. What the Simulator does *not* give you: FairPlay encryption (Simulator apps are plaintext; real App Store binaries are encrypted — [[03-fairplay-encryption-and-decrypting-app-store-apps]]), and the device-only daemons/SEP/Data-Protection are absent (irrelevant here — this lesson is about static binary shape, which the Simulator reproduces exactly).

### Lab 1 — Fingerprint UIKit vs SwiftUI vs Swift-only (Simulator + your own source)

1. Create three minimal targets in Xcode (Simulator destination): (a) a SwiftUI "App" template, (b) a UIKit "App" (Storyboard) template, (c) a Swift command-line tool (or a logic-only framework). Build each.
2. For each executable run the **Hands-on** steps 1–3. Tabulate: Is `SwiftUI` in `otool -L`? Is `_UIApplicationMain` an undefined symbol? Compare the `size` of `__swift5_types` vs `__objc_classlist`.
3. In the SwiftUI binary, `nm | grep _OBJC_CLASS_` — note how few (or zero meaningful) classes appear. In the UIKit binary, find your `ViewController` in the Obj-C class list.
4. Run `dsdump --swift --objc` on the SwiftUI binary and confirm: the screen exists as a `struct … : View` recovered from `__swift5_types`/`__swift5_proto`, with **no** Obj-C method list.
5. Write the three-line decision rule you'd apply to an unknown binary. (Answer key: linked SwiftUI + barren class list + no `UIApplicationMain` ⇒ SwiftUI; populated class list of `*ViewController` + `UIApplicationMain` ⇒ UIKit; no UI dylibs ⇒ logic-only.)

### Lab 2 — Read the `@Observable` macro in the metal (your own source)

1. Write a 3-property `@Observable final class CounterModel` and a SwiftUI view that reads only *one* of its properties.
2. Run `xcrun swiftc -dump-macro-expansions` (or Xcode "Expand Macro") and read the synthesized accessors. Identify the `ObservationRegistrar`, the `access(self, keyPath:)` in each getter, the `withMutation` in each setter, and the `@ObservationIgnored` backing fields.
3. Build for the Simulator and `dsdump --swift` the result; locate the conformance to `Observation.Observable` in `__swift5_proto` and the registrar field in `__swift5_fieldmd`.
4. Reason it through: which view re-renders when you mutate the *unread* property? (None — that's `withObservationTracking` granularity.) Note how this differs from the old `ObservableObject` whole-object republish.

### Lab 3 — Lifecycle archaeology on a sample binary (Simulator app / read-only walkthrough)

1. Take any Simulator-built `.app` (yours, or one from a SwiftUI/UIKit open-source repo built locally — do **not** use an App Store binary; it's FairPlay-encrypted and license-gated).
2. Determine the lifecycle purely from artifacts: `nm -u | grep UIApplicationMain` (present ⇒ UIKit entry); `dsdump --swift | grep -E ': App|: Scene'` (present ⇒ SwiftUI lifecycle); `plutil -extract UIApplicationSceneManifest` on `Info.plist`.
3. If it's UIKit, find the `AppDelegate` and `SceneDelegate` classes in the Obj-C class list and note which one owns the window-level callbacks.
4. Read `MinimumOSVersion` / `DTPlatformVersion`. If `UIApplicationSceneManifest` is **absent**, what does that tell you about the build's age given the iOS 26→27 scene-adoption deadline? (Answer key: it predates enforced scene adoption or is a stale/transitional build — a dating signal.)

### Lab 4 — Dissect a SwiftData store (Simulator)

> **Substrate:** a Simulator-built app that uses SwiftData, populated with a few records, then inspected on the Mac. **Fidelity caveat:** the *schema* and SQL behavior are faithful to a device (SwiftData is the same Core Data stack everywhere), but on a real device the container is Data-Protection-encrypted at rest and only readable in an AFU/decrypted state — the Simulator copy is plaintext, so this teaches *structure/parsing*, not lock-state behavior ([[02-bfu-vs-afu-and-data-protection-classes]]).

1. Build a SwiftData app (a `@Model class Task { … }`), run it on the booted Simulator, add 3–4 records.
2. Use the **Hands-on** `simctl get_app_container` recipe to locate `default.store`; `cp` it (and `-wal`/`-shm`) to `/tmp`.
3. `sqlite3 /tmp/default.store '.schema ZTASK'` — map your Swift property names to `Z`-prefixed columns. Note the `Z_PK`/`Z_ENT` bookkeeping columns and the `Z_PRIMARYKEY`/`Z_METADATA` tables.
4. Convert any date column: SwiftData/Core Data store dates as Mac Absolute Time (seconds since 2001-01-01) — `SELECT datetime(ZCREATEDAT + 978307200, 'unixepoch', 'localtime') FROM ZTASK;`. Confirm against the values you entered. (Same epoch you used throughout `knowledgeC`/Safari analysis.)

> ⚠️ **ADVANCED (device-bound — walkthrough only):** To fingerprint a *real* App Store app you must first defeat FairPlay, which is on-device (dump decrypted pages from a running process on a jailbroken or otherwise instrumented device — `frida-ios-dump`/`bagbak`). That's out of scope here and covered in [[03-fairplay-encryption-and-decrypting-app-store-apps]]; with no physical device, restrict yourself to Simulator builds and OS framework binaries (already plaintext in the shared cache).

## Pitfalls & gotchas

- **"It links UIKit" ≠ "it's a UIKit app."** Every SwiftUI app links UIKit (SwiftUI is built atop it via `UIHostingController`). The discriminator is the **class list density + `SwiftUI` in the load commands + absence of `UIApplicationMain`**, not the mere presence of UIKit.
- **A barren Obj-C class list is not an empty binary.** New reversers see a near-empty `class-dump` on a SwiftUI app and conclude "obfuscated" or "nothing here." The types are all in `__swift5_types`/`__swift5_fieldmd` — use a Swift-aware tool (`dsdump`, `class-dump-swift`, Ghidra's Swift loader), not classic `class-dump`.
- **Whole-module optimization erases your own types harder than the framework's.** App code built non-resilient (the default) is aggressively inlined/specialized, so `__swift5_fieldmd` for app types can be thinner than for the resilient OS frameworks it calls. Don't assume missing reflection = stripping; it may be optimization.
- **`@Observable` is not a drop-in for `ObservableObject` semantics.** In a view, an `@Observable` instance is held with `@State` (owned) or injected with `@Environment`/`@Bindable` — **not** `@StateObject`/`@ObservedObject` (those are for the old `ObservableObject` protocol and silently won't track an `@Observable`). Mixing them is a common "my view doesn't update" bug.
- **Don't read the SwiftData store on the live Simulator without copying.** Same SQLite discipline as every Apple store: `cp` the `default.store` (and `-wal`/`-shm`) first; opening it write-locks and may checkpoint the WAL, altering evidence. The store is Core-Data-shaped (`Z`-tables), not a hand-rolled schema.
- **The scene manifest deadline will silently date your reads.** Through 2026 a non-trivial fraction of binaries still lack `UIApplicationSceneManifest`. After the iOS 27-era enforcement, its absence in a *newly built* binary becomes anomalous. Use it as a dating signal, not a hard rule.
- **Simulator slices aren't device slices.** The Simulator executable is an `arm64` *simulator* binary (different platform load command, no FairPlay). Metadata layout is faithful for fingerprinting, but never present a Simulator binary as if it were the shipped device artifact in a report.
- **`await` is not one hookable function.** Frida/`fishhook` name-based interposition assumes a function is contiguous; under structured concurrency a method is split into partial functions across continuation resume points, so a hook on the symbol catches only the pre-suspension prefix. Reach for Swift-runtime hooks (`swift_task_*`) or instrument the called service instead — see [[05-dynamic-analysis-with-frida]].
- **Touching UI off the main actor used to crash; now it won't compile.** Under Swift 6 strict concurrency, mutating a `@MainActor` view model from a background `Task` is a build error, not a runtime "UI updated on background thread" surprise. When porting older GCD code you'll trade silent races for compiler diagnostics — that's the point, not a regression.

## Key takeaways

- iOS UI is **UIKit (imperative classes)**, **SwiftUI (declarative structs)**, or hybrid; persistence is an orthogonal axis where **SwiftData** (a Core Data skin → SQLite `default.store`) is the 2026 default.
- **ABI stability (Swift 5.0, 2019)** moved the Swift runtime into the OS/dyld shared cache and froze the metadata + mangling contracts — which is precisely what makes static Swift RE tractable.
- Two lifecycles: classic **`UIApplicationMain` → `AppDelegate` (process) → `SceneDelegate` (UI/window)**, and the **SwiftUI `App`/`Scene`** model with `@Environment(\.scenePhase)` and opt-in `@UIApplicationDelegateAdaptor`. iOS 26 warns, iOS 27-era *enforces*, `UIScene` adoption.
- Events route through the **responder chain** (`UIResponder.next`, hit-test down then handle up, first responder for keyboard/`nil`-target actions) — the direct analogue of AppKit's `NSResponder` chain.
- `@Observable` is a **macro**: it synthesizes an `ObservationRegistrar` plus per-property `access`/`withMutation` calls, giving SwiftUI key-path-granular re-rendering — and leaving recognizable code in the binary.
- SwiftUI views are **value-type, throwaway descriptions**; real state lives in the persistent **view graph** (private `AttributeGraph` framework), which is itself a high-confidence SwiftUI fingerprint in the load commands and the reason a SwiftUI runtime tree can't be dumped like a UIKit `UIView` hierarchy.
- **The architecture is a binary fingerprint.** SwiftUI views are structs → `__swift5_types`/`__swift5_proto`, **no** `__objc_classlist` entry, no `@objc` selectors; UIKit views/VCs are `NSObject`-derived → populated `__objc_classlist`, hookable by name. Swift type metadata lives in the `__TEXT.__swift5_*` sections; Obj-C class metadata in `__DATA(_CONST).__objc_*`.
- **The UI layer is main-actor-isolated** and, under Swift 6 strict concurrency, that isolation is compiler-enforced — pushing apps toward a clean `@MainActor` view-model / `Sendable`-service split and leaving `swift_task_*` runtime fingerprints (and `await`-split partial functions that frustrate name-based hooking).
- **Triage before you disassemble:** `otool -L` (frameworks, incl. `AttributeGraph`), section sizes (Swift-vs-Obj-C density), `nm | grep UIApplicationMain` (lifecycle), and the `Info.plist` scene manifest classify and date a binary in seconds.

## Terms introduced

| Term | Definition |
|---|---|
| ABI stability | Frozen Swift calling convention/metadata/mangling (Apple platforms, Swift 5.0, 2019); the runtime ships in the OS, not the app. |
| Module stability | Swift 5.1 textual `.swiftinterface` enabling binary `.xcframework` use across compiler versions; needs library-evolution mode. |
| `UIApplicationMain` | C entry point that boots a UIKit app and wires up the `UIApplicationDelegate`. |
| `UIApplicationDelegate` | Process-level lifecycle delegate (launch, APNs token, memory warnings). |
| `UISceneDelegate` | Per-window (scene) UI lifecycle delegate; owns the `UIWindow` (iOS 13+); enforced by the iOS 27-era SDK. |
| `UIApplicationSceneManifest` | `Info.plist` key declaring an app's scene configuration; a dating/fingerprint signal. |
| `App` / `Scene` (SwiftUI) | Protocols for the SwiftUI lifecycle; `@main` on an `App` struct synthesizes the entry point. |
| `scenePhase` | SwiftUI `@Environment` value (`.active`/`.inactive`/`.background`) replacing background/foreground delegate callbacks. |
| `@UIApplicationDelegateAdaptor` | Property wrapper bridging a UIKit `AppDelegate` into a SwiftUI `App`. |
| Responder chain | Linked list of `UIResponder`s (view→VC→window→app→delegate) up which unhandled events bubble. |
| First responder | The `UIResponder` receiving keyboard input and `nil`-targeted actions. |
| `@Observable` / Observation | iOS 17+ macro/framework giving key-path-granular SwiftUI updates via `ObservationRegistrar` (replaces `ObservableObject`). |
| `@Model` (SwiftData) | Macro marking a persistent model; SwiftData is a Core Data skin storing to SQLite (`default.store`, `Z`-tables). |
| `__swift5_types` | `__TEXT` section listing type context descriptors (every nominal type the binary defines). |
| `__swift5_proto` | `__TEXT` section of protocol conformance descriptors (one per type↔protocol pair; where `: View`/`: App` live). |
| `__swift5_fieldmd` | `__TEXT` section of field descriptors — stored-property names/types for reflection-based type recovery. |
| `__objc_classlist` | `__DATA(_CONST)` section listing every Obj-C-visible class; populated by UIKit subclasses, `@objc`/`@objcMembers` types, and `NSObject`/`NSManagedObject` subclasses — but **not** SwiftData `@Model` classes (those are plain Swift, recovered from `__swift5_*`). |
| `UIHostingController` | UIKit `UIViewController` that hosts a SwiftUI view hierarchy — the bridge that makes SwiftUI apps run on UIKit. |
| `@ViewBuilder` | Result builder turning a declarative `body` (with `if`/`switch`/`ForEach`) into one nested `some View` opaque type. |
| View graph / AttributeGraph | The persistent dependency-graph engine (private framework) that stores `@State` and drives SwiftUI re-evaluation; a SwiftUI binary fingerprint. |
| Structural identity | A SwiftUI view's identity derived from its position in the `@ViewBuilder` tree (vs. explicit identity from `.id(_:)`); governs state lifetime. |
| `NavigationStack` | Value-based SwiftUI navigation: a bound `path` array + `.navigationDestination(for:)`; the modern replacement for `UINavigationController` push/pop. |
| Swift name mangling | The `$s`-prefixed (legacy `_T0`) symbol encoding; length-prefixed module names (`7SwiftUI`, `5UIKit`) and type kind suffixes (`V`/`C`/`O`) decoded with `swift-demangle`. |
| `@MainActor` | Actor isolation pinning a type/method to the main executor; UIKit/SwiftUI UI types are main-actor-isolated, enforced under Swift 6 strict concurrency. |
| Structured concurrency | `async`/`await` + `Task`/`TaskGroup`; compiles to a continuation state machine, backed by `libswift_Concurrency.dylib` (`swift_task_*` symbols). |

## Further reading

- Apple — TN3187 *Migrating to the UIKit scene-based life cycle*; *App* and *Scene* protocol docs; *Managing model data in your app*; *Migrating from the Observable Object protocol to the Observable macro*; the `Observation` framework reference (developer.apple.com).
- Apple — *Swift ABI Stability Manifesto* and *ABI Stability and More* (swift.org/blog); the Swift 6.3 release notes (swift.org/blog, 2026-03-24).
- Apple — *Migrating to the structured concurrency* / Swift concurrency docs; the SwiftUI *NavigationStack* and *Data Essentials in SwiftUI* sessions (WWDC, developer.apple.com/videos).
- Apple — *Documentation Archive: View Controller Programming Guide* and *Event Handling Guide* (the responder chain and hit-testing, still authoritative on UIKit mechanics).
- Jonathan Levin — *MacOS and iOS Internals* (Mach-O segments/sections, dyld shared cache); newosxbook.com / `jtool2`.
- Scott Knight — "Swift metadata" (knight.sc) — the canonical write-up of the `__swift5_*` descriptor layout.
- Derek Selander — `dsdump` (Swift + Obj-C section dumping) and *Advanced Apple Debugging & Reverse Engineering* (Kodeco).
- Emerge Tools — "The Surprising Cost of Protocol Conformances in Swift" (`__swift5_proto` at scale).
- objc.io — *Thinking in SwiftUI* (identity, the value-type view tree, dependency tracking); SwiftRocks — Swift metadata/runtime internals write-ups.
- `frida/frida-swift-bridge` (Mach-O Swift section parsing); `MxIris-Reverse-Engineering/MachOSwiftSection`; doronz88/`swift_reversing`.
- man pages: `otool(1)`, `nm(1)`, `swift-demangle(1)`, `plutil(1)`, `sqlite3(1)`.
- OWASP MASTG — iOS static-analysis chapters (class-dump / Swift type recovery workflow).

---
*Related lessons: [[00-ios-xcode-and-the-build-system]] | [[03-app-lifecycle-scenes-and-background-execution]] | [[04-the-app-bundle-and-ipa-structure]] | [[04-static-analysis-class-dump-and-disassemblers]] | [[00-mach-o-arm64-deep-dive]] | [[05-dynamic-analysis-with-frida]] | [[11-third-party-app-methodology]]*
