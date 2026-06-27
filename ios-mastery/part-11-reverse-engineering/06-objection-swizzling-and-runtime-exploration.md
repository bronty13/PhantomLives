---
title: "objection, swizzling & runtime exploration"
part: "11 — Reverse Engineering & App Security"
lesson: 06
est_time: "45 min read + 20 min labs"
prerequisites: [dynamic-analysis-with-frida]
tags: [ios, re, objection, swizzling, runtime, app-security]
last_reviewed: 2026-06-26
---

# objection, swizzling & runtime exploration

> **In one sentence:** objection is a pre-built Frida agent with a pentest shell — `ios keychain dump`, `ios sslpinning disable`, `ios hooking watch class`, `file download` — that turns the runtime-instrumentation primitives you learned in Frida into one-line operations, and underneath every one of those lines is the same trick: rewriting the Objective-C runtime's selector→IMP table at runtime (method swizzling), the late-binding mechanism that makes Cocoa hookable in the first place.

## Why this matters

You finished [[dynamic-analysis-with-frida]] able to write an agent: resolve a method, `Interceptor.attach`, capture args, `retval.replace`. That's the right depth for a *custom* question. But 80% of a mobile assessment is the same handful of *standard* questions — "what's in the keychain?", "what does the app write to its container?", "is there pinning, and can I turn it off?", "which class gates the premium feature?" — and re-deriving each one from raw GumJS is wasted motion. **objection** is the answer: a Frida-built toolkit that ships those questions as commands, so you spend your scripting budget on the bespoke parts.

But objection is not magic, and a top-1% RE doesn't stop at "I ran `ios sslpinning disable` and it worked." Every objection command is a Frida hook, and almost every iOS Frida hook on Cocoa code is, at bottom, **method swizzling** — swapping the implementation a selector resolves to. Understand swizzling at the runtime level and you understand (a) how objection and Frida actually instrument an app, (b) how to write a hook by hand when objection's pre-built one misses, (c) how an app *detects* that its methods were swapped, and (d) the entire jailbreak-tweak ecosystem ([[tweak-development-with-theos]]), which is swizzling shipped as a dylib. This lesson is the bridge from "I can hook a method" to "I know what hooking *is*."

> ⚖️ **Authorization:** objection lowers the effort of dumping a keychain, lifting cookies, and defeating pinning to a single line — which makes scope discipline *more* important, not less. Run it only against software you own, wrote, or are contractually engaged to test (a signed pentest, your employer's app, an OWASP crackme, an authorized malware/stalkerware exam). `ios keychain dump` against a third party's app reads their secrets; `ios sslpinning disable` circumvents a technical protection measure (DMCA §1201 / CFAA exposure). In casework it is **live acquisition** — it modifies the running process — so it never touches a seized original; you instrument a forensic copy on your own hardware and log the objection version, the agent, and every command. The output is evidence; the method must be reproducible.

## Concepts

### objection is a Frida agent with a shell

objection is not a separate instrumentation engine. It is a **Python CLI** (`pip install objection`) that wraps Frida and ships a single large, pre-compiled **TypeScript Frida agent** (the "objection agent"). The architecture is exactly the host/agent split you already know, with objection occupying the *host* role and pre-writing the *agent* for you:

```
┌──────────────────────── your Mac (host) ────────────────────────┐
│  objection (Python CLI + REPL)                                   │
│    │ uses ▼                                                      │
│  frida (frida-core / frida-tools)  ── device mgr, session, RPC   │
│    │ injects ▼                                                   │
└────┼─────────────────────────────────────────────────────────────┘
     ▼
┌──────────────── target process (Simulator app / device app) ────┐
│  GumJS  ◄── objection's bundled agent.js (one big agent)         │
│             exposes rpc.exports: dumpKeychain(), iosSslPin(),    │
│             hookClass(), memDump(), fileDownload(), …            │
│  frida-gum  →  Interceptor / ObjC bridge / Memory / Module       │
└──────────────────────────────────────────────────────────────────┘
```

When you type `ios keychain dump`, objection's REPL calls an **`rpc.exports`** function on its in-process agent (the `send`/`recv`/`rpc` channel from the Frida lesson). The agent runs a pre-written `SecItemCopyMatching` query loop, serializes the results, and ships them back over the message channel; objection's Python side tabulates them. **Every objection command is a thin Python front-end over an RPC call into a Frida agent.** This is why the Frida lesson called objection "`frida-trace` with a pre-built ObjC agent under the hood" — it is literally that, generalized to a few dozen commands.

Two consequences fall out immediately:

- **objection inherits Frida's injection models.** It has no way into a process that Frida doesn't. Jailbroken device → it rides `frida-server`. Non-jailbroken device → it needs the **gadget** baked into a re-signed app (objection automates this with `patchipa`). Simulator → it attaches to the native macOS process. Same three roads as [[dynamic-analysis-with-frida]].
- **objection inherits Frida's limits and version coupling.** Pure-Swift surface is as hard for objection as for raw Frida; the host objection/Frida must be version-compatible with the gadget/`frida-server`; and anything that detects Frida detects objection (it *is* Frida).

> 🖥️ **macOS contrast:** objection's nearest macOS cousin in spirit is the lldb-plus-Python tooling you'd glue together for a Mac app triage — but there's no single "objection for macOS" because on the Mac you can usually just `frida -n <app>` and script directly, or insert a dylib. On iOS the value of objection is that it pre-solves the *injection-constrained* common cases (keychain, container files, pinning) that are annoying to reach through the sandbox. The agent it injects is the very Frida-compile/TypeScript bundle you learned to build in the Frida lesson — objection just maintains a big one so you don't have to.

### How objection gets in: patchipa and the gadget pipeline

On a non-jailbroken device — the realistic 2026 case, since there is **no public kernel jailbreak for A12+ on iOS 18/26** ([[the-jailbreak-landscape-2026]]) — objection's headline feature is **`objection patchipa`**: it automates the entire FridaGadget-embedding pipeline ([[the-app-bundle-and-ipa-structure]], OWASP **MASTG-TECH-0090**) that you'd otherwise do by hand:

```
objection patchipa  -s MyApp.ipa  -c "<codesigning identity SHA-1 or name>"
  └─ does, in order:
  1. unzip the IPA → Payload/MyApp.app/
  2. download the matching FridaGadget.dylib (frida's GitHub releases;
     --gadget-version/-V to pin) into MyApp.app/Frameworks/FridaGadget.dylib
  3. add an LC_LOAD_DYLIB load command to the main Mach-O — via Tyilo's
     insert_dylib (--strip-codesig --inplace) — pointing at
     @executable_path/Frameworks/FridaGadget.dylib  (so dyld loads it)
  4. (only if you pass --gadget-config/-C) copy a FridaGadget.config into
     Frameworks/; otherwise the gadget uses its default: listen on 127.0.0.1:27042
  5. re-sign every bundled .dylib (codesign -f) AND the whole .app
     (applesign --mobileprovision <profile> --clone-entitlements) with your -c id
  6. repackage → MyApp-frida-codesigned.ipa
```

You then install the resulting `MyApp-frida-codesigned.ipa` (Xcode, `ios-deploy`, Sideloadly, or — for the no-cert path — a CoreTrust-class loader like TrollStore on ≤ iOS 17.0, see [[trollstore-and-the-coretrust-bug]]), launch it, and connect with `objection explore`. At launch, `dyld` honors the new `LC_LOAD_DYLIB`, maps `FridaGadget.dylib` into the app's *own* sandbox, and the gadget opens a Frida server **inside the process** — no foreign task port, no `frida-server`, no jailbreak. The cost is that you need a re-signable IPA and a signing identity, and you only instrument *that one app*.

The `FridaGadget.config` interaction mode is the same three-way choice from the Frida lesson: `listen` (default — wait for objection to connect inbound), `connect` (the app reverse-connects out to your host), and `script` (run a bundled `.js` at startup, fully autonomous). With no flags, `patchipa` ships **no config at all** and the gadget falls back to its built-in default (listen on `127.0.0.1:27042`) — which is exactly what `objection explore` then attaches to; pass `--gadget-config`/`-C` to supply a custom config (e.g. `connect` mode) or `--script-source`/`-l` to bake in a startup script. (There is **no** `patchipa -N` flag — `-N`/`--network` is a top-level `objection` connection option, not a `patchipa` one.)

> ⚠️ **ADVANCED — device path only; no device here.** Steps 3–5 modify and re-sign a signed binary. On a device this is the only non-jailbreak way in, but it (a) requires a paid Apple signing identity + provisioning profile, (b) **changes the binary**, so any anti-tamper that checksums the Mach-O or checks the Team ID will fire ([[anti-tamper-pinning-and-detection-both-sides]]), and (c) re-signing with a free 7-day cert means the app dies in a week. You have no device, so `patchipa` is a **read-only walkthrough** for you (Lab 6). The transferable skill — what `LC_LOAD_DYLIB` injection *is*, why dyld honors it, why it needs a re-sign — you already have from [[mach-o-arm64-deep-dive]] and [[code-signing-and-provisioning-in-depth]].

> 🖥️ **macOS contrast — why iOS needs a gadget at all.** On macOS you hook a Cocoa app the lazy way: write a swizzling dylib and force-load it with `DYLD_INSERT_LIBRARIES=hook.dylib /Applications/Target.app/Contents/MacOS/Target` (the SIMBL / `mach_inject` / "insert_dylib" lineage). **That env var does nothing on iOS.** AMFI + **library validation** (`CS_REQUIRE_LV`) refuse to map any dylib not signed by the *same Team ID* as the main binary; the hardened runtime + the app sandbox block foreign-code loading outright; and `dyld` on iOS ignores `DYLD_*` insertion for platform/App-Store binaries. So you cannot inject a hooking dylib by setting an environment variable — you must either take the task port from a privileged `frida-server` (needs a jailbreak), or **make the dylib part of the bundle and re-sign so it passes library validation** (the gadget). objection's `patchipa` *is* the iOS replacement for `DYLD_INSERT_LIBRARIES`. (On macOS you already saw this tightening: `DYLD_INSERT_LIBRARIES` is itself ignored for hardened-runtime/SIP binaries unless they carry `com.apple.security.cs.allow-dyld-environment-variables` and disable library validation — iOS just takes it to the limit. See [[code-signing-amfi-entitlements]], [[the-sandbox-and-tcc]].)

For **this course**, the path is the Simulator: a Simulator app is a native arm64 macOS process you own, so objection attaches over Frida's **local** device (the host) — `objection --local -n "<App>" explore` — with **no gadget and no device** (Labs 1–5). The `--local`/`-L` flag is the one that tells objection to target a process on this Mac rather than hunt for a USB device; `-n`/`--name` names the target. (Heads-up for older writeups: the `-g`/`--gadget` flag you'll see everywhere is now *deprecated* and aliased to `-n`/`--name`.)

### The objection command surface

Once attached (`objection --local -n <target> explore` on the Simulator), you're in a REPL. The commands group into families; the ones that matter for iOS:

| Family | Representative commands | What it does |
|---|---|---|
| **Orientation** | `env` · `ios bundles list_frameworks` · `ios info binary` | App's on-disk paths (Bundle / Documents / Library / tmp), loaded frameworks, the binary's entitlements + encryption + PIE/ARC flags |
| **Filesystem** | `ls` · `cd` · `pwd print` · `file download <r> <l>` · `file upload <l> <r>` · `file cat <r>` | Walk and exfiltrate the app's sandbox container ([[app-sandbox-and-filesystem-layout]]) |
| **Keychain** | `ios keychain dump` · `ios keychain dump --json kc.json` · `ios keychain add/clear` | `SecItemCopyMatching` over every `kSecClass*`; shows account, service, accessible-class, data |
| **Storage** | `ios nsuserdefaults get` · `ios cookies get` · `ios nsurlcredentialstorage dump` · `ios plist cat <f>` | Dump `NSUserDefaults`, the shared `NSHTTPCookieStorage`, `NSURLCredentialStorage`, and pretty-print any binary plist |
| **Hooking** | `ios hooking list classes` · `ios hooking search methods <kw>` · `ios hooking watch class <C>` · `ios hooking watch method '-[C sel:]' --dump-args --dump-backtrace --dump-return` · `ios hooking set return_value '-[C isJailbroken]' false` | Enumerate the runtime and auto-attach `Interceptor` hooks — swizzling, packaged |
| **Memory** | `memory list modules` · `memory list exports <mod>` · `memory search <pat> --string` · `memory dump from_base <b> <sz> out.bin` · `memory dump all out.bin` · `memory write <addr> <data>` | The `Module`/`Memory` primitives as commands |
| **Bypasses** | `ios sslpinning disable` · `ios jailbreak disable` · `ios jailbreak simulate` · `ios ui biometrics_bypass` | Pre-built hooks that neutralize (or fake) pinning, JB detection, and `LAContext` local auth |
| **Monitors** | `ios pasteboard monitor` · `ios monitor crypto` | Poll `UIPasteboard`; trace CommonCrypto calls live |
| **UI** | `ios ui dump` · `ios ui screenshot s.png` · `ios ui alert` | Dump the view hierarchy / grab a screenshot / pop an alert |
| **Custom + jobs** | `import myhook.js` · `jobs list` · `jobs kill <uuid>` | Load *your own* Frida script when a pre-built command misses; every watch/hook is a manageable background **job** |

The two you'll reach for first are `env` (to learn the container layout for filesystem triage) and `ios hooking search classes <keyword>` (to find the class that gates the behavior you care about, without opening a disassembler). The `import` command is the escape hatch: when objection's pre-built hook doesn't fit, you drop to a hand-written agent — back to [[dynamic-analysis-with-frida]] — inside the same session.

Two operational details that bite first-timers. First, **every hook is a `job`**: `ios hooking watch …`, `set return_value`, `sslpinning disable`, and the monitors all register a background job that keeps running until you `jobs kill <uuid>`; forget this and you'll have a dozen overlapping hooks flooding the console and not understand why output is noise. `jobs list` is your hook inventory; treat it like a job table. Second, objection (v1.12.4+, 2026) added **`reconnect` / `reconnect_spawn`** so a session survives the target crashing or relaunching — important because aggressive hooking (or the app's own anti-tamper killing itself) frequently restarts the process mid-assessment, and you don't want to re-drive the whole setup by hand.

> 🔬 **Forensics note:** Treat objection as a *triage console* over an authorized forensic copy (an extracted IPA re-signed with the gadget on your analysis device, or the app run in the Simulator). The storage family is where apps stash the evidence: `ios keychain dump` recovers tokens/credentials/keys an at-rest image only shows as ciphertext; `ios nsurlcredentialstorage dump` and `ios cookies get` lift session credentials; `ios nsuserdefaults get` and `ios plist cat` surface config, last-user, feature flags, and sloppily-stored secrets; `file download` pulls the app's SQLite/Realm/plist containers for offline parsing ([[third-party-app-methodology]]). Because it's live acquisition, record the objection version (`objection version`), the Frida version, the bundle ID + version + binary UUID, and a transcript of every command — an undocumented `set return_value` is indistinguishable later from tampering.

### What `ios sslpinning disable` actually hooks

"Bypass pinning" sounds like one thing; it's really a *battery* of hooks objection installs at once, because pinning is implemented at several layers ([[certificate-pinning-and-bypass]]). objection's agent descends directly from **SSL Kill Switch 2** — its design choice is to attack the TLS stack *below* the app's own trust logic rather than to hook `SecTrustEvaluateWithError` (the function most *hand-written* bypass scripts target). What it actually installs (see `agent/src/ios/pinning.ts`):

- **Legacy Secure Transport** — `SSLCreateContext` / `SSLHandshake` / `SSLSetSessionOption`, used to force `kSSLSessionOptionBreakOnServerAuth` so the *app* (not the system) owns the trust decision, then to make that decision succeed.
- **`Network.framework` / libnetwork TLS** — the internal `tls_helper_create_peer_trust` and `nw_tls_create_peer_trust`, which build the `SecTrust` used for peer verification; neutralizing them defeats `URLSession` pinning at the transport level.
- **BoringSSL** — `SSL_set_custom_verify` (falling back to `SSL_CTX_set_custom_verify`), re-pointed at a verify callback that returns success (`0`), plus a faked `SSL_get_psk_identity`; this catches pinning that bypasses the Apple TLS layers entirely.
- **The `NSURLSession` delegate path** — `-[* URLSession:didReceiveChallenge:completionHandler:]` (matched across every class by `ApiResolver`), answered with `NSURLSessionAuthChallengeUseCredential` + an `NSURLCredential` built from the server's own trust.
- **Popular pinning libraries, by class/selector when present** — AFNetworking's `AFSecurityPolicy` (`setSSLPinningMode:`, `setAllowInvalidCertificates:`, `policyWithPinningMode:`), TrustKit's `-[TSKPinningValidator evaluateTrust:forHostname:]`, and the Cordova `SSLCertificateChecker` plugin's `-[CustomURLConnectionDelegate isFingerprintTrusted:]`.

That breadth is exactly why a one-liner beats a hand-rolled script for the *common* case, and exactly why it sometimes *fails*: an app with a custom, in-app pin comparison (e.g., hashing the leaf SPKI itself and `memcmp`-ing the result) sits below all of these, and you're back to `import`-ing a targeted hook you wrote after finding the comparison in the disassembler. It also does **not** hook `SecTrustEvaluateWithError` directly — so an app whose pin logic funnels only through there may need the hand-written `SecTrust` hook many blog scripts use. objection gets you most of the way; the last mile is the RE.

### Biometric bypass: a worked example of why the common cases are pre-built

`ios ui biometrics_bypass` is a clean illustration of an objection command as a thin wrapper over a swizzle. Apps gate sensitive flows behind `LocalAuthentication` — `LAContext.evaluatePolicy(_:localizedReason:reply:)` (Touch ID / Face ID). The *naïve, broken* pattern many apps use is a **local-only** check: call `evaluatePolicy`, and in the `reply` block branch on the `success` boolean to unlock — with no server-side confirmation and no cryptographic binding. objection's bypass hooks both `-[LAContext evaluatePolicy:localizedReason:reply:]` *and* `-[LAContext evaluateAccessControl:operation:localizedReason:reply:]`, captures the app's `reply` block, and **invokes it with `success = YES, error = nil`** — so the app behaves as though biometric auth passed, without any biometric ever happening. That's the whole trick: swizzle the auth entry point, call the success path yourself.

The lesson for both sides: this only works because the app trusted a boolean. The *correct* pattern binds biometrics to a key in the Secure Enclave-backed keychain via `kSecAccessControlBiometryCurrentSet` / `SecAccessControlCreateWithFlags`, so the protected secret is *only decryptable* after a real biometric match ([[keychain-on-ios]], [[biometrics-security-architecture]]) — there's no boolean to flip, because the gate is the SEP releasing a key, not app code branching. A builder who reads this lesson designs the second way; an RE who reads it knows the first way is one objection command away. (Caveat: on the **Simulator** there's no SEP and biometrics are an enrollment toggle in the Features menu, so this bypass is a *runtime-mechanics* demo, not a real defeat.)

### objection vs. a hand-written agent: when to reach for each

| Situation | Reach for | Why |
|---|---|---|
| Standard recon — keychain, defaults, cookies, container files, frameworks, entitlements | **objection** | One line; the agent's already written and battle-tested |
| Common pinning / JB / biometric gate | **objection** | The battery-of-hooks commands cover the usual implementations |
| A bespoke check below the standard layer (custom SPKI compare, obfuscated gate) | **hand-written agent** (`import`) | Pre-built hooks miss it; you found the exact address/selector statically |
| Pure-Swift, value types, mangled symbols | **hand-written agent** | objection enumerates the *ObjC* runtime; Swift needs the Swift bridge / symbols |
| Repeatable, version-controlled, court-defensible capture | **hand-written agent** (frida-compile) | A hashed, reviewed `.ts` agent is more reproducible than a REPL transcript |
| Fast triage to *decide* what's worth scripting | **objection** | `ios hooking search` maps the surface before you open a disassembler |

The mature workflow uses **both in one session**: objection to orient and knock out the standard questions, `import` to drop a precise hand-written swizzle for the one thing it can't reach. They are not competitors — objection *is* a Frida agent, and `import` puts your agent alongside it.

### Method swizzling: the runtime mechanism under all of it

Here is the foundation. Objective-C does **not** call methods by a fixed address baked in at compile time. Every `[obj doThing:x]` compiles to `objc_msgSend(obj, @selector(doThing:), x)`, and `objc_msgSend` performs a **dynamic lookup at send time**: it takes the object's class, walks the class's method cache (then its method list, then up the superclass chain) to map the **selector** (`SEL`, an interned string key) to an **`IMP`** (the actual function pointer, typed `id (*)(id self, SEL _cmd, ...)`), and tail-calls it. Late binding through a mutable table is the whole game: **if you can rewrite which `IMP` a selector resolves to, you've hooked the method** — for every caller, everywhere, with no caller-side change.

That rewrite is **method swizzling**, and the Objective-C runtime (`/usr/lib/libobjc.A.dylib`) exposes it directly:

| Runtime function | Effect |
|---|---|
| `class_getInstanceMethod(cls, sel)` → `Method` | Look up the `Method` struct (a `{SEL, IMP, types}` triple) |
| `method_getImplementation(m)` → `IMP` | Read the current function pointer |
| `method_setImplementation(m, imp)` → old `IMP` | Point a `Method` at a new `IMP`, return the old one |
| `method_exchangeImplementations(m1, m2)` | **Atomically swap** the two `Method`s' `IMP`s |
| `class_addMethod(cls, sel, imp, types)` → `BOOL` | Add a brand-new method to a class |
| `class_replaceMethod(cls, sel, imp, types)` → old `IMP` | Add-or-replace in one call |

The canonical, *correct* swizzle — done in `+load` (which the runtime calls exactly once, before `main()`, single-threaded) and guarded with `dispatch_once`, using the `class_addMethod`-first dance so it's safe even when the target method is inherited rather than defined on the class itself:

```objc
#import <objc/runtime.h>
@implementation UIViewController (Trace)
+ (void)load {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    Class cls   = self;                                   // UIViewController
    SEL  orig   = @selector(viewDidAppear:);
    SEL  swiz   = @selector(trace_viewDidAppear:);
    Method om = class_getInstanceMethod(cls, orig);
    Method sm = class_getInstanceMethod(cls, swiz);
    // Try to add the orig selector pointing at our IMP. Succeeds only if the
    // class doesn't already define orig itself (i.e. it's inherited):
    BOOL added = class_addMethod(cls, orig,
                                 method_getImplementation(sm), method_getTypeEncoding(sm));
    if (added) {
      // We added orig→ours; now make swiz→original so our body can call through.
      class_replaceMethod(cls, swiz,
                          method_getImplementation(om), method_getTypeEncoding(om));
    } else {
      // Class defines orig itself → a plain atomic swap is correct.
      method_exchangeImplementations(om, sm);
    }
  });
}
- (void)trace_viewDidAppear:(BOOL)animated {
  NSLog(@"viewDidAppear: on %@", self);
  [self trace_viewDidAppear:animated];   // NOT recursion: after the swap this calls the ORIGINAL
}
@end
```

The line that confuses everyone — `[self trace_viewDidAppear:animated]` calling itself — is the heart of it: after the swap, the selector `trace_viewDidAppear:` resolves to the **original** `viewDidAppear:` IMP, so the "recursive-looking" call invokes the real method. You've wrapped it: log, then call through. Reverse the order to run code *after*; omit the call-through to *replace* it.

`method_exchangeImplementations` vs the `class_addMethod`-first pattern is a real distinction: a bare exchange is wrong when the method is only *inherited* (you'd swap the **superclass's** IMP, hooking every sibling subclass too). The add-first dance ensures you're modifying *this* class's own dispatch table. Know the difference — it's a classic swizzle bug and a great interview question.

> 🖥️ **macOS contrast:** This is the *identical* runtime. The Objective-C you'd swizzle in a macOS app — `class_getInstanceMethod`, `method_exchangeImplementations`, the `+load`/`dispatch_once` idiom — is byte-for-byte the same on iOS, because both link the same `libobjc`. What differs is **delivery**: on macOS you compile that category into a dylib and `DYLD_INSERT_LIBRARIES` it (or build a SIMBL/Input-Method plugin); on iOS you can't insert a foreign dylib (AMFI/library validation, above), so the same swizzle reaches the app either as a **Frida hook** (objection / your agent), as a **gadget dylib re-signed into the bundle**, or — on a jailbreak — as a **Substrate/ElleKit tweak** loaded into every process ([[tweak-development-with-theos]]). The technique is portable; only the injection vehicle changes.

### How Frida and objection swizzle

When you do `method.implementation = ObjC.implement(method, fn)` in Frida (the swizzle from the Frida lesson's Lab 4), the ObjC bridge is calling `method_setImplementation` under the hood — pointing the `Method`'s IMP slot at a `NativeCallback` that wraps your JS, and stashing the old IMP so you can call through. objection's `ios hooking watch method` and `ios hooking set return_value` build on the *same* primitive plus `Interceptor.attach` on the method's implementation address. So the layering is:

```
ios hooking set return_value '-[Gate isPremium]' true   (objection command)
   → rpc.exports call into objection's agent
       → ObjC bridge: resolve Gate, selector isPremium → Method → implementation
           → Interceptor.attach(impl,{ onLeave(r){ r.replace(ptr(1)); } })   (Frida)
               → frida-gum patches the IMP's prologue with a trampoline      (native)
                   → which is, conceptually, runtime method swizzling         (libobjc)
```

Four layers, one idea. This is why understanding swizzling pays off everywhere: it's the bottom of objection, of Frida's ObjC bridge, and of every jailbreak tweak.

### Detecting swizzling: the defense side

Because swizzling is "rewrite the IMP slot," an app can detect it by **inspecting its own dispatch tables** — the both-sides game of [[anti-tamper-pinning-and-detection-both-sides]]. The standard checks:

- **IMP-range validation.** A legitimate method's IMP points *inside the module that defines it*. Read `method_getImplementation(class_getInstanceMethod(cls, sel))`, then check whether that address falls within the expected image's `__TEXT` range (`dladdr` → `Dl_info.dli_fname`, compared to the framework's mach-o slide). A Frida/objection swizzle points the IMP at a `NativeCallback` trampoline in **anonymous JIT memory or `FridaGadget.dylib`** — outside the expected range. That mismatch is the tell.
- **Prologue integrity.** `Interceptor.attach` (which objection's `watch`/`set return_value` use) patches the function *prologue* with a branch to its dispatcher. An app that hashes its own `__TEXT` notices the changed bytes — which is exactly why `Stalker` (no prologue patch) or hooking *above* the integrity check is the counter-move.
- **Selector/IMP audit at startup.** Some hardened SDKs snapshot critical methods' IMPs in `+load` and periodically re-compare, alarming if a security-relevant selector's IMP moved.

The meta-point you've now seen from both directions: detection and bypass are the *same primitive*. The detector is itself a method — so you swizzle *it* to report "clean," and you're back where you started, one level up. This recursion is the whole texture of iOS app hardening, and it's why a top-1% RE reasons about *where in the call graph* to hook, not just *whether* a hook works.

### Cycript and cynject: the interactive ancestor

Before Frida, interactive iOS runtime poking meant **Cycript** (Jay Freeman / saurik). Cycript was a hybrid Objective-C/JavaScript REPL: you'd inject it into a running app and get a `cy#` prompt where you could read and call live objects in a Cocoa-flavored syntax — `[UIApp keyWindow]`, `choose(UIViewController)` to heap-scan for live instances, reassign a method's implementation interactively to swizzle on the fly. Its injection engine was **cynject**, the C code-injection tool that shipped with **Cydia Substrate** (originally *MobileSubstrate*) — the same Substrate that powered classic jailbreak tweaks. The pattern set the template Frida later generalized: inject a scripting runtime into the target, expose the ObjC runtime to it, poke live.

Cycript is **dead for modern work, and you should know why**:

- It saw meaningful development only ~2009–2013; cynject/Substrate injection broke around **iOS 12 (~2019)**, and **PAC** (A12+, [[kernel-hardening-pac-sptm-txm-mie]]) plus library validation break its remaining workflows on iOS 15+.
- NowSecure forked it as **frida-cycript**, replacing Cycript's bespoke runtime with **Mjølner**, a runtime built on frida-core — so the *Cycript syntax* survives, but powered by the same Gum engine as everything else. In practice almost everyone moved to Frida's own REPL + the ObjC bridge + objection, which cover the same ground with current platform support.

The takeaway isn't "learn Cycript" — it's lineage. Every Cycript idiom has a one-to-one Frida translation, which is exactly why old writeups still teach you something:

```
// Cycript (cy# prompt)              →  Frida (REPL / ObjC bridge)
cy# [UIApp keyWindow]                →  ObjC.classes.UIApplication.sharedApplication().keyWindow()
cy# choose(UIViewController)         →  ObjC.choose(ObjC.classes.UIViewController, { onMatch, onComplete })
cy# var o = #0x114e08a00            →  var o = new ObjC.Object(ptr('0x114e08a00'))
cy# Gate->isPremium = function(){…}  →  Gate['- isPremium'].implementation = ObjC.implement(m, fn)
```

objection's `ios hooking` and Frida's `ObjC.choose` are the direct descendants of Cycript's `choose()` and interactive swizzling; the field consolidated onto Gum because it's the one engine that tracks Apple's hardware mitigations (ARM64e/PAC pointer signing on patched IMPs, [[the-jailbreak-landscape-2026]]). When you read a 2014-era jailbreak writeup full of `cy#` prompts, mentally translate to Frida and you've lost nothing.

### Why this is the RE / app-sec payoff

objection + swizzling is the *velocity* layer of a mobile assessment. Static analysis ([[static-analysis-class-dump-and-disassemblers]]) tells you the class and selector names; objection turns those names into instant runtime observations and modifications without a script per question; and when a pre-built command misses, you `import` a hand-written swizzle. The forensic payoff is the storage and crypto families — keychain, credentials, cookies, defaults, container files, and live CommonCrypto — recovering plaintext and keys an at-rest image can't yield. The app-sec payoff is the bypass family — pinning, jailbreak detection, biometric gates — letting you observe the app's *real* behavior with its defenses down. And the engineering payoff is conceptual: once you see that all of it is "rewrite the selector→IMP table," you understand objection, Frida's ObjC bridge, Cycript's ghost, and the entire tweak ecosystem as one mechanism.

It also reframes how you *build* securely. Every objection one-liner that defeats a control is a control that trusted the wrong layer: a boolean gate (flip the return), a local-only biometric check (call the success path), a client-side pin the app could be talked out of (hook the TLS trust check). The defenses that *don't* fall to a one-liner are the ones rooted below the runtime — a secret the SEP only releases on a real biometric match, a server that re-verifies what the client claims, an integrity check positioned above the hooks. Knowing the offensive primitive is therefore the fastest route to designing the defensive one; the RE and the builder are reading the same map from opposite ends.

## Hands-on

These run on your Mac against a **Simulator** process (a native macOS process). There is no on-device shell.

**Install and version-check:**

```bash
pipx install objection            # pulls frida-tools as a dependency
objection version
# objection: 1.12.5               # latest as of 2026-06; verify at author time
# frida:     17.x.x
```

**Boot a Simulator, install a target, attach with objection:**

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted /path/to/MyApp.app          # an app you built to the Sim
xcrun simctl launch booted com.example.MyApp            # note the returned PID
frida-ps | grep -i myapp                                # plain frida-ps lists LOCAL procs
# 50321  MyApp
objection --local -n MyApp explore                      # --local = the host device (Sim)
# MyApp on (... ) [local] #   ← objection's REPL prompt
```

**Orient: where does the app live, what does it link?**

```text
# (inside the objection REPL)
env
# Name               Path
# BundlePath         /Users/you/Library/Developer/CoreSimulator/.../MyApp.app
# DocumentDirectory  /Users/you/Library/Developer/CoreSimulator/.../Documents
# LibraryDirectory   .../Library
# CachesDirectory    .../Library/Caches
ios bundles list_frameworks
ios info binary          # entitlements, PIE, ARC, encryption status (Sim: not FairPlay)
```

**Storage triage:**

```text
ios nsuserdefaults get
ios plist cat Library/Preferences/com.example.MyApp.plist
ios cookies get
ios keychain dump        # Sim: usually near-empty (no real Data Protection) — see caveat
ls Documents
file download Documents/app.sqlite ./app.sqlite      # pull the container DB to the Mac
```

**Map the runtime and hook a gate (swizzling, packaged):**

```text
ios hooking search classes Gate                      # find candidate classes
ios hooking list class_methods MyGate
ios hooking watch class MyGate                        # auto-hook every method, print live
ios hooking watch method '-[MyGate isPremium]' --dump-args --dump-backtrace --dump-return
ios hooking set return_value '-[MyGate isPremium]' true   # flip the gate
jobs list                                            # every hook is a manageable job
```

**Pinning bypass and custom-script escape hatch:**

```text
ios sslpinning disable           # installs the battery of trust/TLS/library hooks
import ./my_custom_pin_hook.js   # when the built-in misses: your own Frida agent, same session
```

**One-shot from the shell (good for scripted/repeatable runs):**

```bash
objection --local -n MyApp explore --startup-command "ios sslpinning disable"
```

**Local-auth / UI inspection (the biometric-gate worked example):**

```text
ios ui biometrics_bypass     # hook -[LAContext evaluatePolicy:...] → invoke reply(YES, nil)
ios ui dump                  # print the live view hierarchy (find the gated screen's classes)
ios ui screenshot ./ui.png   # grab the current screen to the Mac
ios pasteboard monitor       # watch UIPasteboard for copied secrets (jobs kill to stop)
```

**Memory primitives as commands:**

```text
memory list modules
memory search 41 50 49 5f 4b 45 59 --string          # find "API_KEY" in process memory
memory dump from_base 0x102f00000 4096 ./chunk.bin
```

> 🔬 **Forensics note:** `memory dump all` over a live process captures decrypted strings, keys, and buffers that never hit disk — the runtime cousin of a FairPlay in-memory dump ([[fairplay-encryption-and-decrypting-app-store-apps]]). Carve it with `strings`/`rabin2 -z`, but record that it's a *live* artifact: hash the dump, note the bundle UUID and the exact `memory list modules` slide so addresses are reconstructable, and keep the objection command transcript alongside it.

> ⚠️ **ADVANCED — device patchipa path (no device here; narrate only).** On a non-jailbroken **device** you'd run `objection patchipa -s MyApp.ipa -c "<identity>"` (optionally `--gadget-version`/`-V <v>` to pin Frida, and `--provision-file`/`-P <profile.mobileprovision>` for entitlements), install the resulting `MyApp-frida-codesigned.ipa` (`ios-deploy`, Sideloadly, or TrollStore on ≤ iOS 17.0), launch it, then `objection -n MyApp explore` (USB is the default transport — no `--local` here) to connect to the embedded gadget. Verify the exact `patchipa` flag names with `objection patchipa --help` for your version — they have shifted across releases. None of this is reproducible without hardware + a signing identity.

## 🧪 Labs

> ⚠️ **All labs run against the iOS Simulator (a native macOS process) — no device, no jailbreak — except Lab 6, which is a narrated walkthrough.** Fidelity caveat for every Simulator lab: the app is **arm64 macOS** under the host XNU kernel with **no AMFI/sandbox/SEP/Data-Protection/FairPlay**, and the device-only daemons (`knowledged`, `biomed`, `powerlogHelperd`, `routined`) don't run. Concretely for *this* lesson: `ios keychain dump`, `ios jailbreak disable`, and `ios info binary`'s encryption field are **not faithful** on the Simulator (no real keychain/Data-Protection, nothing to detect, no FairPlay). What *is* faithful: the **objection command mechanics**, the **ObjC runtime + swizzling**, `ios hooking`, the filesystem/storage families (`env`, `nsuserdefaults`, `plist cat`, `cookies`, `file download`), `ios sslpinning disable` (the Foundation TLS stack — Secure Transport/BoringSSL/`NSURLSession` — exists on the Sim), and `memory`. Build a self-authored sample app (a plain Xcode "App" template, or clone **OWASP iGoat-Swift** / **DVIA-v2** and build the Simulator scheme — no signing needed) as your authorized target.

### Lab 1 — Attach and orient with objection *(substrate: Simulator)*

1. Build/launch your sample app to the Simulator; confirm it as a local process (`frida-ps | grep -i <App>`).
2. `objection --local -n "<App>" explore` (the `--local`/`-L` flag targets a process on this Mac — the Simulator case).
3. Run `env` — record the four container paths. Cross-check one against the real on-disk location under `~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/` ([[simulator-internals-and-on-disk-filesystem]]).
4. `ios bundles list_frameworks` and `ios info binary`.
5. **Deliverable:** the container map, and a note on which `ios info binary` fields are *meaningless on the Simulator* (encryption/FairPlay) vs. real (PIE, ARC, entitlements).

### Lab 2 — Filesystem & storage triage *(substrate: Simulator)*

1. In your sample app, write something to `NSUserDefaults`, drop a value into a plist under `Library/Preferences`, and (if your app makes web requests) accept a cookie.
2. From objection: `ios nsuserdefaults get`, `ios plist cat <that plist>`, `ios cookies get`.
3. `ls Documents`, then `file download <some file> ./out` and confirm the bytes match on the Mac (`shasum -a 256`).
4. Run `ios keychain dump`. Observe it's empty/sparse — write one sentence on *why* (the Simulator has no SEP-backed keychain / Data-Protection classes; [[keychain-on-ios]], [[data-protection-and-keybags]]).
5. **Deliverable:** the recovered defaults/plist/cookie values + the downloaded file's hash, and the keychain-fidelity note.

### Lab 3 — Flip a gate two ways: objection vs. raw Frida *(substrate: Simulator)*

1. In your sample app, add a `BOOL`-returning gate: `-(BOOL)isPremium` on a `Gate` class, wired to hide/show a feature.
2. **objection way:** `ios hooking watch method '-[Gate isPremium]' --dump-backtrace`, exercise the UI, then `ios hooking set return_value '-[Gate isPremium]' true`. Confirm the feature unlocks.
3. **Frida way:** `jobs kill` the objection hook, `import` a script that does `ObjC.classes.Gate['- isPremium'].implementation = ObjC.implement(...)` returning 1.
4. **Deliverable:** before/after behavior for both, and a paragraph identifying which Obj-C runtime call each path ultimately performs (`method_setImplementation` / `Interceptor` on the IMP) — i.e. that both are swizzling.

### Lab 4 — Hand-roll a swizzle and reason about exchange vs. add-first *(substrate: Simulator, your source)*

1. In your sample app, add the `UIViewController (Trace)` category from the Concepts section (swizzle `viewDidAppear:` to `NSLog` then call through). Build, run, watch the log fire on every screen.
2. Now deliberately introduce the inherited-method bug: swizzle a method your subclass does **not** override (so it's defined on the superclass) using a *bare* `method_exchangeImplementations` instead of the add-first dance. Observe it hooking siblings / misbehaving.
3. Fix it with the `class_addMethod`-first pattern.
4. **Deliverable:** the working category, and a short explanation of *why* the bare exchange was wrong for the inherited method (you'd swap the superclass's shared IMP) — and why `+load` + `dispatch_once` is the correct timing/guard.

### Lab 5 — `ios sslpinning disable` against a pinned Simulator request *(substrate: Simulator)*

1. Give your sample app a request to an HTTPS endpoint you control, with a simple `URLSession:didReceiveChallenge:` pin (compare the server trust to a bundled cert).
2. Point the app's traffic at a proxy (mitmproxy/Burp) with its CA trusted by the Simulator; confirm the request **fails** while pinning is on ([[traffic-interception-and-tls]], [[certificate-pinning-and-bypass]]).
3. `ios sslpinning disable`, retry — the request now flows through the proxy.
4. **Deliverable:** the before/after proxy capture, and a note listing *which* hooks objection installed that made it work (the Secure Transport/BoringSSL + `NSURLSession`-delegate path — read them off the REPL output), plus one sentence on a pinning style this would **not** beat (a custom in-app SPKI `memcmp` below those TLS hooks, or pin logic gated only on `SecTrustEvaluateWithError`).

### Lab 6 — Read-only walkthrough: patchipa on a non-jailbroken device *(substrate: narrated; no device)*

You can't run this, but you must be able to **describe** the standard non-JB professional path:

1. Obtain an authorized IPA (extracted/decrypted, [[fairplay-encryption-and-decrypting-app-store-apps]]).
2. `objection patchipa -s App.ipa -c "<signing identity>"` → it unzips, drops `FridaGadget.dylib` into `Frameworks/`, adds the `LC_LOAD_DYLIB`, writes the listen-mode config, and re-signs the dylib + app with your identity/profile.
3. Install `App-frida-codesigned.ipa` (Xcode/`ios-deploy`/Sideloadly, or TrollStore on ≤ iOS 17.0), launch, `objection -n App explore` (USB default, no `--local`) to connect to the in-app gadget.
4. Now device-only commands become meaningful: `ios keychain dump` reads the **real** SEP-backed keychain, `ios jailbreak disable` has actual checks to defeat, and the binary is **FairPlay-encrypted** on disk.
5. **Deliverable:** a comparison table — what the Simulator faithfully reproduced for Labs 1–5 (objection mechanics, ObjC runtime/swizzling, hooking, storage families, `sslpinning`) vs. what only the gadget-on-device path adds (real keychain/Data-Protection, FairPlay, genuine anti-tamper to bypass), and a one-line note on why `patchipa` changes the binary and thus risks anti-tamper detection.

## Pitfalls & gotchas

- **objection *is* Frida — it inherits every Frida limit.** No magic extra access: same three injection models, same version coupling (host objection/Frida must match the gadget/`frida-server`), same detectability. If raw Frida can't reach a process, neither can objection.
- **`ios keychain dump` is per-entitlement-group, and empty on the Simulator.** It only returns items in the *current app's* keychain access group — never "the whole device keychain." And on the Simulator there's no SEP/Data-Protection-backed store to read, so it returns little or nothing. Keychain realism is a device/sample-image topic.
- **`ios sslpinning disable` is a *battery* of common hooks, not a universal solvent.** It nails the Secure Transport/BoringSSL layer, the `NSURLSession` delegate path, and popular libraries (AFNetworking/TrustKit/Cordova) — but a custom in-app pin comparison below those layers (or one gated solely on `SecTrustEvaluateWithError`, which objection doesn't hook) survives. When it "doesn't work," find the comparison statically and `import` a targeted hook; don't assume the app isn't pinning.
- **`method_exchangeImplementations` on an *inherited* method hooks the superclass.** A bare exchange swaps the IMP on whatever class actually *defines* the selector — if that's a superclass, you've hooked every sibling subclass. Use the `class_addMethod`-first dance to confine the swizzle to your class. Classic, silent swizzle bug.
- **Swizzle in `+load`, not `+initialize`.** `+load` runs once, before `main()`, single-threaded — safe. `+initialize` runs lazily on first message and **once per subclass**, so a swizzle there can apply multiple times (double-swap = no-op or chaos). Always `dispatch_once`-guard regardless.
- **Pure-Swift is as hard for objection as for Frida.** `ios hooking list classes` enumerates the **Objective-C** runtime. A pure-Swift type with no `@objc`/`NSObject` base won't appear, and `set return_value` can't target it — you need the Swift bridge / mangled symbols, exactly as in [[dynamic-analysis-with-frida]]. Many "Swift" apps are ObjC-bridged where it counts; check first.
- **Cycript is dead — don't reach for it.** It's broken on modern iOS (Substrate/cynject injection died ~iOS 12; PAC + library validation finish it on 15+). Old writeups using `cy#`/`choose()` translate directly to Frida's REPL + `ObjC.choose` + objection. Use **frida-cycript** only if you specifically want the Cycript *syntax* on Frida's engine.
- **`patchipa` changes the binary — anti-tamper can see it.** Adding `LC_LOAD_DYLIB` and re-signing alters the Mach-O and the Team ID; integrity checks fire ([[anti-tamper-pinning-and-detection-both-sides]]). And a 7-day free cert means the patched app dies in a week.
- **Hooking high-frequency methods floods the channel.** `ios hooking watch class` on a chatty class (or watching a method called thousands of times/sec) stalls the UI as objection ships every call over the message channel — the same backpressure trap as raw Frida. Watch a *method*, not a whole hot class, and `jobs kill` aggressively.
- **Mind which Frida *device* objection picks.** objection drives Frida's device manager: USB is the default, `--network`/`-N -h <ip> -p <port>` selects a network gadget, `--local`/`-L` targets a process on **this Mac** (the iOS-Simulator case), `-S <serial>` chooses among multiple USB devices, and `-n`/`--name` names the target process. The classic Simulator footgun is forgetting `--local`: with the USB default, objection hunts for a `frida-server` on a connected device, finds none, and prints a confusing "unable to connect"/"process not found" — confirm the target with `frida-ps` (local) first. (`-g`/`--gadget` still works but is deprecated; it's now an alias for `-n`.)
- **`objection version` ≠ `frida` version — log both.** They release on independent cadences and the gadget/`frida-server` must match the *Frida* version, not objection's. A surprising number of "won't attach" failures are version skew between the embedded gadget and your host Frida. Capture both in your notes.
- **It's live acquisition.** objection modifies the running target. Never against a seized original; document the objection + Frida versions, the agent, the bundle ID/UUID, and a command transcript. (See the Forensics note above.)

## Key takeaways

- **objection is a Python CLI over a big pre-built Frida agent** — every command (`keychain dump`, `sslpinning disable`, `hooking watch`) is an `rpc.exports` call into that agent. It adds *velocity*, not new access; it inherits Frida's injection models, limits, and detectability.
- **`patchipa` is the iOS replacement for `DYLD_INSERT_LIBRARIES`:** unzip → drop `FridaGadget.dylib` → add `LC_LOAD_DYLIB` → re-sign → repackage. You re-sign because AMFI/library-validation block inserting a foreign dylib — the macOS env-var trick is dead on iOS.
- **Method swizzling is the mechanism under all of it.** Obj-C dispatches via `objc_msgSend` looking up selector→IMP in a *mutable* table; rewrite the IMP and you've hooked the method everywhere. Frida's `ObjC.implement` = `method_setImplementation`; objection's `set return_value` = that plus `Interceptor`.
- **`method_exchangeImplementations` vs. `class_addMethod`-first** matters: a bare exchange on an *inherited* method hooks the superclass. Swizzle in `+load` with `dispatch_once`.
- **`ios sslpinning disable` is a battery of hooks** (Secure Transport/BoringSSL, the `NSURLSession` delegate, AFNetworking/TrustKit — the SSL-Kill-Switch-2 lineage, *not* `SecTrustEvaluateWithError`), not a universal solvent — a custom below-TLS pin needs a hand-written hook via `import`.
- **Cycript → frida-cycript (Mjølner)** is the lineage: interactive ObjC poking moved onto Frida's engine because only Gum tracks Apple's mitigations (PAC/ARM64e). `ObjC.choose` is Cycript's `choose()`.
- **Forensic value is the storage + crypto families** (keychain, credentials, cookies, defaults, container files, CommonCrypto) — plaintext/keys an at-rest image can't give — but it's **live acquisition**: authorized copies only, fully logged.
- **Detection and bypass are the same primitive.** Apps spot swizzling by validating their own IMP ranges / `__TEXT` integrity; you defeat that by swizzling the *detector*. Reason about *where in the call graph* to hook, not just whether a hook works.
- **The mature workflow uses objection and a hand-written agent together** in one session: objection to orient and clear the standard questions, `import` to drop a precise swizzle for the one thing the pre-built hooks can't reach. They aren't competitors — objection *is* a Frida agent.
- The **Simulator faithfully teaches objection mechanics, the runtime, and swizzling**; it does **not** teach keychain/Data-Protection/FairPlay/anti-JB realism — those are device/sample-image topics.

## Terms introduced

| Term | Definition |
|---|---|
| objection | Python CLI built on Frida that ships a pre-compiled Frida agent and exposes mobile-pentest commands (keychain, storage, hooking, pinning bypass) over RPC |
| objection agent | The single large pre-written Frida (TypeScript) agent objection injects; commands map to its `rpc.exports` |
| `patchipa` | objection command that embeds `FridaGadget.dylib` into an IPA (add `LC_LOAD_DYLIB` + re-sign) for non-jailbroken devices |
| Method swizzling | Replacing the `IMP` an Objective-C selector resolves to at runtime, hooking the method for all callers |
| `objc_msgSend` | The Obj-C dispatch function that maps `(class, selector) → IMP` at send time — the late binding swizzling exploits |
| SEL | An interned selector (method name) used as the lookup key in dispatch |
| IMP | A method's actual function pointer, typed `id (*)(id self, SEL _cmd, ...)` |
| Method (struct) | The runtime's `{SEL, IMP, type-encoding}` triple that swizzling rewrites |
| `method_exchangeImplementations` | Runtime call that atomically swaps two `Method`s' IMPs |
| `method_setImplementation` | Runtime call that points one `Method` at a new IMP (returns the old) — what Frida's `ObjC.implement` uses |
| `class_addMethod` / `class_replaceMethod` | Add (or add-or-replace) a method on a class; the add-first swizzle pattern uses these to avoid hooking inherited methods on the superclass |
| `+load` | Class method the runtime calls once, before `main()`, single-threaded — the safe place to swizzle |
| `ios sslpinning disable` | objection command installing a battery of hooks (Secure Transport/BoringSSL, `NSURLSession` delegate, AFNetworking/TrustKit — the SSL-Kill-Switch-2 lineage) to defeat common pinning |
| Cycript | Saurik's pre-Frida interactive ObjC/JS runtime REPL (cynject + Cydia Substrate); broken on modern iOS |
| cynject | The C code-injection tool shipped with Cydia Substrate that Cycript used to enter a process |
| frida-cycript | NowSecure fork of Cycript whose runtime (Mjølner) is rebuilt on frida-core, keeping Cycript syntax on Frida's engine |

## Further reading

- **objection** — github.com/sensepost/objection (README, Wiki: *Using objection*, *Features*, *Notes About The Keychain Dumper*); `objection --help`, `objection patchipa --help`, in-REPL `help ios`. Latest **v1.12.5** (2026-06) — verify at author time.
- **OWASP MASTG/MASVS** — *MASTG-TOOL-0038: objection*; *MASTG-TECH-0090: Injecting Frida Gadget into an IPA*; *MASTG-TECH-0061: Dumping KeyChain Data*; *MASTG-TOOL-0046: Cycript*, *MASTG-TOOL-0049: Frida-cycript* ([[owasp-mastg-and-app-security-testing]]).
- **Frida** — frida.re *JavaScript API* (ObjC bridge, `Interceptor`); `frida-objc-bridge` repo (`implement`, the IMP machinery) ([[dynamic-analysis-with-frida]]).
- **Objective-C runtime** — Apple `objc/runtime.h` reference (`class_getInstanceMethod`, `method_exchangeImplementations`, `method_setImplementation`, `class_addMethod`); NSHipster "Method Swizzling"; Mike Ash (mikeash.com) "Friday Q&A" runtime deep-dives; `man objc_msgSend`.
- **Cycript lineage** — cycript.org (historical); github.com/nowsecure/frida-cycript (Mjølner); saurik's Cydia Substrate / cynject docs.
- **Pinning & tweaks (adjacent)** — TrustKit, AFNetworking `AFSecurityPolicy`; Theos/ElleKit/Logos `%hook` as device-side swizzling ([[tweak-development-with-theos]], [[certificate-pinning-and-bypass]]).
- **Practitioner cheat-sheets** — Virtue Security "iOS Frida/objection Pentesting Cheat Sheet"; RedFox Security "iOS Pen Testing with Objection"; NetSPI "Four Ways to Bypass iOS SSL Verification and Certificate Pinning" (the `patchipa -s … -c …` workflow).
- **Books** — David Thiel, *iOS Application Security*; Jonathan Levin, *MacOS and iOS Internals* (Obj-C runtime, message dispatch — newosxbook.com).

---
*Related lessons: [[dynamic-analysis-with-frida]] | [[static-analysis-class-dump-and-disassemblers]] | [[certificate-pinning-and-bypass]] | [[anti-tamper-pinning-and-detection-both-sides]] | [[tweak-development-with-theos]] | [[fairplay-encryption-and-decrypting-app-store-apps]] | [[code-signing-and-provisioning-in-depth]] | [[owasp-mastg-and-app-security-testing]]*
