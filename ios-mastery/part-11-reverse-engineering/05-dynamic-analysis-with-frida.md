---
title: "Dynamic analysis with Frida"
part: "11 — Reverse Engineering & App Security"
lesson: 05
est_time: "50 min read + 25 min labs"
prerequisites: [static-analysis-class-dump-and-disassemblers, processes-mach-xpc]
tags: [ios, re, frida, dynamic-analysis, instrumentation, app-security]
last_reviewed: 2026-06-26
---

# Dynamic analysis with Frida

> **In one sentence:** Frida injects a JavaScript runtime into a *running* process and lets you hook, trace, and rewrite native and Objective-C/Swift code from the outside — so where static analysis shows you the binary's potential, Frida shows you what actually happens: the decrypted strings, the live arguments to `CCCrypt`, the URL passed to `NSURLSession` before TLS wraps it, and the boolean a jailbreak-detection routine *really* returned.

> ⚖️ **AUTHORIZED USE ONLY.** Dynamic instrumentation modifies a running program's behavior. Run it **only** against software you own, you wrote, or you are contractually authorized to test (a signed pentest engagement, your employer's app, an OWASP crackme, a malware/stalkerware sample in an authorized examination). Attaching Frida to a third party's app to defeat its protections, lift its content, or exfiltrate its data can violate the CFAA, the DMCA's anti-circumvention provisions, app-store terms, and software licenses. In a forensic context, instrumenting a live process on an evidence device is a **modification** of state — it breaks the dead-box principle, must be documented, must be authorized in the warrant/scope, and is normally reserved for a forensic *copy* running on your own analysis hardware, never the seized original. Image first; instrument the copy.

## Why this matters

Static analysis ([[static-analysis-class-dump-and-disassemblers]]) has a hard ceiling: it reasons about code as written, not code as run. The interesting iOS behavior is almost always *runtime* behavior. A string is XOR-decoded at launch and never touches disk in cleartext. A C2 URL is assembled from three fragments and a device identifier. A "premium" gate is a single `BOOL` returned deep in a call graph you'd spend an afternoon tracing by hand. App Store binaries are FairPlay-encrypted on disk and only decrypt *in memory* — so the only place to read their real code is from a live process ([[fairplay-encryption-and-decrypting-app-store-apps]]). And anti-analysis code — jailbreak detection, certificate pinning, anti-debug — is specifically designed to make the static picture misleading.

Frida collapses all of that. You attach to the live process, hook the function you care about, and *observe* its arguments and return value, or *replace* its behavior. For the forensicator examining a suspect app, Frida is how you recover plaintext that the app encrypts at rest, capture the keys it derives, log the endpoints it talks to, and prove what it does with data — evidence you cannot get from the binary alone. For the builder/RE'er, it's the fastest path from "I see this method in the disassembly" to "here is exactly what it's called with, 40 times a second, in production." This lesson teaches Frida's architecture, its three injection models, and — because you have no physical device — how to drive the **same API** against a Simulator process running natively on your Mac.

## Concepts

### What Frida actually is

Frida is not one program; it's a stack with a clean split between a **host** side (your Mac) and an **agent** that runs *inside* the target process:

```
┌─────────────────────────── your Mac (host) ───────────────────────────┐
│  frida / frida-trace / frida-ps / objection  (frida-tools, Python CLI) │
│  Python / Node / Swift bindings  ─────────────►  frida-core            │
│                                                  (device mgr, session, │
│                                                   injection, transport)│
└───────────────────────────────┬───────────────────────────────────────┘
                                 │  inject + bidirectional message channel
                                 ▼
┌──────────────── target process (Simulator app / device app) ──────────┐
│  GumJS runtime (QuickJS or V8)  ◄── your agent.js runs here, in-proc   │
│        │ exposes ▼                                                      │
│  frida-gum  (C core):  Interceptor · Stalker · Memory · Module ·       │
│             NativeFunction/NativeCallback · Backtracer · CModule       │
│        │ operates on ▼                                                  │
│  the target's own __TEXT/__DATA, ObjC/Swift runtime, libc, frameworks │
└────────────────────────────────────────────────────────────────────────┘
```

- **frida-gum** is the C engine: the actual machinery that rewrites a function prologue, JIT-recompiles a basic block, reads/writes memory, walks modules. Platform-specific, ARM64/ARM64e-aware (it handles PAC signing of patched pointers — see [[kernel-hardening-pac-sptm-txm-mie]]).
- **GumJS** embeds a JavaScript engine (QuickJS by default; V8 optional) and surfaces Gum to JS. This is the "agent runtime" that gets mapped into the target. You write JavaScript (or TypeScript compiled by `frida-compile`); it runs *in-process*, at native speed for the hot parts because the hooks themselves are compiled native code.
- **frida-core** is the host-side library: it enumerates devices (local, USB, remote), manages sessions, performs the injection, and carries the async **message channel** (`send()`/`recv()`) and **RPC** (`rpc.exports`) between your script and your CLI.
- **frida-tools** is the Python CLI layer you actually type: `frida` (REPL), `frida-trace`, `frida-ps`, `frida-ls-devices`, `frida-kill`, plus the third-party `objection` ([[objection-swizzling-and-runtime-exploration]]).

The key mental model: **your JavaScript executes inside the victim's address space**, with full read/write to its memory and the ability to intercept any call. The host CLI is just a remote control and a console.

> 🖥️ **macOS contrast:** You've used this exact engine on macOS — `frida -n Safari`, or `frida-trace -m '-[NSURLSession dataTaskWithRequest:*]' Safari`. The injection primitive there is the Mach `task_for_pid` → `mach_vm_allocate` → `thread_create_running` dance you met in [[processes-mach-xpc]]: Frida grabs the target's **task port**, maps in the agent, and spins up a thread to run it. On macOS this works for your own processes but is gated for SIP-protected / hardened-runtime binaries (you need the `com.apple.security.cs.debugger` entitlement or SIP disabled). `dtrace`/`dtruss` is the kernel-level cousin — system-wide, probe-based, but read-mostly and itself SIP-restricted. The thing to internalize: **on an iOS *device* none of this is available to you** — the kernel denies you the task port (no `task_for_pid` for unprivileged code), AMFI refuses to execute the unsigned agent, and the sandbox blocks `ptrace`. That's why the device needs either a jailbreak (to run a privileged `frida-server`) or a *gadget* baked into the app. The Simulator, by contrast, is a native macOS process you own — so Frida injects exactly as it does into Safari.

### How the agent gets in: injection internals

It's worth understanding the actual mechanism, because it's *exactly* what AMFI/sandbox block on a device and *exactly* what you have for free in the Simulator. When you `frida -p <pid>`, frida-core performs a classic **Mach injection** (the technique you traced in [[processes-mach-xpc]]):

1. **Acquire the task port** with `task_for_pid(mach_task_self(), pid, &task)`. The task port is a capability granting full control of another process's address space and threads. On macOS/Simulator your user can get it for a process you own (or a debuggable/`get-task-allow` build); on an iOS *device* the kernel hands unprivileged callers nothing — this single call is the wall.
2. **Allocate memory** in the target via `mach_vm_allocate`, write a small **bootstrapper** plus the GumJS runtime image into it (`mach_vm_write`/`mach_vm_protect` to make it executable).
3. **Start a thread** with `thread_create_running`, entering the bootstrapper, which initializes GumJS and loads your agent on a dedicated Frida thread — the target's own threads keep running.
4. **Wire the channel.** The agent opens a bidirectional pipe back to frida-core; from here on, host and agent exchange async messages.

That's the whole trick: get the task port, map in code, run a thread. The reason `frida-server` must be **root** on a device is that only a privileged, AMFI-exempt process can perform steps 1–3 against another app; the reason the **gadget** model exists is that an app loading its *own* dylib never needs a foreign task port at all; and the reason the **Simulator** is open is that the app is a process you own on a kernel with no AMFI. Same three steps, three different ways to be allowed to take them.

### Talking to your agent: messages and RPC

Your agent runs *in the target*; your CLI/script runs on the *host*. They're separate worlds connected only by an async message channel — internalize this or your data-capture scripts will silently drop output.

- **`send(payload[, data])`** (agent → host) ships a JSON-serializable `payload` plus an optional raw `ArrayBuffer` (`data`) — use `data` for binary like a captured key or a memory dump, not base64-in-JSON. The host receives it via an `on('message', …)` handler (Python: `script.on('message', cb)`).
- **`recv(type, cb)`** (host → agent) lets the agent wait for instructions. `recv().wait()` blocks the agent until the host replies — useful for interactive "should I bypass this check?" flows.
- **`rpc.exports = { dumpKeys() {…} }`** turns the agent into a callable API: the host invokes `script.exports_sync.dump_keys()` (note Python snake_case mapping) and gets the return value back. This is how you build a *tool* on top of Frida rather than just watching `console.log`.

```js
// agent.js — forensic key capture: hook CommonCrypto, ship keys as raw bytes
const CCCrypt = Process.getModuleByName('libcommonCrypto.dylib').getExportByName('CCCrypt');
Interceptor.attach(CCCrypt, {
  onEnter(args) {
    // CCCrypt(op, alg, options, key, keyLength, iv, dataIn, dataInLength, dataOut, ...)
    const keyLen = args[4].toInt32();
    send({ event: 'CCCrypt', alg: args[1].toInt32(), keyLen },
         args[3].readByteArray(keyLen));      // raw key bytes ride in `data`
  }
});
```

```python
# host.py — receive and persist captured keys with a forensic transcript
import frida, sys
def on_message(message, data):
    if message['type'] == 'send':
        p = message['payload']
        print(p, data.hex() if data else None)   # data = the raw key bytes
session = frida.attach(int(sys.argv[1]))
script = session.create_script(open('agent.js').read())
script.on('message', on_message)
script.load()
sys.stdin.read()                                  # keep the process attached
```

This is the durable pattern behind every Frida-based capture tool, including `frida-trace` and objection.

> 🔬 **Forensics note:** Hooking the crypto boundary recovers what no at-rest acquisition can. An app may store only ciphertext in its container ([[app-sandbox-and-filesystem-layout]]), but it must call `CCCrypt`/`SecKeyCreateDecryptedData`/its own wrapper with the **key and plaintext in registers** to use it — so a single `Interceptor.attach` on the decryptor yields both. The same goes for the network boundary: hook `-[NSURLSession dataTaskWithRequest:…]` or `nw_connection_send` and you capture the **cleartext request body, headers, and bearer tokens before TLS** — a cleaner, attributable capture than an on-wire MITM, and one that survives certificate pinning entirely. Treat every captured key/token as evidence: hash it, timestamp it, and tie it to the bundle version + binary UUID in your notes.

### The three injection models

Everything in iOS Frida comes down to *how the agent gets into the process*. There are exactly three roads, and which one you can use is dictated by whether you have a jailbreak, whether you can re-sign the app, and whether you're on a device or the Simulator.

| | **frida-server** (jailbroken device) | **frida-gadget** (re-signed app) | **Simulator attach** (this course) |
|---|---|---|---|
| Substrate | Physical device, jailbroken | Physical device, no JB | iOS Simulator on your Mac |
| How the agent enters | Privileged `frida-server` (root) injects via task port | App loads `FridaGadget.dylib` itself at launch | Frida injects into the native process via task port |
| Prereq | Jailbreak (palera1n, A8–A11 / checkm8, iOS ≤ 18.7.x) | Apple signing cert + provisioning profile to re-sign | Just Xcode + frida-tools |
| Spawn (`-f`) | ✅ full spawn-gating, attach any app | ✅ (gadget loads at launch) | ⚠️ broken for Sim apps (see below) |
| Fidelity | Real device: SEP, Data Protection, FairPlay, real daemons | Real device, but only the patched app | **No** SEP/AMFI/sandbox/FairPlay; host frameworks |
| Device needed? | Yes | Yes | **No** ← the no-device path |

**1. `frida-server` on a jailbroken device.** A statically-linked `frida-server` binary runs as **root** on the jailbroken device, listening on a local port; the host reaches it over USB via `usbmuxd` (`frida-ps -Uai`). Because it's root and the jailbreak has neutered AMFI/sandbox for it, it can `task_for_pid` any app, inject the agent, and even **spawn** apps suspended so you hook *before* `main()` runs (`frida -U -f com.example.app`). This is the highest-fidelity model — you're on real hardware with a real SEP, real Data Protection, real FairPlay-encrypted binaries — but it is strictly device-bound and gated on a working jailbreak, which for the modern boundary means **A8–A11 (checkm8) on iOS ≤ 18.7.x via palera1n** — there is **no public kernel jailbreak for A12+ on iOS 18/26** ([[the-jailbreak-landscape-2026]]). (The BootROM-*acquisition* boundary reaches A13 via the 2026 `usbliter8` exploit, but that's code-exec for imaging — it isn't a jailbreak and won't host `frida-server`.) You have no device, so this is a **read-only walkthrough** for you (Lab 6).

**2. `frida-gadget` embedded into a re-signed app.** When you can't jailbreak but you *can* re-sign, you flip the model inside-out: instead of injecting from outside, you make the app **load Frida itself**. You add an `LC_LOAD_DYLIB` command to the main executable pointing at `@executable_path/Frameworks/FridaGadget.dylib`, drop the gadget (and an optional `FridaGadget.config` / `.dylib.config`) into the bundle, then **re-sign** the whole app with your Apple Developer cert + an `embedded.mobileprovision`, and install it (`ios-deploy`/`Apple Configurator`). At launch, `dyld` loads the gadget, which starts a Frida server *inside the app's own sandbox*. A sibling JSON config (`FridaGadget.config`) picks the **interaction type**: `listen` (default — wait on a TCP port for the host to connect), `connect` (reverse-connect *out* to your host, for devices you can't reach inbound), or `script` (run a bundled `.js` at startup with no host at all — fully autonomous instrumentation). `objection patchipa` and OWASP **MASTG-TECH-0090** automate the unzip → add `LC_LOAD_DYLIB` → drop dylib+config → `applesign`/`codesign` with your `embedded.mobileprovision` → repackage pipeline. The cost: you need a paid signing identity, the app must be re-signable (some apps detect the changed `LC_LOAD_DYLIB`/teamID — see [[anti-tamper-pinning-and-detection-both-sides]]), and you only get *that one* app, not the system. This too needs a device to *install* on, so it's walkthrough-level here — but the **gadget-injection skill** transfers directly to the Simulator gadget (`frida-gadget-<ver>-ios-simulator-universal.dylib`).

**3. Attaching to a Simulator process — the path this course uses.** A Simulator app is **not** running iOS. On Apple-Silicon Macs, CoreSimulator runs each app as a **native arm64 Mach-O process on macOS**, using the Simulator runtime's copy of UIKit/Foundation but the host XNU kernel, host `dyld`, and *no* AMFI/sandbox/SEP enforcement. To Frida it is just another local macOS process. You `frida-ps` to find it and `frida -p <pid>` (or `frida -n <name>`) to attach — the **identical API** to attaching to Safari. This is the great gift of the no-device constraint: the instrumentation surface (`Interceptor`, `Stalker`, the ObjC bridge, `frida-trace`) is byte-for-byte the same skill you'd use on a device; only the injection plumbing differs.

> ⚠️ **Simulator spawn (`frida -f`) is broken for Sim apps.** Frida's launchd integration is hardcoded for macOS's `launchd` (PID 1); the Simulator's per-runtime `launchd_sim` has no fixed PID, so `frida -f com.example.app` fails to spawn-gate Simulator apps (tracked upstream — issue #3376, still open as of 2026-06). **Workaround:** launch the app with `xcrun simctl launch` (optionally `--wait-for-debugger`) or from Xcode, then **attach by PID/name**. You lose the "hook before `main()`" property — for early-init hooks on the Simulator, prefer the Simulator gadget or `--wait-for-debugger`.

### The instrumentation API — the four primitives that matter

Almost all Frida work is built from a small set of GumJS objects.

**`Interceptor` — function/method hooking.** The workhorse. `Interceptor.attach(target, callbacks)` installs an **inline trampoline**: Frida overwrites the function's prologue with a branch to its dispatcher, relocates the displaced instructions, and (on ARM64e) re-signs the patched pointers for PAC. Your `onEnter(args)` runs before the function body with `args[]` as `NativePointer`s; `onLeave(retval)` runs after, and `retval.replace(x)` rewrites the return value. `Interceptor.replace(target, NativeCallback(...))` swaps the function out entirely.

```js
// Hook the C function open() — observe every path the app opens, and lie about one.
Interceptor.attach(Module.getGlobalExportByName('open'), {
  onEnter(args) {
    this.path = args[0].readUtf8String();   // arg0 = const char *path
    console.log('open(' + this.path + ', flags=' + args[1].toInt32() + ')');
  },
  onLeave(retval) {
    if (this.path && this.path.indexOf('/private/etc/jailbreak_marker') !== -1) {
      retval.replace(ptr(-1));              // pretend the file doesn't exist
    }
  }
});
```

**`Stalker` — execution tracing.** Where `Interceptor` hooks *known* functions, `Stalker` traces *whatever runs*. `Stalker.follow(threadId, {events, onReceive, transform})` JIT-recompiles each basic block as a thread executes it, emitting events at `call`/`ret`/`exec`/`block`/`compile` granularity. It's how you get code-coverage, trace an unknown control-flow path, or find which function decodes a string — without knowing its address up front. Because it **doesn't patch prologues**, it's harder for checksum-based anti-tamper to spot than `Interceptor` (though its timing overhead is detectable). It is heavyweight: scope it to one thread and a tight window.

```js
// Stalk the current thread for one action, count which app functions ran.
const main = Process.enumerateModules()[0];          // the app's own image
Stalker.follow(Process.getCurrentThreadId(), {
  events: { call: true },
  onReceive(events) {
    Stalker.parse(events).forEach(([_type, _from, to]) => {
      if (to >= main.base && to < main.base.add(main.size))
        console.log('call → ' + main.name + '!' + to.sub(main.base));
    });
  }
});
// … trigger the behavior, then Stalker.unfollow(Process.getCurrentThreadId());
```

**`Memory` / `Module` / `NativePointer` — the substrate.** `Process.getModuleByName(name).getExportByName(sym)` (or `Module.getGlobalExportByName(sym)` for a global search), the per-module `enumerateExports/Imports/Symbols()`, and `Process.enumerateModules()` give you addresses; `Memory.readByteArray/readUtf8String/scan()` and `Memory.protect()` read/modify memory; `NativeFunction(addr, retType, argTypes)` lets you *call* a target function from your script; `NativeCallback` builds a native function from JS (used by `Interceptor.replace`). `Memory.scan()` over a module's `__TEXT`/`__DATA` ranges is how you find decrypted secrets sitting in RAM.

```js
// Call a target function yourself, then fully replace it.
const check = new NativeFunction(
  Process.getModuleByName('MyApp').getExportByName('license_valid'), 'int', ['pointer']);
console.log('real result for our token:', check(Memory.allocUtf8String('TOKEN-123')));

Interceptor.replace(check, new NativeCallback((tokenPtr) => {
  console.log('license_valid("' + tokenPtr.readUtf8String() + '") → forcing 1');
  return 1;                                  // any token is now "valid"
}, 'int', ['pointer']));
```

`Interceptor.attach` observes (and can tweak the return); `Interceptor.replace` swaps the function body wholesale — reach for `attach` when you want the original behavior plus a side-channel, `replace` when you want to substitute logic entirely.

**The bridges — `ObjC` and `Swift`.** Raw addresses are tedious for Cocoa code, so Frida ships language bridges:

- **ObjC bridge.** `ObjC.classes` is a live proxy over every registered Objective-C class. `ObjC.classes.NSString.stringWithUTF8String_('hi')` calls a method (selector `:` → `_`). `ObjC.Object(ptr)` wraps a raw pointer as a usable object. `ObjC.choose(cls, {onMatch})` heap-scans for **live instances** of a class — invaluable for grabbing an already-instantiated session/keychain object. You hook a method by attaching to its `.implementation`, or **swizzle** it by reassigning `.implementation = ObjC.implement(method, fn)`.

```js
// Capture every NSString → C string and bypass a pinning check, ObjC-style.
const NSURLSession = ObjC.classes.NSURLSession;
Interceptor.attach(NSURLSession['- dataTaskWithRequest:completionHandler:'].implementation, {
  onEnter(args) {
    const req = new ObjC.Object(args[2]);             // NSURLRequest *
    console.log('URL → ' + req.URL().absoluteString().toString());
  }
});
```

- **Swift bridge.** `frida-swift-bridge` gives an `Interceptor`-like interface that maps Swift arguments to wrappers (`Swift.Object`, `Swift.Struct`, `Swift.Enum`) and exposes `Swift.classes`. The catch is structural: **`@objc`/`NSObject`-subclass Swift is reachable through the ObjC bridge** (it has stable selectors), but **pure-Swift** types have mangled, unstable symbols and pass value types in registers per the Swift calling convention — so pure-Swift hooking needs `Process.getModuleByName(app).enumerateSymbols()` to resolve the mangled symbol, plus demangling, and is genuinely harder. Reach for the ObjC bridge whenever a Swift class bridges to ObjC; fall back to the Swift bridge for the rest.

```js
// Pure-Swift, no @objc: there's no selector — resolve the *mangled* symbol and hook it raw.
const sym = Process.getModuleByName('MyApp').enumerateSymbols()
  .find(s => s.name.includes('isLicensed'));        // mangled, e.g. $s5MyApp...isLicensedSbyF
if (sym) {
  Interceptor.attach(sym.address, {
    onLeave(retval) { retval.replace(ptr(1)); }      // Swift Bool true is 1 in x0/w0
  });
}
// swift demangle "$s5MyApp...isLicensedSbyF"  →  MyApp.(…).isLicensed() -> Swift.Bool
```

The friction is real: pure-Swift symbols are **mangled** (run `swift demangle` to read them — see [[static-analysis-class-dump-and-disassemblers]]), value types and protocol witnesses pass through registers per the Swift calling convention so `args[n]` doesn't map cleanly, and the symbol may be stripped entirely in a release build (then you're back to addresses from the disassembler). This is why so much iOS app surface is still hooked through ObjC — and why a builder targeting analyzability avoids burying security gates in unexported pure-Swift functions.

> ⚠️ **Frida 17 moved the bridges out of the core runtime.** Since **Frida 17.0.0 (May 2025)** the ObjC/Swift/Java bridges are **no longer bundled** in GumJS — they're external npm packages (`frida-objc-bridge`, `frida-swift-bridge`, `frida-java-bridge`). In the **REPL and `frida-trace`** the global `ObjC` and `Swift` still "just work" because **frida-tools bakes them in**. But in a standalone agent built with `frida-compile`, you must `import ObjC from 'frida-objc-bridge'` (and `Swift` likewise) yourself, or `ObjC` will be `undefined`. This trips up everyone porting an old script. (Current as of frida-tools 14.x.)

### `frida-trace` — the fastest first move

`frida-trace` auto-generates an editable handler stub for every function/method you match, then hot-reloads the stub when you save it. It's how you go from zero to "what is this called with?" in seconds.

```
frida-trace -p 50321 -m '-[NSURL initWithString:]' -m '*[* *URL*]'   # ObjC methods by glob
frida-trace -p 50321 -i 'CCCrypt' -i 'SecItemCopyMatching'           # C/imported functions
```

`-m`/`-M` include/exclude ObjC methods, `-i`/`-x` include/exclude native functions (by module!symbol glob), `-j` Java (Android). It writes `__handlers__/<scope>/<name>.js` files containing `onEnter`/`onLeave` you edit to dump args, decode structs, and log returns — the generated stub already resolves ObjC selectors and prints a call tree.

### Building real agents: frida-compile, TypeScript, and project layout

REPL one-liners and `-l agent.js` get you started, but a serious instrumentation project — especially anything you'll re-run for chain-of-custody — wants structure. `frida-compile` bundles a multi-file TypeScript/JavaScript agent (with npm dependencies and the externalized bridges) into a single loadable `.js`:

```bash
npm init -y && npm install frida-objc-bridge frida-swift-bridge @types/frida-gum
npx frida-compile agent.ts -o agent.js          # one-shot bundle
npx frida-compile agent.ts -o agent.js -w       # watch + rebuild on save
frida -p 50321 -l agent.js                       # load the bundle
```

In `agent.ts` you get full type-checking against `@types/frida-gum` and must **explicitly import** the bridges (`import ObjC from 'frida-objc-bridge'`) — they are not global outside the REPL/`frida-trace`. The payoff: testable, versioned, reusable agents, an `rpc.exports` API your Python/Node harness drives, and TypeScript catching `NativePointer` mistakes before they crash the target. This is the difference between a throwaway hook and a tool you can hand to another examiner and have them reproduce your result exactly — which, in casework, is the whole point.

> 🖥️ **macOS contrast:** This is the same agent toolchain you'd use to instrument a Mac app — `frida-compile` + `@types/frida-gum`, identical imports, identical `rpc.exports`. The agent source is *portable across targets*: a hook on `-[NSURLSession dataTaskWithRequest:]` you wrote against a Mac app runs unchanged against the same class in a Simulator app or (with the right injection model) a device app, because Foundation is Foundation. The platform difference is entirely in **how you inject**, never in the agent you wrote — which is exactly why building the skill on the Simulator transfers cleanly to the device when you eventually have one.

### Frida vs. lldb vs. dtrace vs. static — when to reach for each

You arrive from macOS with `lldb`, `dtrace`, and a disassembler already in hand. Frida doesn't replace them; it occupies a distinct niche.

| Tool | Model | Best at | Weakness on iOS |
|---|---|---|---|
| Disassembler (static) | No execution | Whole-program structure, finding *where* | Can't see runtime values, decrypted code, real control flow |
| `lldb` + `debugserver` | Breakpoint debugger | Single-step, watchpoints, deep one-call inspection | One process, serial, slow for "log every call"; on device needs `debugserver` + entitlement |
| `dtrace` | Kernel probe tracer | System-wide, low-overhead probes | **Absent on iOS** (SIP/no on-device); macOS-only and restricted |
| **Frida** | In-process JS instrumentation | Hooking *many* functions at scale, modifying behavior, scripted capture, ObjC/Swift bridges | Patches prologues (detectable); pure-Swift is hard; live-acquisition only |

The practical division of labor: **static** to find the address/method, **Frida** to watch and rewrite it at scale, **lldb** to single-step the one gnarly function Frida flagged. Frida and lldb coexist — you can `Interceptor.attach` to log every call site and drop an lldb breakpoint on the one that's interesting ([[debugging-instruments-and-lldb-for-ios]]).

### Frida detection — the cat-and-mouse

Hardened apps actively hunt for Frida, and as an RE you'll both *trip* and *defeat* these checks. The common tells (all of which you then neutralize with the very hooks above — this is the both-sides game of [[anti-tamper-pinning-and-detection-both-sides]]):

- **The default port.** `frida-server` listens on TCP **27042**; apps probe it. (Run `frida-server -l 0.0.0.0:<rand>` to move it.)
- **Loaded-image tells.** The gadget shows up as `FridaGadget.dylib`/`frida-agent` in the dyld image list (`_dyld_image_count`/`_dyld_get_image_name`); apps walk that list for `frida`/`gum`/`cynject` substrings.
- **Thread + named-pipe tells.** A thread named `gum-js-loop` or `gmain`, or a `frida`/`linjector` named pipe/UNIX socket in the process.
- **Prologue integrity.** As noted, `Interceptor`'s trampoline mutates `__TEXT`; an app that checksums its own functions detects the patch — which is why `Stalker` (no prologue patch) or hooking *above* the integrity check is the counter-move.

Each check is itself just a function — so the meta-move is to hook *the detector* and force it to report "clean," exactly as in Lab 4. Detection and bypass are the same primitive pointed in opposite directions.

### Why this is the forensic and RE payoff

Dynamic analysis reaches three classes of evidence that static analysis structurally cannot:

1. **Runtime-decrypted content.** FairPlay App Store binaries are ciphertext on disk; the only cleartext copy is in the live process's `__TEXT`. Frida dumps it — the basis of `frida-ios-dump`/`bagbak` ([[fairplay-encryption-and-decrypting-app-store-apps]]). Likewise app-level "encrypted strings" become readable the instant you hook the decryptor or `Memory.scan()` after launch.
2. **Cryptographic material and plaintext-before-encryption.** Hook `CCCrypt`, `SecKeyCreateSignature`, `kSecAttr*`, or an app's own crypto wrapper and you capture **keys, IVs, and plaintext** at the boundary — the data the app intends to protect at rest. For a stalkerware/malware exam this is how you recover what was exfiltrated and to where.
3. **True control flow and defeated defenses.** Hook the jailbreak-detection or pinning routine and read what it *returned*, or `retval.replace()` it to neutralize the defense and watch the app's real behavior. Capturing the URL/headers/body of `NSURLSession`/`NWConnection` calls *before* TLS — the cleartext request — is the bread-and-butter of API analysis and a cleaner capture than an on-wire MITM ([[certificate-pinning-and-bypass]]).

> 🔬 **Forensics note:** Frida is a **live-acquisition** technique — it changes process memory and, with hooks installed, the app's behavior. In a casework setting that means it never touches the seized original: you instrument a **forensic copy** (an extracted IPA re-signed with the gadget, or — for analysis fidelity short of the device — the app built/run in the Simulator), on your own hardware, under documented authorization. Record the exact Frida and agent versions, the script SHA-256, the target's bundle ID + version + binary UUID (`otool -l`/`ipsw macho info`), and a transcript of every hook. An undocumented runtime hook that altered a value is indistinguishable, later, from evidence tampering. The *output* (captured keys, URLs, plaintext) is the artifact; the *method* must be reproducible.

## Hands-on

These run on your Mac. There is no on-device shell; the Simulator app is a native macOS process, so Frida talks to it locally.

**Install the toolchain** (Homebrew Python + pipx keeps it isolated):

```bash
pipx install frida-tools          # frida, frida-trace, frida-ps, frida-ls-devices, frida-kill
frida --version                   # → 17.15.3  (latest as of 2026-06-22)
frida-ls-devices                  # local + any USB devices
# Id            Type    Name
# local         local   Local System
```

**Boot a Simulator and install a target app:**

```bash
xcrun simctl list devices available | grep -i booted   # what's running
xcrun simctl boot "iPhone 17 Pro"                       # boot a device (UDID also works)
# Build your sample app to the Simulator (Xcode, or):
xcrun simctl install booted /path/to/MyApp.app
xcrun simctl launch booted com.example.MyApp            # note the returned PID
```

**Find and attach to the process:**

```bash
frida-ps | grep -i myapp                 # local processes; Simulator apps appear here
# 50321  MyApp
frida -p 50321                           # interactive REPL inside the process
# [Local::PID::50321 ]->  ObjC.available
# true
# [Local::PID::50321 ]->  Object.keys(ObjC.classes).length
# 14237
```

**Hook before the app finishes launching** (the Simulator workaround for the broken `-f`):

```bash
# Launch suspended waiting for a debugger, capture the PID, attach, then resume.
PID=$(xcrun simctl launch --wait-for-debugger booted com.example.MyApp | awk '{print $NF}')
frida -p "$PID" -l early-hook.js          # your hooks install while the app is paused
# the app proceeds once Frida resumes it — you've caught it before -[AppDelegate application:didFinishLaunching…]
```

This recovers most of the value of device-side spawn-gating (`frida -U -f`) on the Simulator: your hooks are in place before app code runs. For the rest, embed the Simulator gadget (`frida-gadget-<ver>-ios-simulator-universal.dylib`) into the `.app` and load a bundled script via its config.

**Trace an ObjC method and a C function:**

```bash
frida-trace -p 50321 -m '-[NSString stringWithUTF8String:]' -i 'open'
# Instrumenting...
# open: Auto-generated handler __handlers__/libsystem_kernel.dylib/open.js
# -[NSString stringWithUTF8String:]: Auto-generated handler at __handlers__/...
#            /* TID 0x103 */
#   1234 ms  -[NSString stringWithUTF8String:]
#   1240 ms  open(path="/var/.../Documents/db.sqlite", oflag=0x2)
```

Edit `__handlers__/.../open.js` to dump more; saving hot-reloads it live.

**Scan the live process for a decrypted secret** (REPL one-liner — find a token the app decoded at launch and never wrote to disk):

```js
// In the frida -p <pid> REPL:
const m = Process.enumerateModules()[0];               // the app's own image
Memory.scan(m.base, m.size, '41 50 49 5f 4b 45 59', {  // hex of "API_KEY"
  onMatch(addr) { console.log(addr + '  ' + addr.readUtf8String(64)); },
  onComplete() {}
});
```

**Quick wins with objection** (a Frida-built toolkit; no script writing):

```bash
objection -g 50321 explore            # attach by PID; opens an interactive shell
# ios hooking list classes            # enumerate ObjC classes
# ios hooking watch class MyGate      # auto-hook every method of a class
# ios keychain dump                   # (device) read the keychain via SecItem hooks
# ios jailbreak disable               # neutralize common jailbreak checks
```

**Run a script file** (the durable workflow — version-control your agent):

```bash
frida -p 50321 -l trace_urls.js          # attach + load agent
# For a frida-compile/TypeScript agent, build first, then -l the bundle:
# frida-compile agent.ts -o agent.js && frida -p 50321 -l agent.js
```

**Capture script output as data** (forensic transcript):

```bash
frida -p 50321 -l capture_keys.js -o /tmp/frida-keys-$(date +%Y%m%dT%H%M%S).log
shasum -a 256 capture_keys.js            # record the agent hash for chain of custody
```

> ⚠️ **ADVANCED — device path (no device here; narrate only).** On a *jailbroken* device you'd install `frida-server` (e.g. via the Frida APT repo on a rootless JB), confirm it with `frida-ps -Uai` (USB, apps + identifiers), then `frida -U -f com.example.app -l agent.js --no-pause` to **spawn** the app suspended and hook before `main()`. The `-U` selects the USB device; `-f` spawns; `--no-pause` resumes after the agent loads. None of this is reproducible without hardware + a current jailbreak — see [[the-jailbreak-landscape-2026]].

## 🧪 Labs

> ⚠️ **All labs run against the iOS Simulator (a native macOS process) — no device, no jailbreak.** Fidelity caveat for every lab below: a Simulator app is **arm64 macOS**, running the Simulator runtime's frameworks under the host XNU kernel with **no AMFI, no app sandbox, no SEP, no Data Protection, and no FairPlay** (Simulator binaries are *not* FairPlay-encrypted). Device-only daemons (`knowledged`, `biomed`, `powerlogHelperd`, `routined`) do not run, so behaviors that depend on them won't fire. The labs teach the **Frida API and method** — `Interceptor`, the ObjC bridge, `frida-trace`, swizzling — which transfer 1:1 to a device; they do **not** teach FairPlay decryption or anti-jailbreak realism, which are device/sample-image topics.

### Lab 1 — Attach to a Simulator app and explore the ObjC runtime *(substrate: Simulator)*

1. Boot a device and launch any app you can install to the Simulator. The cleanest authorized target is a self-built crackme: clone **OWASP iGoat-Swift** or **DVIA-v2** and build the Simulator scheme in Xcode (both build to the Simulator from source — no signing required). A plain Xcode "App" template works too.
2. `frida-ps | grep -i <AppName>` to get the PID, then `frida -p <pid>`.
3. In the REPL: `ObjC.available` (→ `true`), `Object.keys(ObjC.classes).length`, and pick a class: `ObjC.classes.UIApplication.sharedApplication().toString()`.
4. Heap-scan for live instances of a model class: `ObjC.choose(ObjC.classes.NSURL, { onMatch(o){ console.log(o.absoluteString()); }, onComplete(){} })`.
5. **Deliverable:** the count of registered classes, and one live instance you found with `ObjC.choose`. Note in your log that this is a host process (no sandbox) — contrast with how you'd reach the same runtime on a device.

### Lab 2 — `frida-trace` an Objective-C method and edit the handler *(substrate: Simulator)*

1. Pick a method your app calls often — e.g. `frida-trace -p <pid> -m '-[NSString stringWithUTF8String:]'` (or a method from your own app's class via `-m '-[MyViewController *]'`).
2. Watch the live call tree print. Open the generated `__handlers__/.../*.js`.
3. In `onEnter`, log `args[2].readUtf8String()` (the C string for that selector); save — note it **hot-reloads** with no restart.
4. Add an `onLeave` that prints `new ObjC.Object(retval).toString()`.
5. **Deliverable:** the edited handler and a sample of captured strings. Explain why `args[0]`/`args[1]` are `self`/`_cmd` and the real arg starts at `args[2]`.

### Lab 3 — `Interceptor` on a native C function, observe and modify *(substrate: Simulator)*

1. Write `agent.js`:

```js
Interceptor.attach(Module.getGlobalExportByName('open'), {
  onEnter(args) { this.p = args[0].readUtf8String(); },
  onLeave(retval) {
    if (this.p) console.log('open("' + this.p + '") = ' + retval.toInt32());
  }
});
```

2. `frida -p <pid> -l agent.js`. Interact with the app; watch every file it opens (you'll see its container DB, plists, caches).
3. Now **modify**: make `open()` on a path containing `Caches` return `-1` (`retval.replace(ptr(-1))` in `onLeave`) and observe how the app reacts to the "missing" file.
4. **Deliverable:** the list of paths the app opened and a one-line note on what changed when you forced a failure. This is the same hook shape you'd use to spoof a jailbreak-marker check (`/Applications/Cydia.app`, `/private/var/jb`).

### Lab 4 — Swizzle a method return value to flip app behavior *(substrate: Simulator)*

1. Find a `BOOL`-returning method that gates behavior — in iGoat/DVIA, a jailbreak-detection or "is-secure" check; in your own app, write one (`-(BOOL)isPremium`).
2. Replace its implementation so it always returns `YES`:

```js
const m = ObjC.classes.MyGate['- isPremium'];        // adjust class/selector
const orig = m.implementation;
m.implementation = ObjC.implement(m, function (self, sel) {
  console.log('isPremium called → forcing YES');
  return 1;                                            // ObjC BOOL = 1
});
```

3. Trigger the gated feature in the UI; confirm it now unlocks.
4. **Deliverable:** before/after behavior, and a note on the difference between `Interceptor.attach` (observe, then optionally `retval.replace`) and reassigning `.implementation` (full swizzle). This is the conceptual core of [[objection-swizzling-and-runtime-exploration]].

### Lab 5 — Runtime exploration with objection (no scripts) *(substrate: Simulator)*

1. `objection -g <pid> explore` to attach to your Simulator app.
2. `ios hooking list classes` then `ios hooking search methods <keyword>` to map the attack surface without opening a disassembler.
3. `ios hooking watch class <YourClass>` and exercise the UI — objection auto-hooks every method and prints the live call/return flow (it's `frida-trace` with a pre-built ObjC agent under the hood).
4. Try `ios hooking set return_value <method> false` to flip a gate, mirroring Lab 4 with zero JavaScript.
5. **Deliverable:** the watched call trace and one flipped return. Note that objection is *built on* the Frida API you learned — every command maps to `Interceptor`/`ObjC` calls. (Keychain/jailbreak commands are device-meaningful; on the Simulator they have nothing to read or detect.)

### Lab 6 — Read-only walkthrough: the jailbroken-device `frida-server` flow *(substrate: narrated; no device)*

You can't run this, but you must be able to **describe** it, because it's the standard professional path:

1. Jailbreak a compatible device (**A8–A11 / checkm8, iOS ≤ 18.7.x, palera1n**; there is no public kernel jailbreak for A12+) — [[the-jailbreak-landscape-2026]].
2. Install `frida-server` from the Frida repo (rootless layout on modern JBs); confirm `frida-ps -Uai` lists installed apps **with bundle IDs**.
3. `frida -U -f com.target.app -l agent.js --no-pause` — spawn-gate the app and hook before `main()`, the property the Simulator can't give you.
4. Note what's now in scope that the Simulator lacked: **FairPlay-encrypted** binaries (decryptable in-memory → `frida-ios-dump`), the **real keychain + Data Protection** classes, and genuine anti-jailbreak code to bypass.
5. **Deliverable:** a short comparison table — what the Simulator faithfully reproduces (the ObjC/Swift runtime, the framework APIs, the Frida API itself) vs. what only the device provides (SEP, Data Protection at rest, FairPlay, real daemons, real anti-analysis).

## Pitfalls & gotchas

- **`frida -f` does not spawn Simulator apps.** `launchd_sim` has no fixed PID (issue #3376). Launch with `xcrun simctl launch` (or Xcode, or `--wait-for-debugger`) and **attach by PID**. Don't burn an hour assuming `-f` is broken globally — it works fine on macOS and on devices; it's specifically the Sim launchd path.
- **The bridges aren't global in compiled agents (Frida 17+).** `ObjC`/`Swift` are auto-injected only in the REPL and `frida-trace`. In a `frida-compile` agent you must `import ObjC from 'frida-objc-bridge'`. A script that worked in the REPL and throws `ObjC is not defined` as a loaded agent is hitting exactly this.
- **Frida 17 removed the static `Module.*` lookups.** `Module.getExportByName()`, `Module.findExportByName()`, and `Module.enumerateExports/Imports/Symbols()` (plus `Module.get/findBaseAddress()`) were all deleted in **Frida 17.0.0** (May 2025). Use `Module.getGlobalExportByName('open')` for a global search and `Process.getModuleByName('libsystem_kernel.dylib').getExportByName('open')` / `.enumerateSymbols()` for a module-scoped one. An old script that calls `Module.getExportByName(...)` throws `TypeError: Module.getExportByName is not a function` on any 17.x install — the most common porting break after the bridge externalization. (`Process.enumerateModules()`/`Process.getCurrentThreadId()` are unaffected.)
- **`args[0]` and `args[1]` are `self` and `_cmd` for ObjC methods.** Every Objective-C method secretly takes the receiver and selector first; the first *declared* argument is `args[2]`. Off-by-two here silently reads garbage pointers.
- **The Simulator is not iOS.** It's the single biggest fidelity trap: no AMFI/sandbox/SEP, host kernel, **not FairPlay-encrypted**. Anti-jailbreak and FairPlay-dump labs are *meaningless* on the Simulator — they have nothing to detect or decrypt. Use it for runtime/API skill; use device or sample images for the encryption/lock-state story.
- **`Interceptor` patches the prologue — anti-tamper can see it.** Apps that checksum their own `__TEXT` will notice the trampoline. Prefer `Stalker` (no prologue patch) or hook *above* the integrity check, and read [[anti-tamper-pinning-and-detection-both-sides]] before you assume a hook is invisible.
- **Pure-Swift hooking ≠ ObjC hooking.** If a class isn't `@objc`/`NSObject`-derived, it won't appear in `ObjC.classes`; you need the Swift bridge or `Process.getModuleByName(app).enumerateSymbols()` + demangling, and value types passed in registers break the naïve `args[n]` model. Check `ObjC.classes` first; many "Swift" apps are ObjC-bridged where it counts.
- **Version skew between host frida-tools and device `frida-server`.** On the device path, the `frida-server` build **must** match your host `frida` major/minor or the session won't establish. (Not a Simulator concern — there both sides are your one local install.)
- **Hooking high-frequency functions can wedge the app.** `console.log` in an `onEnter` that fires 10⁵×/sec floods the channel and stalls the UI. Aggregate in-script (`send()` batches, counters) and log summaries; scope `Stalker.follow` to one thread and a short window.
- **The host/agent boundary is async — don't expect a return value from `console.log`.** Your agent runs in the target; the CLI runs on your Mac. Data only crosses via `send()`/`recv()`/`rpc`. A common mistake is computing a value in `onEnter` and expecting the host to "have" it — you must `send()` it, and for binary, ride it in the raw `data` arg, not stringified JSON.
- **`Module.getGlobalExportByName(sym)` searches *all* modules — be specific.** A global lookup resolves the *first* match across every loaded image, which can grab the wrong `open`/`malloc` if a framework re-exports it. Prefer the module-scoped `Process.getModuleByName('libsystem_kernel.dylib').getExportByName('open')` when it matters.
- **Reading a freed or unmapped pointer crashes the *target*, not your script.** A bad `readUtf8String()` on a dangling `NativePointer` segfaults the app you're examining. Validate with `ptr.isNull()` and wrap risky reads in `try { } catch (e) { }` — an uncaught native fault takes the process down and your session with it.
- **It's live acquisition.** Repeat for discipline: Frida modifies the running target. Never against a seized original; document versions, agent hash, and a transcript. (See the Forensics notes above.)

## Key takeaways

- Frida is a **host/agent** split: your JavaScript (GumJS) runs **inside** the target via frida-gum's C engine, driven remotely by frida-tools — the same engine you used on macOS.
- There are exactly **three injection models**: `frida-server` (jailbroken device, root, full spawn), `frida-gadget` (re-signed app, no jailbreak, the app loads Frida itself), and **attaching to a Simulator process** (native macOS process you own — the no-device path).
- The **instrumentation API is identical across models**. Master `Interceptor` (hook/replace), `Stalker` (trace), `Memory`/`Module`/`NativeFunction` (substrate), and the **ObjC/Swift bridges**, and the skill transfers from Simulator to device unchanged.
- **`frida-trace`** is the fastest first move: auto-generated, hot-reloading handlers for any function or ObjC method by glob.
- The **Simulator faithfully reproduces the runtime and the Frida API** but **not** AMFI/sandbox/SEP/Data-Protection/FairPlay — so it teaches method, not encryption/lock-state realism.
- Two current traps: **`frida -f` can't spawn Sim apps** (attach by PID instead), and since **Frida 17** the **bridges are external** (`import ObjC from 'frida-objc-bridge'` in compiled agents; global only in the REPL/`frida-trace`).
- Dynamic analysis reaches what static can't: **runtime-decrypted code/strings, crypto keys and pre-encryption plaintext, pre-TLS network payloads, and true control flow** — the forensic and RE payoff.
- Frida is **live acquisition**: authorized targets only, forensic copies not originals, every hook documented and the agent hashed.

## Terms introduced

| Term | Definition |
|---|---|
| Frida | Dynamic instrumentation toolkit that injects a JS runtime into a live process to hook/trace/modify it |
| frida-gum | Frida's C instrumentation core (Interceptor, Stalker, Memory, Module); the engine the JS API drives |
| GumJS | The embedded JavaScript runtime (QuickJS/V8) that runs your agent inside the target process |
| frida-core | Host-side library: device management, process injection, session + message transport |
| Agent | The JS/TS script that executes in-process inside the target |
| frida-server | Privileged (root) Frida daemon run on a jailbroken device; host connects over USB |
| frida-gadget | A `FridaGadget.dylib` embedded into a re-signed app so the app loads Frida itself (no jailbreak) |
| Simulator attach | Injecting Frida into a Simulator app, which on Apple Silicon is a native arm64 macOS process |
| Interceptor | Frida API that hooks a function/method via an inline prologue trampoline (`onEnter`/`onLeave`/`replace`) |
| Stalker | Frida's tracing engine using JIT recompilation of basic blocks; traces execution without patching prologues |
| ObjC bridge | `ObjC.classes`/`ObjC.Object`/`ObjC.choose` — JS access to the live Objective-C runtime |
| Swift bridge | `frida-swift-bridge` — Interceptor-like access to Swift types; pure-Swift is harder than `@objc` Swift |
| frida-trace | CLI that auto-generates editable, hot-reloading handler stubs for matched functions/ObjC methods |
| NativeFunction / NativeCallback | JS wrappers to *call* a target function, or build a native function from JS (used by `Interceptor.replace`) |
| Swizzling | Replacing an Objective-C method's `.implementation` at runtime to change its behavior |
| launchd_sim | The Simulator runtime's per-instance launchd; lacks a fixed PID, which is why `frida -f` can't spawn Sim apps |

## Further reading

- **Frida docs** — frida.re: *JavaScript API*, *Stalker*, *Bridges*, *iOS* guide; the *Frida 17.0.0 released* post (bridge externalization). Always check the live docs — the API moves.
- **frida-swift-bridge** — github.com/frida/frida-swift-bridge (`docs/api.md`); maltek/swift-frida (predecessor, for background).
- **OWASP MASTG/MASVS** — *MASTG-TOOL-0031: Frida*; *MASTG-TECH-0090: Injecting Frida Gadget into an IPA Automatically*; the iGoat-Swift / UnCrackable crackmes ([[owasp-mastg-and-app-security-testing]]).
- **objection** — github.com/sensepost/objection (`patchipa`, jailbroken/jailed wikis); the Frida-built runtime toolkit ([[objection-swizzling-and-runtime-exploration]]).
- **frida-ios-dump / bagbak** — FairPlay in-memory dump via Frida ([[fairplay-encryption-and-decrypting-app-store-apps]]).
- **Books/refs** — Jonathan Levin, *MacOS and iOS Internals* (Mach injection, task ports — newosxbook.com); David Thiel, *iOS Application Security*; the Frida HandBook (learnfrida.info).
- **Tooling** — `man codesign`, `xcrun simctl help`, `frida --help`, `frida-trace --help`; ios-deploy, applesign (re-signing for the gadget path).

---
*Related lessons: [[static-analysis-class-dump-and-disassemblers]] | [[objection-swizzling-and-runtime-exploration]] | [[fairplay-encryption-and-decrypting-app-store-apps]] | [[certificate-pinning-and-bypass]] | [[anti-tamper-pinning-and-detection-both-sides]] | [[simulator-internals-and-on-disk-filesystem]] | [[the-jailbreak-landscape-2026]]*
