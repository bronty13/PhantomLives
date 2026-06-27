---
title: "FairPlay encryption & decrypting App Store apps"
part: "11 — Reverse Engineering & App Security"
lesson: 03
est_time: "45 min read + 20 min labs"
prerequisites: [mach-o-arm64-deep-dive, the-app-bundle-and-ipa-structure]
tags: [ios, re, fairplay, decryption, app-security]
last_reviewed: 2026-06-26
---

# FairPlay encryption & decrypting App Store apps

> **In one sentence:** every App Store binary ships with its `__TEXT` code wrapped in FairPlay DRM that is decrypted *only in RAM at exec time by a kernel/daemon path with no static key on disk* — so step zero of any authorized iOS app assessment is to capture those decrypted pages off a running process, splice them back over the encrypted range, and flip `cryptid` to `0`.

---

> ⚖️ **AUTHORIZED USE ONLY.** Everything below is written for lawful, scoped work: reversing **apps you wrote**, apps you are **contractually authorized to assess** (a signed pentest engagement / SOW), or **bona-fide security research** within your jurisdiction's exemptions. Decrypting an App Store binary is *circumventing a technological protection measure* — DMCA §1201 in the US (with a narrow security-research exemption), comparable provisions elsewhere. Stripping FairPlay to **redistribute** a paid app is piracy, full stop. Keep RE scoped to binaries you own or are authorized to analyze, document what you touched, and never publish a decrypted Store binary.

> ⚠️ **ADVANCED / DEVICE-BOUND.** The actual decryption step requires running the target on a device you control (jailbroken, or developer-provisioned with an injected Frida gadget). This course has **no physical device**, so every device step here is a **narrated read-only walkthrough**, paired with device-free labs that exercise the same *downstream* static-analysis skill on binaries that are already plaintext (Simulator builds, OWASP crackmes). Do not attempt the device path against hardware or apps you are not authorized to touch.

---

## Why this matters

You cannot `class-dump` an App Store app. You cannot point Ghidra, Hopper, IDA, or Binary Ninja at a freshly-downloaded `.ipa` and read its code — the bytes in the encrypted range disassemble to convincing-looking garbage that will eat hours before you realize the file was never plaintext. FairPlay is the single biggest day-one difference between reversing macOS and reversing iOS: on macOS the binaries you care about (Homebrew tools, notarized Developer-ID apps, open source) are almost never FairPlay'd; on iOS, **every** Store executable is. So "get a clean decrypted binary" is the gate every iOS RE workflow passes through before any of the static/dynamic techniques in the rest of Part 11 apply. Knowing *exactly* where that gate is — what's encrypted, what isn't, what produces the key, and why the file on disk can never contain it — is what separates someone who decrypts deliberately from someone who flails. For the forensic examiner it matters too: the FairPlay payload on disk (`SC_Info/`, `iTunesMetadata.plist`) is itself an artifact that ties an installed app to an **Apple Account and a device**.

---

## Concepts

### The encryption boundary: what FairPlay actually covers

FairPlay encrypts a **single contiguous byte range of one Mach-O executable** — the app's main code in `__TEXT` — and records that range in one load command, `LC_ENCRYPTION_INFO_64` (the 32-bit variant `LC_ENCRYPTION_INFO` is legacy; arm64 store apps are all 64-bit). You met this struct in [[mach-o-arm64-deep-dive]]; here is the whole thing because three of its fields are the entire lesson:

```c
struct encryption_info_command_64 {
    uint32_t cmd;        // LC_ENCRYPTION_INFO_64  == 0x2C  (the 32-bit cmd LC_ENCRYPTION_INFO == 0x21)
    uint32_t cmdsize;    // sizeof(struct) == 24
    uint32_t cryptoff;   // file offset where the encrypted range begins
    uint32_t cryptsize;  // number of bytes encrypted
    uint32_t cryptid;    // 0 = NOT encrypted; 1 = FairPlay-encrypted
    uint32_t pad;        // 8-byte alignment (the 32-bit struct has no pad)
};
```

Field semantics, the parts that bite:

| Field | Meaning | Typical value on a store binary |
|---|---|---|
| `cryptid` | **The whole tell.** `0` ⇒ plaintext, disassemble now. `1` ⇒ ciphertext, decrypt first. | `1` |
| `cryptoff` | Start of the encrypted range, **file offset**, page-aligned. | `0x4000` (16 KB — one arm64 page past the header/load-commands) |
| `cryptsize` | Length of the encrypted range, a multiple of the FairPlay crypt page (`0x1000`). | varies; covers the code pages of `__TEXT` |

Three facts that scope your work precisely:

- **Only `[cryptoff, cryptoff+cryptsize)` is ciphertext.** Everything outside it — the Mach-O header, the load-command stream, `__DATA`, `__LINKEDIT`, the symbol table, the code-signature blob — is **plaintext on disk**. You can read entitlements, linked dylibs, the symbol table, and Objective-C/Swift type metadata *that lives outside `__TEXT`* without ever decrypting. Decryption only buys you the **code**.
- **It is per-executable, and that includes app extensions.** The main app binary carries its own `LC_ENCRYPTION_INFO_64 cryptid 1`; **so does every `PlugIns/*.appex/<name>` extension** (share/widget/notification-service/etc.), each an independent `MH_EXECUTE`. They decrypt separately and must be dumped separately — this is why `bagbak`/`dumpdecrypted` run a distinct pass per extension.
- **Embedded frameworks and dylibs are usually NOT encrypted.** `Frameworks/*.framework/<name>` and bundled `*.dylib` typically have **no** `LC_ENCRYPTION_INFO_64` (or `cryptid 0`), so you can analyze third-party SDKs and your own dynamic libraries statically with zero device steps. Check each one; don't assume.

The older marker `SG_PROTECTED_VERSION_1` in a segment's `flags` is the historical "this segment is protected/encrypted" bit; modern App Store encryption is expressed through `LC_ENCRYPTION_INFO_64`, and that's what every current tool keys on.

> 🖥️ **macOS contrast:** macOS *has* FairPlay — Mac App Store apps can ship encrypted, and you'll occasionally see `cryptid 1` on a Mac binary. But the overwhelming majority of Mac binaries you reverse (CLI tools, open-source apps, Developer-ID apps distributed outside the store, system binaries) are **never** FairPlay'd, so on macOS you almost always start from plaintext. On iOS the default inverts: store apps are encrypted by default, and "decrypt first" is the unconditional first move. Same load command, opposite base rate.

### What you can still read on an *encrypted* binary (no decrypt needed)

Because only `__TEXT`'s code range is encrypted, a `cryptid 1` binary leaks a surprising amount before you ever touch a device. Reaching for a decrypt when a plaintext read would answer the question wastes a (gated) device pass. The split:

| Readable on `cryptid 1` (plaintext on disk) | Needs decryption (inside `[cryptoff, cryptsize)`) |
|---|---|
| Mach-O header, all load commands, `cputype`/`cpusubtype` | The actual function bodies / instructions in `__TEXT,__text` |
| Linked dylibs/frameworks (`LC_LOAD_DYLIB`), min-OS (`LC_BUILD_VERSION`) | Inlined string literals stored in encrypted `__TEXT` sections |
| Entitlements + code-signature metadata (`codesign -d`) | — |
| Symbol table / imports-exports in `__LINKEDIT` (`nm`) | — |
| Objective-C class/method **names** in `__DATA*,__objc_*` (often outside the crypt range) | The *implementation* of those methods |
| Swift type/reflection metadata in `__TEXT,__swift5_*` **if** it falls outside `[cryptoff,cryptsize)` | Swift function bodies in the encrypted range |
| `Info.plist`, bundled assets, `embedded.mobileprovision` | — |

So you can frequently map the **shape** of an app — its dependencies, declared classes/selectors, entitlements, and which third-party SDKs it embeds — purely statically, and only spend the device decrypt when you need the **logic** (the comparison in a license check, an obfuscated routine, a custom crypto implementation). Caveat: exactly *which* Objective-C and Swift metadata sections fall inside vs. outside `[cryptoff, cryptsize)` varies per binary — verify against the section offsets, don't assume.

### The on-disk DRM payload: `SC_Info`, `sinf`/`supp`/`supf`, and `iTunesMetadata.plist`

When you download an app, the IPA that lands on the device is not just the `.app` bundle. FairPlay's licensing material rides alongside it, and it is **forensically meaningful** because it binds the install to an account and device:

```
Payload/
  MyApp.app/
    MyApp                       ← MH_EXECUTE, cryptid 1   (encrypted)
    SC_Info/
      MyApp.sinf                ← per-purchase license: Apple Account / purchase record
      MyApp.supp / .supf        ← key material used to derive the decryption key (itself wrapped)
      Manifest.plist            ← lists which .sinf applies to which executable
    PlugIns/Share.appex/Share   ← cryptid 1 (encrypted, separate license scope)
    Frameworks/Lib.framework/Lib ← usually cryptid 0 (clear)
iTunesMetadata.plist            ← app itemId, version external id, the downloading Apple Account
```

- **`.sinf`** is the DRM license — it carries the **Apple Account identifier and purchase record** that the app is licensed to. This is why a binary decrypted on *your* device is keyed to *your* account; the ciphertext on disk is not portable.
- **`.supp` / `.supf` / `.supx`** carry the key material; the actual content key is wrapped and only unwrapped inside the FairPlay path (below). There is **no plaintext content key sitting in these files** — that's the design.
- **`iTunesMetadata.plist`** (at the IPA root, outside the `.app`) records the app's `itemId`, `softwareVersionExternalIdentifiers`, and the **Apple Account that downloaded it** — gold for attribution.

> 🔬 **Forensics note:** Presence of `SC_Info/` + a populated `iTunesMetadata.plist` is a reliable signal that an app came from the **App Store** (vs. an enterprise/MDM/sideloaded build, which has no FairPlay licensing payload). In a full-file-system acquisition the installed-app bundles live under `/private/var/containers/Bundle/Application/<UUID>/`; the `iTunesMetadata.plist`'s account fields tie the install to a specific Apple Account, and the `.sinf` corroborates it. A sideloaded/Frida-gadget'd or developer-signed build will be conspicuously **missing** these — itself an indicator the app was not store-provisioned.

### The runtime decryption path: why there is no key on disk

This is the crux. FairPlay decryption is **not** "apply a key in the file to the ciphertext." The file deliberately contains no usable content key. Decryption happens **at exec time, in the kernel and a system daemon**, and the plaintext only ever exists as **RAM pages mapped into the running process**:

```
exec(MyApp)
   │  dyld maps the Mach-O; sees LC_ENCRYPTION_INFO_64, cryptid 1
   ▼
kernel: vm_fault on a page in [cryptoff, cryptoff+cryptsize)
   │  the FairPlayIOKit kernel driver intercepts
   ▼
MIG up-call → fairplayd (user-space daemon, invoked via AMPLibraryAgent; CoreFP is the library)
   │  fairplayd reads SC_Info/*.sinf + *.supp/.supf, unwraps the content key
   │  (key derivation is device/SEP-bound; the wrapped key ≠ a usable key)
   ▼
kernel decrypts the page IN PLACE in the process's address space
   ▼
__TEXT pages are now plaintext IN RAM ONLY — never written back to the file
```

Note the asymmetry: the **wrapped** key travels in the IPA's `SC_Info` files, but unwrapping it requires the SEP-anchored device path — so possessing the files buys you nothing without the device. The kernel primitive that does the page-level decrypt is exposed to user space as **`mremap_encrypted(2)`** (BSD syscall **#489**, `AUE_MPROTECT`, compiled in only when XNU is built with `CONFIG_CODE_DECRYPTION`): given a mapped region plus `cryptid`, `cputype`, and `cpusubtype`, it asks the FairPlay path to decrypt that range into the mapping. dyld effectively drives this transparently for the app's own `__TEXT`; **decryption tools call it deliberately on a fresh mapping of the binary** to force plaintext without running the full app (more below).

Two consequences you must internalize:

1. **The key is device-bound and ephemeral.** It is derived through the SEP-anchored FairPlay path for *this* account on *this* device; it never materializes as a static value you could copy. So you cannot "extract the key and decrypt offline" — there is nothing to extract. You must capture the **output** (the plaintext pages), not the key.
2. **Therefore decryption ≡ memory capture.** Every tool, old or new, is a variation on: *get the plaintext `[cryptoff, cryptsize)` bytes out of a process where the OS has already decrypted them, write them over the encrypted range of a copy of the file, set `cryptid = 0`.*

### The universal decryptor recipe (and its three flavors)

The recipe never changes; only *how you obtain the plaintext pages* differs:

```
1. Run / instrument the target on a device you control.
2. Obtain the decrypted [cryptoff, cryptoff+cryptsize) bytes from process memory.
3. Open a copy of the on-disk Mach-O; overwrite that file range with the bytes.
4. Set LC_ENCRYPTION_INFO_64.cryptid = 0  (and, optionally, zero cryptoff/cryptsize).
5. Re-pack the .app into an .ipa.  Now it is a plain Mach-O: class-dump / disassemble freely.
```

Always keep the **original encrypted IPA** alongside the dump: it is your evidence-of-provenance (hash it before you touch it), and the diff between the two is itself documentation of exactly which bytes the decrypt changed (the `[cryptoff, cryptsize)` range plus the one `cryptid` field). Never overwrite the original in place.

Three flavors, by how they execute step 2:

- **Read-from-own-process-memory** *(classic — `dumpdecrypted`)*. A small `.dylib` is injected via `DYLD_INSERT_LIBRARIES` into the launching app; from *inside* the process it reads its own already-decrypted `__TEXT` pages and writes the file. Simple, but only ever decrypts the binary it was injected into (run again per extension).
- **`mremap_encrypted` on a fresh mapping** *(`bfdecrypt`/`bfinject` lineage)*. Instead of trusting the loader's mapping, the tool `mmap`s the file itself and calls `mremap_encrypted(2)` to force the kernel to decrypt that region directly — more robust against ASLR/segment quirks, and the most *mechanism-faithful* approach (it drives the exact kernel primitive dyld uses). Caveat: the syscall rejects non-page-aligned addresses, which broke the naïve `bfdecrypt` path for many apps once 16 KB pages became universal on arm64 — later tools (`fouldecrypt`) work around it with kernel read/write instead of the bare syscall, so treat "just call `mremap_encrypted`" as version-dependent.
- **Frida-orchestrated** *(`frida-ios-dump`, `bagbak`)*. Frida attaches to the running app from your Mac over USB, walks the loaded images, reads the decrypted ranges, and streams them back; the host-side script repacks the IPA, **including app extensions** in separate passes. This is the dominant 2026 workflow because it's scriptable from the Mac and doesn't need you to build/sign a dylib.

> 🖥️ **macOS contrast:** The closest macOS reflex is dumping a packed/obfuscated binary's unpacked image from memory (e.g., reading `__TEXT` out of a running process with `lldb`/`vmmap`+`memory read`). FairPlay turns that *optional* macOS trick into the *mandatory* iOS first step — and adds the wrinkle that the plaintext exists **only** in RAM because the kernel decrypts per-page on fault, never to disk.

### The 2026 tool landscape

Durable: the recipe above. Perishable: which tool is maintained and what it needs. Verify maintenance status at author time — these move.

| Tool | Mechanism | Requires | 2026 status / caveat |
|---|---|---|---|
| `frida-ios-dump` (AloneMonkey) | Frida attach + memory dump, host-side repack | Jailbroken **or** Frida-gadget'd device; Frida 17.x; SSH/usbmux | The default modern choice; actively used; Python3 host script. |
| `bagbak` (ChiChou) | Frida-based; decrypts app **+ extensions** | Jailbroken device; Frida 17.x (bagbak v5) | Marked **deprecated** by author but still widely used; best at extensions. |
| `flexdecrypt` / `flexdump` (JohnCoates) | On-device decryptor + IPA packer | Jailbroken device (`.deb`) | On-device; convenient when you already have a shell on the device. |
| `dumpdecrypted` (stefanesser / AloneMonkey fork) | `DYLD_INSERT_LIBRARIES` dylib, self-read | Jailbroken device; per-binary | The original; educational; one binary per run. |
| `bfdecrypt` / `bfinject` | `mremap_encrypted` on a fresh map | Jailbroken device | The "correct" syscall-driven approach; good fallback. |
| `yacd` (DerekSelander) | No-JB FairPlay decrypt | **iOS ≤ 13.4.1 only** | Historical; the no-jailbreak path it used was patched. Don't expect it on modern iOS. |

> ⚠️ **ADVANCED — getting a device you can dump on is itself gated.** To execute step 1 you need either (a) a **jailbreak** — `palera1n` covers **iOS 15.0–18.7.x** on bootrom-exploitable silicon (`checkm8` A8–A11; `usbliter8` A12–A13 as of 2026-06-18), with **no public kernel jailbreak for A12+ on iOS 18/26** and **no public bootrom exploit at all for A14+** — or (b) a **developer-provisioned, non-jailbroken** device where you **re-sign the IPA with your own developer certificate and inject the Frida gadget** (the "locked up but not locked out" path). A bootrom exploit gives code-exec *below* signature checks but is **not** a jailbreak and does **not** by itself defeat SEP/Data-Protection/passcode — you still need the device unlocked (AFU) with the user's keys. The newest apps on the newest hardware therefore have the **highest** acquisition bar. See [[the-jailbreak-landscape-2026]].

### The no-jailbreak re-sign path (and why it still needs a device)

You can decrypt **without** a jailbreak on a device you own:

1. Obtain the encrypted IPA (e.g., `ipatool` downloads it under your Apple Account — still FairPlay'd to you).
2. Re-sign the `.app` with **your** Apple developer certificate + provisioning profile, **injecting a Frida gadget** (`Frameworks/FridaGadget.dylib`) via an added `LC_LOAD_DYLIB` / re-codesign (tools: `frida` `--gadget`, `objection patchipa`, `Sideloadly`).
3. Install to a developer-enabled (Developer Mode ON) device and run it. The OS **still decrypts `__TEXT` at exec** — FairPlay decryption is keyed to the *download account/device*, and you downloaded it — so the gadget can read the plaintext pages and dump exactly as `frida-ios-dump` would.

The hard requirement that never goes away: **a real device that will execute the binary**, because that's the only place the FairPlay path runs. A Simulator won't help — Simulator binaries are built for `PLATFORM_IOSSIMULATOR` on the host CPU and are **never FairPlay'd** (`cryptid 0`), so there's nothing to decrypt and nothing to learn about *device* decryption from them.

### After decryption you still need the dyld shared cache

A `cryptid 0` binary is *necessary* but not *sufficient* for full static analysis. Store apps are thin — almost every symbol they call (UIKit, Foundation, Swift runtime, CoreFoundation) lives in the **dyld shared cache**, not in the app binary. A decrypted app's import stubs are just branches into shared-cache addresses; a disassembler that doesn't have the cache will show you `bl 0x1a2b3c4d` with no idea it's `-[NSString stringWithFormat:]`. So a complete pipeline pairs the decrypted binary with the **matching-version shared cache** (extracted from an IPSW or a device image) loaded into Ghidra/IDA/Binary Ninja via their shared-cache loaders. The cache is itself **not** FairPlay-encrypted (it's signed system code, plaintext), so unlike the app it needs no decrypt step — just extraction. See [[the-dyld-shared-cache]] and [[dyld-shared-cache-and-amfi]]. Practical sequence: decrypt the app (this lesson) → obtain the cache for the same OS build → load both → now imports resolve to real symbol names.

### Detecting a decrypted / repacked binary (the investigative inverse)

The same `cryptid` field that gates *your* analysis also **betrays** a binary that has been tampered with. A binary that came from the App Store *should* be `cryptid 1` with a valid Apple-issued code signature over the encrypted bytes. After a dump-and-repack you have the opposite: `cryptid 0` over what *was* the encrypted range, and a code signature that **no longer matches** (the splice changed `__TEXT`; a re-signed dump carries a *developer* or ad-hoc signature, not Apple's). For an examiner triaging an installed app, the tells of a repacked/sideloaded build are:

- `cryptid 0` on a binary whose bundle *otherwise* looks store-provisioned (or, conversely, a store bundle missing `SC_Info/`).
- A code signature whose Team ID / authority isn't Apple's store signing, or an **ad-hoc** signature (`codesign -dv` shows no authority chain).
- A `FridaGadget.dylib` / extra `LC_LOAD_DYLIB` in the load commands, or `frida`/`cycript` strings — the fingerprint of a re-sign-and-instrument dump.

This matters in two directions: it's how anti-tamper code on the *defensive* side detects it's been decrypted (see [[anti-tamper-pinning-and-detection-both-sides]]), and it's how a forensic examiner flags an app that isn't the pristine store build.

> 🔬 **Forensics note:** In a full-file-system image, comparing each installed `MH_EXECUTE`'s `cryptid` and code-signature authority against "should be Apple-signed, `cryptid 1`" is a fast triage sweep for **tampered or sideloaded** apps — a binary that's `cryptid 0` with a non-Apple/ad-hoc signature inside an otherwise-store-looking bundle is a red flag worth pulling for deeper analysis. Pair it with the `iTunesMetadata.plist`/`SC_Info` presence check from Lab 3.

### FairPlay is stable; the *dumping substrate* is what moves

Durable vs. perishable, made explicit. The **mechanism** here barely changes year to year: `LC_ENCRYPTION_INFO_64`, the `fairplayd`/`FairPlayIOKit` path, `mremap_encrypted`, and the dump-and-`cryptid 0` recipe have held since the 64-bit transition. What changes — and what you must re-verify at author time — is the **substrate**: which devices can be jailbroken or bootrom-exploited, which OS versions a jailbreak covers, and which dumper tool is currently maintained. As of 2026-06-26 the boundary is `checkm8` (A8–A11) + `usbliter8` (A12–A13) for bootrom access, `palera1n` for iOS 15.0–18.7.x, **nothing public for A14+ / no kernel JB for A12+ on iOS 18/26**, and the no-jailbreak developer-re-sign path as the catch-all on devices you own. Treat those as perishable; re-check before relying on them.

### Where decryption sits in the RE pipeline

```
encrypted .ipa  ──(device + dump)──▶  cryptid-0 Mach-O  ──▶  static analysis        ──▶  dynamic analysis
(cryptid 1)        THIS LESSON          (plaintext code)      class-dump / Hopper /        Frida hooks /
                                                              Ghidra / IDA / BinNinja      objection
                                        [[static-analysis-class-dump-and-disassemblers]]   [[dynamic-analysis-with-frida]]
```

Decryption is **the gate**, not the goal. Everything downstream (class-dump, disassembly, the dyld-shared-cache cross-references, Frida instrumentation) assumes you already hold a `cryptid 0` binary. Get the gate wrong and every later step silently operates on noise.

---

## Hands-on

All commands run **on the Mac** — there is no on-device shell in this course. These inspect the FairPlay boundary, prove a binary is (or isn't) encrypted, and set up the device-free labs. (Substitute a real binary path for `"$APP"`.)

### Detect FairPlay: the one check that gates everything

```bash
# The canonical detector. No output on a Simulator/your-own build = no FairPlay.
otool -l "$APP" | grep -A4 LC_ENCRYPTION_INFO
# Encrypted store binary prints:
#       cmd LC_ENCRYPTION_INFO_64
#   cmdsize 24
#  cryptoff 16384          ← 0x4000
# cryptsize 1310720        ← multiple of 0x1000, covers __TEXT code
#   cryptid 1              ← ENCRYPTED — __TEXT is ciphertext until dumped

# Toolchain note: on a Command Line Tools-only Mac use the llvm spelling:
llvm-otool -l "$APP" | grep -A4 LC_ENCRYPTION_INFO

# Just the verdict, scriptable:
otool -l "$APP" | awk '/cryptid/{print ($2==1)?"ENCRYPTED":"plaintext"}'
```

### Pick the right slice first

```bash
# arm64 store binaries are usually single-arch already, but always check.
lipo -archs "$APP"          # e.g. "arm64"  (Simulator build on Apple Silicon: "arm64", PLATFORM_IOSSIMULATOR)
file "$APP"                 # Mach-O 64-bit executable arm64
# If fat, thin to the slice you'll analyze before anything else:
lipo "$APP" -thin arm64 -output /tmp/App.arm64
```

### Prove the decryption boundary scopes to `__TEXT`

```bash
# Where does the encrypted range fall? Compare cryptoff/cryptsize against section offsets.
otool -l "$APP" | grep -A2 -E 'sectname|segname __TEXT' | head
# __TEXT,__text typically begins at/after cryptoff. __DATA, __LINKEDIT, the
# symbol table, and the code-signature blob are OUTSIDE the range = readable now.

# These work even on an ENCRYPTED binary because they read plaintext regions:
otool -l "$APP" | grep -A5 LC_LOAD_DYLIB     # linked dylibs / SDKs
codesign -d --entitlements :- "$APP" 2>/dev/null   # entitlements (plaintext)
nm -arch arm64 "$APP" | head                  # symbol table (plaintext, in __LINKEDIT)
```

### Show that class-dump fails on ciphertext, succeeds on plaintext

```bash
# On an ENCRYPTED binary: class-dump reads garbage in the __TEXT range.
class-dump "$ENCRYPTED_APP"     # → empty / nonsense ObjC, or a decrypt warning
# On a cryptid-0 binary (Simulator build, OWASP crackme, or a properly dumped IPA):
class-dump "$PLAINTEXT_APP"     # → real @interface/@property/method declarations
```

### Build a known-plaintext Simulator binary to practice on

```bash
# A Simulator build is PLATFORM_IOSSIMULATOR and NEVER FairPlay'd (cryptid 0).
xcrun simctl list devicetypes | grep iPhone        # pick a device type
# (Build any SwiftUI/UIKit app for "Any iOS Simulator Device" in Xcode, or:)
APPBIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*Debug-iphonesimulator*/*.app/*' -type f -perm +111 -name '[A-Z]*' | head -1)"
otool -l "$APPBIN" | grep -c LC_ENCRYPTION_INFO    # → 0  (no FairPlay)
otool -l "$APPBIN" | grep -A2 LC_BUILD_VERSION     # platform 7 = IOSSIMULATOR
class-dump "$APPBIN" | head -30                     # real types — the plaintext baseline
```

### Prove the encrypted range is noise (and read the licensing payload)

```bash
# Carve the encrypted range out of an ENCRYPTED binary and confirm it's not code.
CRYPTOFF=$(otool -l "$APP" | awk '/cryptoff/{print $2}')
CRYPTSIZE=$(otool -l "$APP" | awk '/cryptsize/{print $2}')
dd if="$APP" bs=1 skip="$CRYPTOFF" count=64 2>/dev/null | xxd     # high-entropy bytes
# Disassembling that same range prints plausible-but-fake instructions:
otool -tv "$APP" 2>/dev/null | sed -n '1,20p'                    # garbage on cryptid 1

# Attribution: read the downloading Apple Account + itemId from an IPA root plist.
unzip -p target.ipa iTunesMetadata.plist | plutil -p - \
  | grep -E 'itemId|appleId|com.apple.iTunes|softwareVersionExternalIdentifiers'
# And confirm the FairPlay licensing payload exists (store-provisioned tell):
unzip -l target.ipa | grep -E 'SC_Info|\.sinf|\.sup'
```

### Inspect the code signature / look for tamper fingerprints

```bash
# A pristine store binary chains to Apple; a dumped/re-signed one does not.
codesign -dvvv "$BIN" 2>&1 | grep -E 'Authority|TeamIdentifier|flags|Signature'
# Tamper fingerprint of a re-sign-and-inject dump:
otool -L "$BIN" | grep -i -E 'frida|gadget|cycript|substrate'
otool -l "$BIN" | grep -A2 LC_LOAD_DYLIB | grep -i -E 'frida|gadget'
```

### jtool2 alternative (when you want one tool for header + signature)

```bash
# Levin's jtool2 reads the encryption command and the signature in one pass.
jtool2 -l "$APP" | grep -i ENCRYPTION      # LC_ENCRYPTION_INFO_64 with cryptid
jtool2 --sig "$APP"                          # code-signature / entitlements summary
```

### Verify a (hypothetically) dumped IPA

```bash
# After an AUTHORIZED device dump, the success criteria on the Mac are:
unzip -o dumped.ipa -d /tmp/dumped >/dev/null
BIN="$(find /tmp/dumped/Payload/*.app -maxdepth 1 -type f -perm +111 | head -1)"
otool -l "$BIN" | grep cryptid          # MUST read: cryptid 0
class-dump "$BIN" | head                 # MUST yield real ObjC type info
# Don't forget extensions — each must independently read cryptid 0:
find /tmp/dumped/Payload/*.app/PlugIns -name '*.appex' -maxdepth 1 2>/dev/null
```

---

## 🧪 Labs

> All labs are **device-free**. They teach the *boundary detection* and the *downstream static-analysis* skills that bracket the device-only decrypt step. None of them can produce a FairPlay-decrypted Store binary — that is irreducibly device-bound and is covered only as a narrated walkthrough (Lab 4).

### Lab 1 — Establish the plaintext baseline *(substrate: Xcode Simulator)*

**Fidelity caveat:** a Simulator binary is a `PLATFORM_IOSSIMULATOR` build on the **host CPU**, so it is plain `arm64` (never `arm64e`), carries **no FairPlay** (`cryptid 0`), and has **no code-signing/AMFI semantics**. It faithfully teaches the *plaintext* end-state of decryption (and that `class-dump`/disassembly work on it) but tells you nothing about the device decryption path itself.

1. Build any SwiftUI/UIKit app for the Simulator (or locate one under `~/Library/Developer/Xcode/DerivedData/.../Debug-iphonesimulator/`).
2. Run `otool -l "$APPBIN" | grep -c LC_ENCRYPTION_INFO`. Confirm `0`. This is what "decryption succeeded" looks like at the byte level — no encryption command, or `cryptid 0`.
3. Confirm the build platform with `LC_BUILD_VERSION` (`platform 7` = IOSSIMULATOR). Note *why* this binary will never be FairPlay'd.
4. Run `class-dump "$APPBIN"`. You get real `@interface`/method declarations. **This is the payoff of decryption** — internalize that the Store-app workflow exists only to reach this same state.

### Lab 2 — Full static pipeline on a pre-decrypted crackme *(substrate: public sample)*

**Fidelity caveat:** OWASP's UnCrackable iOS apps and `iGoat-Swift` are distributed **already plaintext** (built for analysis), so they stand in for "an app you have already legitimately decrypted." They exercise the exact post-decryption skillset against a *device-architecture* (`arm64`) binary the Simulator can't give you.

1. Get an OWASP MASTG iOS crackme / `iGoat-Swift` build (MASTG repo / `MASTG-APP-0028`). Unzip the `.ipa`; find the `Payload/*.app/<binary>`.
2. Prove it's plaintext: `otool -l "$BIN" | grep cryptid` → `cryptid 0` (or no encryption command).
3. `class-dump "$BIN"` → enumerate classes. Find the obvious challenge classes (e.g., a `*ViewController`, a verification/`check`/`secret` method).
4. Open the binary in Ghidra/Hopper/Binary Ninja and locate that method. Read the comparison logic. (This is precisely the analysis that is *impossible* on an encrypted Store binary — which is the entire reason for the decrypt step.)

### Lab 3 — Anatomy of the FairPlay/DRM payload *(substrate: read-only walkthrough + Simulator contrast)*

**Fidelity caveat:** you cannot lawfully produce a Store IPA's `SC_Info/` here, so the licensing payload is studied on paper; the *absence* of it is verified on a real Simulator bundle.

1. From the **Concepts** layout, write down what each licensing file binds: `.sinf` → Apple Account / purchase record; `.supp`/`.supf` → wrapped key material; `Manifest.plist` → sinf↔executable mapping; `iTunesMetadata.plist` → downloading account + `itemId`.
2. On your **Simulator** `.app` bundle, confirm there is **no** `SC_Info/` and **no** `iTunesMetadata.plist`: `ls -la "$APP_BUNDLE"`, `find "$APP_BUNDLE" -name 'SC_Info' -o -name '*.sinf'` → empty. State the forensic inference: *no FairPlay payload ⇒ not a Store-provisioned install* (sideloaded/dev-signed/MDM).
3. Reason about the device case: in a full-file-system image, the bundle under `/private/var/containers/Bundle/Application/<UUID>/` would carry `SC_Info/*.sinf` and a root `iTunesMetadata.plist` whose account fields attribute the install. Note which artifact you'd cite to tie an app to an Apple Account. (See [[the-app-bundle-and-ipa-structure]].)

### Lab 4 — The device decrypt, narrated *(substrate: read-only walkthrough)*

> ⚠️ **ADVANCED — do not execute without a device you control and explicit authorization.** This is the irreducibly device-bound step; here you only *trace* it.

Walk the `frida-ios-dump` path end to end and annotate where each Concept appears:

1. **Provision a dumpable device** — jailbreak (`palera1n`, within its `checkm8`/`usbliter8` + iOS-15–18.7 envelope) **or** developer-provisioned with an injected Frida gadget. *(Concept: the device is the only place the FairPlay path runs.)*
2. **Acquire the encrypted IPA** — e.g. `ipatool download` under your Apple Account. *(Concept: still `cryptid 1`, FairPlay'd to your account/device.)*
3. **Launch + attach** — start the app, run `frida-ios-dump.py <bundle-id>` from the Mac over USB. *(Concept: dyld + `FairPlayIOKit`/`fairplayd` have already decrypted `__TEXT` into RAM; Frida reads those pages.)*
4. **Repack** — the host script overwrites `[cryptoff, cryptsize)` in a copy, sets `cryptid 0`, re-zips the IPA, **including each `PlugIns/*.appex` in its own pass**. *(Concept: capture the output, not a key.)*
5. **Verify on the Mac** (the only part you can actually do here, against the *hypothetical* output): `otool -l dumped.app/Binary | grep cryptid` → `0`; `class-dump` yields real types; every `.appex` independently reads `cryptid 0`.

Write the one-line invariant in your notes: **`cryptid 0` ⇒ analyze now; `cryptid 1` ⇒ the on-disk bytes in `[cryptoff, cryptsize)` are noise until a device dumps them.**

### Lab 5 — Triage: is this binary pristine, or repacked? *(substrate: Simulator + reasoning)*

**Fidelity caveat:** you don't have a Store binary to compare against, so you build the *signature/load-command fingerprints* on a Simulator binary and reason about how they'd differ on a tampered store app.

1. On your Simulator `.app`, run `codesign -dvvv "$APPBIN" 2>&1 | grep -E 'Authority|TeamIdentifier|flags'`. Note the authority (your dev cert or ad-hoc) and that it is **not** Apple store signing — exactly the state a re-signed dump would show.
2. Run `otool -L "$APPBIN" | grep -i -E 'frida|gadget'` (empty here). State that a **non-empty** result on a store-looking bundle is the fingerprint of a Frida-gadget re-sign dump.
3. Build the triage checklist for a full-file-system image: for each installed `MH_EXECUTE`, flag it if **(`cryptid 0` AND non-Apple/ad-hoc signature AND store-style bundle)** OR **(`SC_Info`/`iTunesMetadata.plist` missing)** OR **(an injected `FridaGadget.dylib`/extra `LC_LOAD_DYLIB`)**. Each condition is a tell that the app is not the pristine store build.
4. Tie it back: this is the *defensive* and *forensic* inverse of the decrypt step — the same `cryptid`/signature facts you used to gate analysis are what expose tampering. (See [[anti-tamper-pinning-and-detection-both-sides]].)

---

## Pitfalls & gotchas

- **Disassembling ciphertext for hours.** If `cryptid == 1` and you point a disassembler at the file, the encrypted range decodes to plausible-but-wrong instructions. It *looks* like weird real code. **Always check `cryptid` first**; the fix is decryption, not a "better" disassembler.
- **Forgetting the extensions.** You dump the main binary, `class-dump` succeeds, you declare victory — and miss that `PlugIns/Share.appex/Share` is still `cryptid 1`. Every `MH_EXECUTE` in the bundle has its own encryption command. Enumerate and verify each (`bagbak`/`frida-ios-dump` handle this; `dumpdecrypted` does not).
- **Assuming frameworks are encrypted (they're usually not).** Don't waste a device pass on `Frameworks/*.dylib`/`*.framework` — check `cryptid` first; most are `0` and are statically analyzable immediately.
- **Expecting a static key.** There is no content key in the IPA. `.supp`/`.supf` hold *wrapped* material unwrapped only inside the device's FairPlay path. "Just pull the key and decrypt offline" is impossible by design — capture the plaintext pages instead.
- **Thinking the Simulator can teach decryption.** Simulator binaries are `cryptid 0` and built for `PLATFORM_IOSSIMULATOR` on the host CPU. They teach the plaintext end-state and `arm64` *structure*, but there is **no SEP, no FairPlay, no `mremap_encrypted` path** to observe. Decryption itself is device-only.
- **Newest device + newest app = highest bar.** A14+ has **no public bootrom exploit** and there is **no public kernel jailbreak for A12+ on iOS 18/26**, so for current flagships the only route is the **developer re-sign + Frida gadget** path on a device you own — and that needs the IPA downloadable under your account. Plan acquisition accordingly.
- **`cryptid 0` ≠ "the whole binary decrypted correctly."** A botched dump can flip `cryptid` to `0` while the spliced bytes are wrong (truncated range, ASLR skew, wrong slice). Always *prove* success with a `class-dump`/disassembly that yields **coherent** types and code, not just the flag flip.
- **`otool` vs `llvm-otool`.** On a Command-Line-Tools-only Mac, `otool` may be the llvm shim or missing; `llvm-otool` is the reliable spelling. Output is equivalent for this check.
- **Lock-state still gates everything upstream.** Even with a jailbreak, a BFU device or one whose Data-Protection keys aren't available won't let the app launch into a state you can dump. You need an unlocked/AFU device with the user's keys (see [[the-jailbreak-landscape-2026]]).
- **Decrypting to answer a question that's already plaintext.** If you only need the dependency list, entitlements, declared classes, or which SDKs ship inside the app, read them off the `cryptid 1` binary directly (see the "what you can still read" table). Burning a device pass to learn something that was never encrypted is a beginner tell.
- **Wrong OS-build shared cache.** After decryption, loading a shared cache from a *different* iOS build than the app was running on yields mismatched or missing symbol resolution — branches resolve to the wrong functions. Match the cache to the device/OS build, not just "an iOS shared cache."
- **`mremap_encrypted` cputype/cpusubtype mismatch.** The `bfdecrypt`-style approach must pass the binary's exact `cputype`/`cpusubtype` (arm64 vs arm64e); a mismatch fails the decrypt or returns garbage. Read them from the Mach-O header first.

---

## Key takeaways

- **`cryptid` is the gate.** `LC_ENCRYPTION_INFO_64.cryptid == 1` ⇒ `[cryptoff, cryptoff+cryptsize)` is ciphertext, decrypted only at runtime; `== 0` ⇒ plaintext, analyze now. Check it before anything else.
- **Only `__TEXT` code is encrypted.** Header, load commands, `__DATA`, `__LINKEDIT`, symbols, entitlements, and the code-signature blob are plaintext on disk and readable on an *encrypted* binary.
- **There is no key on disk — by design.** The content key is unwrapped inside the device-bound FairPlay path (`fairplayd` + `FairPlayIOKit`, via `mremap_encrypted`, SEP-anchored). Decryption means **capturing the plaintext RAM pages**, never extracting a key.
- **The recipe is universal:** run/instrument on a device → read the decrypted range from memory → overwrite the file range → set `cryptid 0` → repack. `dumpdecrypted` (self-read), `bfdecrypt` (`mremap_encrypted`), and `frida-ios-dump`/`bagbak` (Frida) are just three ways to do the read.
- **Per-executable, including extensions.** Main binary *and* every `*.appex` carry independent encryption; frameworks/dylibs usually don't.
- **Getting a dumpable device is itself the constraint in 2026:** jailbreak (`palera1n` ≤ iOS 18.7.x on `checkm8`/`usbliter8` silicon) or developer re-sign + Frida gadget; **no public bootrom exploit for A14+**, no public kernel JB for A12+ on iOS 18/26.
- **The FairPlay payload is a forensic artifact.** `SC_Info/*.sinf` + `iTunesMetadata.plist` attribute an install to an **Apple Account and device**; their absence flags a sideloaded/dev-signed/MDM build.
- **Decrypt is step zero, not the goal** — every later RE technique (class-dump, disassembly, shared-cache xrefs, Frida) assumes a `cryptid 0` binary.

---

## Terms introduced

| Term | Definition |
|---|---|
| FairPlay (app DRM) | Apple's DRM that encrypts a Store app executable's `__TEXT` code range; decrypted only at runtime, keyed to the downloading Apple Account/device |
| `LC_ENCRYPTION_INFO_64` | Mach-O load command (`cmd 0x2C`) describing the encrypted range: `cryptoff`, `cryptsize`, `cryptid` (32-bit legacy variant `LC_ENCRYPTION_INFO` = `0x21`) |
| `cryptid` | `LC_ENCRYPTION_INFO_64` field: `0` = not encrypted (plaintext), `1` = FairPlay-encrypted (decrypt before analysis) |
| `cryptoff` / `cryptsize` | File offset (page-aligned, often `0x4000`) and length (multiple of `0x1000`) of the encrypted range |
| `fairplayd` | User-space FairPlay daemon (invoked via AMPLibraryAgent; library is CoreFP) that unwraps the content key from `SC_Info` material |
| AMPLibraryAgent / CoreFP | The agent that drives `fairplayd`, and the FairPlay client library system processes link against — the user-space half of the decryption path |
| FairPlayIOKit | Kernel driver that intercepts faults in the encrypted range and MIG-calls `fairplayd` to decrypt pages in place |
| `mremap_encrypted(2)` | BSD syscall #489 (`AUE_MPROTECT`; built only under `CONFIG_CODE_DECRYPTION`) that decrypts a mapped, FairPlay-encrypted range in place; the primitive `bfdecrypt`-style tools call directly |
| `SC_Info/` | In-bundle directory holding FairPlay licensing files (`.sinf`, `.supp`/`.supf`/`.supx`, `Manifest.plist`) |
| `.sinf` | Per-purchase FairPlay license binding the app to an Apple Account / purchase record |
| `iTunesMetadata.plist` | IPA-root plist recording app `itemId`, version external id, and the downloading Apple Account (attribution artifact) |
| `dumpdecrypted` | Classic `DYLD_INSERT_LIBRARIES` dylib that reads the app's own decrypted `__TEXT` from inside the process |
| `frida-ios-dump` / `bagbak` | Frida-driven, Mac-side decryptors that dump the plaintext range over USB and repack the IPA (incl. extensions) |
| `SG_PROTECTED_VERSION_1` | Legacy segment `flags` bit marking a protected/encrypted segment; superseded by `LC_ENCRYPTION_INFO_64` for app DRM |

---

## Further reading

- Apple — *Mach-O `<mach-o/loader.h>`* (`encryption_info_command` / `encryption_info_command_64`, the `LC_ENCRYPTION_INFO*` constants) — the authoritative struct definition.
- `man otool`, `man lipo`, `man nm`, `man codesign` — exact flag semantics on your toolchain version; `llvm-otool` on Command-Line-Tools-only Macs.
- OWASP MASTG — "iOS Tampering and Reverse Engineering" + `MASTG-TECH` decryption techniques; reference apps `iGoat-Swift` (`MASTG-APP-0028`) and the UnCrackable iOS crackmes (already-plaintext samples for Labs 2).
- qyang-nj/llios — `macho_parser` docs, including a focused `LC_ENCRYPTION_INFO` write-up and a from-scratch parser to study.
- AloneMonkey — `frida-ios-dump` and `dumpdecrypted` (the dominant modern + the classic dumpers); ChiChou — `bagbak` (extensions); JohnCoates — `flexdecrypt`/`flexdump`.
- pwn0rz/`fairplay_research` and nicolo.dev — "Analysis of Obfuscation Found in Apple FairPlay" — RE of the `fairplayd`/CoreFP internals and the SC_Info file formats.
- Meituan security team — "Research on FairPlay DRM and Obfuscation Realization" — the clearest public write-up of the `fairplayd`↔`FairPlayIOKit` MIG path and `.sinf`/`.supf` roles.
- Jonathan Levin — *MacOS and iOS Internals* (Vol. I/III) and newosxbook.com / `jtool2` — Mach-O internals and the FairPlay/`mremap_encrypted` path.
- DerekSelander/`yacd` — historical no-jailbreak FairPlay decrypt (iOS ≤ 13.4.1), a study in how that path was closed.
- Anvil Secure — "Locked Up But Not Locked Out: iOS App Pentesting Without Jailbreak" — the developer re-sign + Frida-gadget dump path in practice.
- `ipatool` (majd/ipatool) — fetch the (still-encrypted) IPA under your own Apple Account as the dump input; read `iTunesMetadata.plist` for attribution.
- bishopfox / stinger.io "Hack Notes — Decrypt iOS Executable", redfoxsec "Application Extraction and IPA Decryption Techniques" — practitioner walkthroughs of the dump-and-`cryptid 0` recipe.
- theapplewiki.com — "Dev:Crack prevention" — the historical record of FairPlay/`cryptid` and the cat-and-mouse with dumpers.

---
*Related lessons: [[mach-o-arm64-deep-dive]] | [[the-app-bundle-and-ipa-structure]] | [[static-analysis-class-dump-and-disassemblers]] | [[dynamic-analysis-with-frida]] | [[the-jailbreak-landscape-2026]] | [[owasp-mastg-and-app-security-testing]]*
