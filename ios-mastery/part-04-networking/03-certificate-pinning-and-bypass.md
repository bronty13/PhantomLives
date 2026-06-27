---
title: "Certificate pinning & bypass"
part: "04 — Networking & Connectivity"
lesson: 03
est_time: "45 min read + 20 min labs"
prerequisites: [traffic-interception-and-tls, dynamic-analysis-with-frida]
tags: [ios, networking, certificate-pinning, ssl, bypass, app-security]
last_reviewed: 2026-06-26
---

# Certificate pinning & bypass

> **In one sentence:** Certificate pinning narrows an app's notion of "valid certificate" from *any chain the system trusts* down to *one specific key (or CA) the developer baked in* — so it sails right past the trusted-CA proxy you set up in the last lesson — and defeating it for an authorized assessment is a deterministic ladder (objection → targeted Frida → SSL-Kill-Switch → static patch) that all attacks the same handful of trust-evaluation choke points.

## Why this matters

In [[traffic-interception-and-tls]] you became a man-in-the-middle the app *willingly trusts*: plant your proxy's CA root, enable full trust, and default `URLSession` validation accepts your forged leaf because it chains to a now-trusted root. That works against the **majority** of iOS apps — most ship no pinning at all. The ones that *do* pin are exactly the ones whose traffic you most want to read: banking, healthcare, "secure" messengers, DRM-bearing media, and anything with a server-side abuse-prevention story. For those, a trusted CA is not enough — the app does a *second* check that your proxy leaf fails.

Pinning is therefore the single recurring obstacle between an assessor (or a forensics examiner reconstructing a suspect app's server behavior in a lab) and the wire. Recognizing it, locating *which* mechanism the app uses, and removing it under authorization is a standard, expected step in every mobile assessment — codified in OWASP MASVS-NETWORK. This lesson is the mechanism map: the four ways apps pin, why 2026's prevailing engineering opinion treats pinning as *operationally net-negative*, and the bypass ladder from one-liner to binary surgery.

> ⚖️ **Authorization:** Bypassing pinning is an act of defeating a security control. Do it only against apps and accounts you own or are contractually authorized to assess, under a signed engagement scope. Instrumenting a third party's app to read its traffic can violate the CFAA, the DMCA's anti-circumvention provisions, the app's ToS, and the vendor's IP. Keep the bypass scoped to in-scope hosts, log every Frida script and patched binary as an artifact of the engagement, and never leave a patched/re-signed copy of someone else's app in distribution.

## Concepts

### What pinning actually changes

Default TLS validation answers one question: *does the server's certificate chain to a root in my trust store, and is it otherwise valid (hostname, dates, key usage, revocation)?* The trust store is large (Apple's bundled roots + any CA you installed and fully trusted). Pinning adds a second, narrower question that the developer controls:

```
   Default validation                        Pinned validation (adds a gate)
   ─────────────────                         ──────────────────────────────
   ClientHello / ServerHello                 ClientHello / ServerHello
        │                                          │
   server sends leaf + chain              server sends leaf + chain
        │                                          │
   SecTrustEvaluateWithError():           SecTrustEvaluateWithError():
   chains to a trusted root?  ── no ─▶ ✗  chains to a trusted root?  ── no ─▶ ✗
        │ yes                                      │ yes
        ▼                                          ▼
      ACCEPT  ◀── your proxy CA          does the leaf's (or CA's) SPKI hash
              wins here                  equal one I hard-coded?  ── no ─▶ ✗
                                                   │ yes
                                                   ▼
                                                 ACCEPT  ◀── your proxy CA
                                                            FAILS here
```

The crucial subtlety: pinning is layered *on top of* normal validation, not instead of it. Your trusted-CA proxy still passes the first gate (`SecTrustEvaluateWithError` succeeds — the leaf chains to your now-trusted root). It fails the *second* gate because the SPKI the proxy minted is not the one the developer pinned. That is why, in mitmproxy, a pinned client **completes the TLS handshake and then drops the connection or sends a TLS alert**, whereas an untrusted-CA failure rejects the certificate *during* the handshake. Recognizing that signature is how you diagnose "this is pinning, not a proxy misconfig."

> 🖥️ **macOS contrast:** The foundation is identical to what you already know from macOS — `Security.framework`'s `SecTrust` API. `SecTrustEvaluateWithError(_:_:)` (introduced in iOS 12 / macOS 10.14, superseding the older `SecTrustEvaluate`, which Apple deprecated in iOS 13 / macOS 10.15) is the same function on both platforms, and `NSPinnedDomains` (below) works on macOS 11+ too. What iOS adds is not a different trust API — it's the *bypass ecosystem*: a mature, mobile-specific tooling stack (objection, Frida pinning scripts, SSL Kill Switch) built because mobile apps pin far more often than desktop apps, and because the runtime is locked down enough that runtime instrumentation became the standard assessment technique.

### What gets pinned: leaf, intermediate, or SPKI

Three things can be "the pin," in increasing order of robustness for the developer:

| Pinned object | What's compared | Fragility |
|---|---|---|
| **Full leaf certificate** (DER bytes) | `SecCertificateCopyData` of the server leaf vs. a bundled `.cer` | Breaks on *every* cert renewal — worst operationally |
| **Public key / SPKI** | SHA-256 of the leaf (or CA) `SubjectPublicKeyInfo`, base64 | Survives renewal *if the key is reused*; the modern default |
| **CA / intermediate** | The SPKI of an intermediate or root the developer's certs all chain through | Survives leaf rotation; widest blast radius if that CA is compromised |

Almost all modern pinning is **SPKI pinning** (`SPKI-SHA256-BASE64`), because you can rotate the leaf certificate without breaking the app *as long as you keep the same key pair* (or pre-publish a backup pin). The SPKI is the DER-encoded `SubjectPublicKeyInfo` ASN.1 structure — the public key *plus* its algorithm identifier — not the raw key bytes. This distinction bites people writing their own pin checks (see the hand-rolled trap below).

### Mechanism 1 — URLSession delegate trust evaluation (the hand-rolled standard)

The canonical native implementation overrides the authentication-challenge delegate. When `URLSession` hits a server-trust challenge, it calls:

```swift
func urlSession(_ session: URLSession,
                didReceive challenge: URLAuthenticationChallenge,
                completionHandler: @escaping (URLSession.AuthChallengeDisposition,
                                              URLCredential?) -> Void) {
    guard challenge.protectionSpace.authenticationMethod
            == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust
    else { return completionHandler(.performDefaultHandling, nil) }

    // Gate 1: normal chain validation (still passes for your trusted proxy CA)
    guard SecTrustEvaluateWithError(trust, nil) else {
        return completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // Gate 2: the pin. Extract the leaf's public key (SecKey), rebuild the
    // DER SubjectPublicKeyInfo, SHA-256 it, compare to the baked-in pin.
    guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], // iOS 15+
          let leaf  = chain.first,
          let key   = SecCertificateCopyKey(leaf),
          let spki  = spkiSHA256Base64(for: key),       // <- the app's helper
          Self.pinnedSPKIs.contains(spki)
    else {
        return completionHandler(.cancelAuthenticationChallenge, nil)   // pin failed
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
}
```

The exact method names you will hunt for at runtime:

- `URLSession:didReceiveChallenge:completionHandler:` (session-level) and `URLSession:task:didReceiveChallenge:completionHandler:` (task-level) — the delegate entry points.
- `SecTrustEvaluateWithError` — gate 1.
- `SecTrustCopyCertificateChain` (iOS 15+) / older `SecTrustGetCertificateAtIndex` / `SecTrustCopyCertificateAtIndex` — getting the leaf.
- `SecCertificateCopyKey` (iOS 12+, replaced `SecCertificateCopyPublicKey`) / `SecTrustCopyKey` — getting the public key.
- `SecKeyCopyExternalRepresentation` — the raw key bytes (note: *not* the full SPKI — see the trap).

Each of these is a hook target. The delegate method is the highest-level, app-specific one; `SecTrustEvaluateWithError` and the BoringSSL layer (below) are the lowest, framework-wide ones.

### Mechanism 2 — NSPinnedDomains (declarative, Info.plist)

Since iOS 14, Apple offers **Identity Pinning** as an extension of App Transport Security: a static `NSPinnedDomains` dictionary in the app's `Info.plist`, evaluated by the system inside `URLSession` with zero app code. Structure:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSPinnedDomains</key>
  <dict>
    <key>api.example.com</key>
    <dict>
      <key>NSIncludesSubdomains</key><true/>
      <key>NSPinnedLeafIdentities</key>            <!-- or NSPinnedCAIdentities -->
      <array>
        <dict>
          <key>SPKI-SHA256-BASE64</key>
          <string>r/mIkG3eEpVdm+u/ko/cwxzOMo1bk4TyHIlByibiA5E=</string>
        </dict>
        <dict>                                       <!-- backup pin, strongly advised -->
          <key>SPKI-SHA256-BASE64</key>
          <string>YLh1dUR9y6Kja30RrAn7JKnbQG/uEtLMkBgFF2Fuihg=</string>
        </dict>
      </array>
    </dict>
  </dict>
</dict>
```

Each domain takes a non-empty `NSPinnedCAIdentities` (CA/sub-CA pins) and/or `NSPinnedLeafIdentities` (leaf pins); each identity is `{ SPKI-SHA256-BASE64: <base64 SHA-256 of the DER SubjectPublicKeyInfo> }`. The hash format is exactly the SPKI-SHA256-BASE64 you compute with the openssl one-liner below.

> 🔬 **Forensics note:** `NSPinnedDomains` is a **durable static artifact** — it lives in the installed bundle's `Info.plist` at `/private/var/containers/Bundle/Application/<UUID>/<App>.app/Info.plist` in a full-file-system extraction (or in the unencrypted bundle on the Simulator). `plutil -p` it and you have the pinned domains *and the exact pinned hashes* without running anything — the cleanest possible "does this app pin, and to what?" answer. Guardsquare's well-known shortcoming applies: because the pins are plaintext in the plist, an attacker who can repackage the app can simply edit them; for the *examiner* that openness is a gift.

### Mechanism 3 — TrustKit

[TrustKit](https://github.com/datatheorem/TrustKit) (Data Theorem) is the de-facto third-party pinning library, predating `NSPinnedDomains` and still widely embedded. It takes a configuration dictionary (`kTSKPinnedDomains` → per-domain `kTSKPublicKeyHashes` array of base64 SPKI-SHA256 strings, `kTSKEnforcePinning`, `kTSKReportUris` for pin-failure reporting), and it **swizzles** `NSURLSession`'s delegate methods at load time so app developers get pinning without writing the challenge handler. Its validation engine is `TSKPinningValidator` (`-evaluateTrust:forHostname:`), and it computes SPKI hashes by extracting the key and **prepending fixed ASN.1 headers** per key type to reconstruct the true SubjectPublicKeyInfo before hashing.

Recognizing TrustKit statically: `strings`/`class-dump`/`nm` on the binary will show `TSKPinningValidator`, `TSKConfiguration`, `kTSKPublicKeyHashes`, and the `TrustKit` framework in the bundle's `Frameworks/`. Its presence tells you both *that* the app pins and *how* (swizzled session delegates), which steers your bypass.

### Mechanism 4 — hand-rolled SPKI / cert-byte checks

Beyond the clean delegate pattern, plenty of apps roll their own: hard-code a `Data` blob of the expected cert or SPKI, grab the server's via `SecCertificateCopyData` / `SecKeyCopyExternalRepresentation`, and `==`-compare. These are the most varied to find (the comparison can be anywhere — a networking wrapper, an Alamofire `ServerTrustEvaluating`, a C function in a cross-platform core) and the most likely to be *subtly wrong*.

> ⚠️ **The classic hand-rolled trap (worth knowing as both builder and breaker):** `SecKeyCopyExternalRepresentation` returns the *raw* key (for RSA, the PKCS#1 `RSAPublicKey`; for EC, the `04||X||Y` point) — **not** the DER `SubjectPublicKeyInfo`. A naive pin that SHA-256s that raw representation produces a hash that does **not** match the SPKI-SHA256 everyone else (openssl, NSPinnedDomains, TrustKit, hpkp tooling) computes. Apps with this bug "pin," but to a non-standard digest; you'll see the developer hard-coding a hash you can't reproduce with the standard openssl pipeline. The correct computation prepends the ASN.1 algorithm header to rebuild the SPKI before hashing — which is exactly what TrustKit does for you.

### Mechanism 5 — Alamofire (and other HTTP wrappers)

Most Swift apps don't call `URLSession` directly — they use [Alamofire](https://github.com/Alamofire/Alamofire). Alamofire owns its own `SessionDelegate` and routes every server-trust challenge through a `ServerTrustManager`, configured with per-host `ServerTrustEvaluating` objects:

| Evaluator | What it pins |
|---|---|
| `PinnedCertificatesTrustEvaluator` | Bundled DER `.cer` files (full-cert pinning); reads them from the app bundle |
| `PublicKeysTrustEvaluator` | The public keys extracted from bundled certs (SPKI-style pinning) |
| `DefaultTrustEvaluator` | Normal chain validation, no pinning |
| `RevocationTrustEvaluator` | Chain validation + OCSP/CRL revocation check |

Two consequences for you. First, **the bundled `.cer` files are themselves a forensic artifact** — `PinnedCertificatesTrustEvaluator` defaults to loading every `.cer`/`.crt`/`.der` in `Bundle.main`, so `find "$APP" -name '*.cer'` plus an `openssl x509 -in … -noout -subject` tells you exactly what the app trusts. Second, the bypass target is `ServerTrustManager.serverTrustEvaluator(forHost:)` or the evaluator's `evaluate(_:forHost:)` — but because Alamofire still terminates in the standard `URLSession`/BoringSSL stack, **objection's BoringSSL hook usually clears it without an Alamofire-specific hook at all.** Recognizing Alamofire (symbols `ServerTrustManager`, `PinnedCertificatesTrustEvaluator` in `class-dump`/`nm`, or an `Alamofire.framework` in `Frameworks/`) tells you the *config* lives in code and the *enforcement* still rides BoringSSL.

### How BoringSSL's custom-verify hook is the universal lever

Every pin that goes through the standard stack ultimately rides one BoringSSL callback. `SSL_set_custom_verify(SSL *ssl, int mode, enum ssl_verify_result_t (*cb)(SSL *ssl, uint8_t *out_alert))` installs a per-connection verification callback that runs during the handshake and returns one of:

```
ssl_verify_ok      = 0   // accept — what every bypass forces
ssl_verify_invalid = 1   // reject — what a failed pin returns
ssl_verify_retry   = 2   // async, try again later
```

`CFNetwork`/`URLSession` set this callback so that *all* of iOS's trust logic — chain validation, ATS, `NSPinnedDomains`, and the SecTrust evaluation a delegate or TrustKit performs — funnels its verdict back through it. Replace the installed callback (or replace `SSL_set_custom_verify` itself so it installs *your* always-`ssl_verify_ok` callback) and you have defeated the entire standard-stack pinning surface in one hook, regardless of which of Mechanisms 1–5 the app chose. That is exactly why both objection's disabler and SSL Kill Switch converge on this single export — it is the narrowest waist in the whole pipeline.

### Recognizing the mechanism at runtime

Mapping mechanism → where to look → what to hook is the core skill; keep this table in your head:

| Mechanism | Static tell (in the bundle) | Runtime hook target |
|---|---|---|
| `NSPinnedDomains` | `plutil -p Info.plist` shows the dict + hashes | BoringSSL `SSL_set_custom_verify` (no app symbol to hook) |
| URLSession delegate | `otool`/`class-dump` shows `…didReceiveChallenge…` + `serverTrust` | the delegate method, or `SecTrustEvaluateWithError` |
| TrustKit | `TrustKit.framework`; symbols `TSKPinningValidator`, `kTSKPublicKeyHashes` | `-[TSKPinningValidator evaluateTrust:forHostname:]` |
| Alamofire | `Alamofire.framework`; `ServerTrustManager`; bundled `.cer` files | BoringSSL hook (usually), or the evaluator's `evaluate(_:forHost:)` |
| Hand-rolled SPKI/cert | `strings` hits `SecCertificateCopyData`/`SecKeyCopyExternal`; embedded `.cer` | the compare site (find via disassembly) or BoringSSL |
| Non-`URLSession` C core | none of the above; its own TLS lib statically linked | that lib's verify callback — find it in the disassembly |

### The 2026 reality: most apps don't pin, and pinning is increasingly seen as net-negative

Two facts shape every real engagement:

1. **The majority of iOS apps ship no pinning.** A correctly installed and fully-trusted proxy CA reads them transparently — no Frida, no jailbreak. Before you reach for the bypass ladder, *confirm the app actually pins* (handshake completes then drops; only one host fails while others decrypt fine). Don't fight a pin that isn't there.

2. **Among engineers, pinning is now widely viewed as operationally net-negative**, for the same reason the web abandoned HTTP Public Key Pinning (HPKP, removed from Chrome in 2018): **pinning is a foot-gun that can brick your app for every user at once.** If a pinned key is lost, rotated without a pre-published backup pin, or the issuing CA changes, *every installed copy fails to connect* until users update — an outage you cannot hotfix server-side. The modern posture for many teams is short-lived certificates + Certificate Transparency monitoring + ATS's strong defaults, *not* pinning; and where pinning is used, the guidance is **CA/intermediate pinning with backup pins**, never bare leaf pinning. For the assessor this means: pinning, when present, is often *one* layer that may be paired with jailbreak/Frida detection, so plan for a bypass that survives anti-instrumentation (covered in [[anti-tamper-pinning-and-detection-both-sides]]).

### The bypass ladder (authorized testing)

Attack the choke points from highest-leverage/lowest-effort down. Stop at the first rung that works.

```
Rung 1  objection:  ios sslpinning disable        ← one command, hooks everything common
Rung 2  targeted Frida script                     ← when objection misses a custom check
Rung 3  SSL Kill Switch 2/3 (jailbroken device)   ← system-wide tweak, device-only
Rung 4  static binary patch + re-sign             ← most robust vs. runtime detection, most work
```

**Rung 1 — objection.** `objection` (built on Frida) ships a generic disabler:

```bash
objection -g "Target App" explore
# then, in the objection REPL:
ios sslpinning disable
```

Under the hood it hooks the common framework choke points: `NSURLSession`-based classes and their known pinning methods, the `SecTrust*` evaluation functions, and — the system-wide catch-all — the BoringSSL custom-verify callback (`SSL_set_custom_verify` / `SSL_CTX_set_custom_verify` in `/usr/lib/libboringssl.dylib`), forcing each to report success. Because BoringSSL is the bottom of iOS's `URLSession`/`CFNetwork` TLS stack, hooking it defeats *every* pinning implementation that goes through the standard stack — TrustKit, NSPinnedDomains, hand-rolled delegate, and the like. This one command clears the large majority of real apps.

**Rung 2 — targeted Frida.** When objection misses a check (a custom non-`URLSession` stack, an obfuscated comparison, a pin done in a C core, or an anti-Frida guard), write a focused script. The two durable targets:

```js
// (a) Lowest level: neuter BoringSSL's custom-verify callback (defeats the standard stack)
//     SSL_set_custom_verify(SSL*, int mode, int (*cb)(SSL*, uint8_t*)) -> void
//     Replace the callback with one that returns ssl_verify_ok (0).
const set_custom_verify = Module.findExportByName("libboringssl.dylib",
                                                  "SSL_set_custom_verify");
const set_custom_verify_orig = new NativeFunction(set_custom_verify,   // keep a callable original
                                                  "void", ["pointer","int","pointer"]);
const ssl_verify_ok = 0;
const cb = new NativeCallback((ssl, out_alert) => ssl_verify_ok, "int", ["pointer","pointer"]);
Interceptor.replace(set_custom_verify, new NativeCallback((ssl, mode, _cb) => {
  set_custom_verify_orig(ssl, mode, cb);   // install OUR always-ok callback
}, "void", ["pointer","int","pointer"]));

// (b) Higher level: force the framework trust evaluation to succeed
const eval = Module.findExportByName("Security", "SecTrustEvaluateWithError");
Interceptor.replace(eval, new NativeCallback((trust, errOut) => {
  if (!errOut.isNull()) errOut.writePointer(NULL.add(0)); // no error
  return 1;                                                // true = trusted
}, "bool", ["pointer","pointer"]));
```

For TrustKit specifically, hook `-[TSKPinningValidator evaluateTrust:forHostname:]` and return the "trusted" result enum. For an Objective-C hand-rolled delegate, hook `-URLSession:didReceiveChallenge:completionHandler:` and invoke the completion handler with `NSURLSessionAuthChallengeUseCredential` + a credential built from the (now unvalidated) trust. This is the runtime-exploration skill from [[dynamic-analysis-with-frida]] and [[objection-swizzling-and-runtime-exploration]] applied to one well-known target.

**Rung 3 — SSL Kill Switch (device, jailbroken).** [SSL Kill Switch 2](https://github.com/nabla-c0d3/ssl-kill-switch2) (nabla-c0d3) and the maintained fork **SSL Kill Switch 3** are MobileSubstrate/ElleKit tweaks that patch BoringSSL system-wide on a jailbroken device — SSL Kill Switch 2 hooks `SSL_CTX_set_custom_verify`, SSL Kill Switch 3 moved to `SSL_set_custom_verify` (iOS 13+) and adds rootless/fishhook support and `SecTrustEvaluate`-family disabling for iOS 15+. Same idea as objection's BoringSSL hook, but persistent and process-wide via the tweak loader instead of injected per-launch. **Device-only** — it needs a jailbreak, which on 2026 hardware means the BootROM-exploit ceiling (checkm8 A8–A11; usbliter8 A12–A13) plus a userland jailbreak; there is no public kernel jailbreak for A12+ on iOS 18/26 (see [[the-jailbreak-landscape-2026]]). objection/Frida against a developer-signed app is the device-free equivalent of this rung.

**Rung 4 — static binary patch.** The most robust against runtime anti-instrumentation: decrypt the app binary (FairPlay strip — see [[fairplay-encryption-and-decrypting-app-store-apps]]), locate the verification routine in the Mach-O (the delegate method, the SPKI compare, or the call into `SecTrustEvaluateWithError`), and patch the branch so it always takes the "trusted" path (e.g. `MOV W0, #1; RET`, or invert/NOP the conditional branch after the compare). Then re-sign and re-install (see [[code-signing-and-provisioning-in-depth]]). No injected agent means nothing for an anti-Frida/anti-debug guard to detect — the trade-off is per-binary reverse-engineering effort and a re-sign step.

> 🔬 **Forensics note:** Each rung leaves different artifacts and has different evidentiary weight. objection/Frida modify nothing on disk (instrumentation is in-memory) — clean for the original-evidence copy, but your *script* is the documented method. SSL Kill Switch requires a jailbroken device, which is itself a major chain-of-custody event (you have altered the device). A static patch produces a *modified, re-signed binary* — never confuse that with the original evidence; it is a derived working copy, hashed and logged separately. Whichever rung you use, the bypass is part of your method, not part of the evidence: record it in the engagement log alongside the captured flows it enabled.

> 🔬 **Forensics note:** Pinning leaves *telemetry*, and telemetry is evidence. TrustKit's `kTSKReportUris` ships a JSON pin-failure report (the offending host, the served chain, and the configured pins) to a developer endpoint on every mismatch — so an app under interception is, by design, *phoning home that it is being MITM'd*. In a controlled lab that report (visible in your own proxy as an outbound POST when the pin fails) confirms both that the app pins and where its reporting backend lives; in the field it means a sloppy bypass can tip off the app vendor's monitoring. The same goes for crash/abort-on-pin-failure designs that write a crash log under `/private/var/mobile/Library/Logs/CrashReporter/` — a pin failure can surface as a recoverable on-device artifact even when the network capture is empty.

### Computing an SPKI pin (to verify, to compare, or to build a demo)

You need this both as a builder (to author `NSPinnedDomains`/TrustKit config) and as a breaker (to confirm what a recovered hash pins to, or to reproduce a hand-rolled value). The canonical SPKI-SHA256-BASE64 pipeline:

```bash
# From a live server (grabs the leaf, extracts its SPKI, SHA-256, base64):
openssl s_client -servername api.example.com -connect api.example.com:443 </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
# -> r/mIkG3eEpVdm+u/ko/cwxzOMo1bk4TyHIlByibiA5E=

# From a saved certificate file (.pem/.cer):
openssl x509 -in leaf.pem -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | openssl enc -base64
```

The `openssl pkey -pubin -outform der` step emits the full DER `SubjectPublicKeyInfo` (key + algorithm identifier), which is precisely what NSPinnedDomains and TrustKit hash — paste that base64 straight into `SPKI-SHA256-BASE64`. To pin the CA instead of the leaf, run the same pipeline on the intermediate/root cert from the chain (`openssl s_client -showcerts` to dump the full chain).

### The MASVS-NETWORK framing

OWASP's Mobile Application Security project is the standard scaffolding for this work. In **MASVS v2.0** the relevant control is **MASVS-NETWORK-2** ("the app performs identity pinning for all remote endpoints under the developer's control") sitting under the MASVS-NETWORK category (secure data-in-transit); v2.0 dropped numeric verification levels in favor of **MAS Testing Profiles** in the MASWE weakness catalog. The concrete iOS procedure is **MASTG-TEST-0068** ("Testing Custom Certificate Stores and Certificate Pinning"), whose method is exactly the diagnostic above: attempt interception with a trusted proxy CA — if it succeeds, the app does not pin (a MASVS-NETWORK-2 gap *if* pinning is in scope for that app's threat model); if it fails *only after* the CA is trusted, the app pins and you proceed to the bypass to verify what the pinned channel actually carries. Pinning's presence is not automatically a "pass" and its absence is not automatically a "fail" — it is judged against the app's threat model, which is the whole point of the MASVS structuring it as a profile-dependent control.

> 🖥️ **macOS contrast:** On macOS you assessed network trust mostly by reading code and `SecTrust` behavior directly, often with a debugger or by reasoning about the keychain trust settings. On iOS the *same* `SecTrust` core is wrapped by a far more locked-down runtime, so the assessment workflow shifts to black-box instrumentation: you rarely have the source, the binary is FairPlay-encrypted from the Store, and the standard move is to *observe and override the trust decision at runtime* with Frida/objection rather than read it. Same trust primitives, a runtime that forces a different methodology.

## Hands-on

These run on your Mac against the Simulator or a sample bundle — there is no on-device shell.

**Compute and verify an SPKI pin:**

```bash
# A known-good public host, to anchor the pipeline:
openssl s_client -servername www.apple.com -connect www.apple.com:443 </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary | openssl enc -base64
# -> prints a base64 hash; re-run and it's stable until Apple rotates the key.
```

Described output: a stable base64 string like `8vQqGqtq...A5E=`, identical on re-run until the key rotates — your anchor that the pipeline is correct.

**Detect pinning statically in a bundle's Info.plist (no run needed):**

```bash
# Simulator-installed app, or an extracted .app bundle:
APP=~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/<UUID>/Target.app
plutil -p "$APP/Info.plist" | grep -A20 NSPinnedDomains
```

Described output, if the app uses Identity Pinning:

```
"NSPinnedDomains" => {
  "api.example.com" => {
    "NSIncludesSubdomains" => 1
    "NSPinnedLeafIdentities" => [
      0 => { "SPKI-SHA256-BASE64" => "r/mIkG3eEpVdm+u/ko/cwxzOMo1bk4TyHIlByibiA5E=" }
    ]
  }
}
```

No output means the plist mechanism isn't in use — move on to the framework/symbol checks below (the app may still pin via TrustKit, Alamofire, or hand-rolled code).

**Find TrustKit / hand-rolled pinning symbols in the binary:**

```bash
# Third-party library:
ls "$APP/Frameworks/" | grep -i trustkit
nm -gU "$APP/Frameworks/TrustKit.framework/TrustKit" 2>/dev/null | grep -i 'PinningValidator\|evaluateTrust'

# Hand-rolled native checks — grep the Mach-O for the trust APIs an app calls:
strings -a "$APP/Target" | grep -E 'SecTrustEvaluate|SecCertificateCopyData|SecKeyCopyExternal|SPKI|PublicKeyHash'
# Symbols/imports (class-dump or otool for the delegate method):
otool -ov "$APP/Target" 2>/dev/null | grep -i 'didReceiveChallenge\|serverTrust'
```

**Attach Frida to a Simulator app and disable pinning (device-free):**

```bash
# Frida can instrument Simulator processes directly (they're native Mac processes).
frida-ps | grep -i target              # find the running Simulator app
objection -g "Target" explore          # objection drives Frida under the hood
#   ios sslpinning disable             # <- in the objection REPL
# Or a raw script:
frida -n Target -l disable_pinning.js
```

Described objection output on success: `(agent) Custom TLS validator not found`/`Found NSURLSession … hooking` lines, then `(agent) Job: <uuid> - Started` — after which the previously-dead host begins decrypting in mitmproxy.

**Confirm the effect on the wire:** with mitmproxy running and the Simulator trusting your CA (from [[traffic-interception-and-tls]]), a pinned demo app shows *handshake-complete-then-drop* before the bypass, and *full decrypted flows* after `ios sslpinning disable` — that before/after is the deliverable.

**Locate the patch site for Rung 4 (disassembly, on a decrypted binary):** the verification routine ends in a boolean returned in `w0`. In a disassembler you're looking for a call to `SecTrustEvaluateWithError` (or the SPKI `memcmp`/`==`) followed by a conditional branch on the result; the patch is to force the trusted path — e.g. overwrite the comparison-and-branch so the function returns `1`:

```
; before (simplified arm64)
  bl   _SecTrustEvaluateWithError
  cbz  w0, fail            ; if false -> reject
  ...
; after (always-trusted)
  mov  w0, #1
  ret                      ; or NOP the cbz so the reject path is never taken
```

Then re-sign (`codesign -f -s -`) and reinstall. Nothing is injected at runtime, so an in-memory anti-Frida/anti-debug guard sees a clean process — the trade-off is the per-binary RE effort, covered in [[static-analysis-class-dump-and-disassemblers]] and [[mach-o-arm64-deep-dive]].

## 🧪 Labs

> **Substrate note:** every lab is device-free. Labs 1–4 use your Mac + the Xcode **Simulator** or a public **sample bundle**; Lab 5 is a **read-only walkthrough** of the device-only rung. **Fidelity caveat:** the Simulator runs the macOS Security/Network frameworks, so `SecTrust*` and `libboringssl.dylib` exist and the *trust-evaluation logic* is a faithful analogue — but there is **no SEP, no Data Protection, no AMFI/sandbox enforcement, and no jailbreak/SSL-Kill-Switch path**, and an App-Store FairPlay-encrypted binary won't run there. The Simulator teaches the *trust-decision mechanism and the runtime-override skill*; the device-only rungs (SSL Kill Switch, patching a decrypted Store binary) are narrated.

### Lab 1 — Compute SPKI pins and author an NSPinnedDomains block (Mac CLI)

1. Run the live-server SPKI pipeline against two hosts you control or any public HTTPS host. Record the base64 hash for each.
2. Pull the **full chain** with `openssl s_client -showcerts -connect host:443 </dev/null`, save the leaf and the intermediate to separate `.pem` files, and compute the SPKI hash of *each*.
3. Hand-write an `NSPinnedDomains` dict pinning the **intermediate** (`NSPinnedCAIdentities`) plus a backup pin. **Deliverable:** the plist block, and one sentence on why CA-pinning + backup pin is the operationally safe choice over bare-leaf pinning.

### Lab 2 — Build a pinning demo app and watch it block your proxy (Simulator)

1. In Xcode, build a trivial app that does one `URLSession` GET to a host you control, with a delegate that implements `urlSession(_:didReceive:completionHandler:)` and rejects unless the leaf's SPKI matches a hard-coded pin (use the value from Lab 1). Run it in the Simulator.
2. Start mitmproxy and make the Simulator trust your CA (the Lab from [[traffic-interception-and-tls]]).
3. Observe the failure signature in mitmproxy: **handshake completes, then the client drops** — contrast that with what an *un-pinned* build does (clean decrypted flow). **Deliverable:** the two mitmproxy event traces side by side, annotated with where gate 1 vs. gate 2 fired.

### Lab 3 — Static pinning triage of a sample bundle (read-only)

1. Take a Simulator-installed app (or a public sample IPA's extracted `.app`) and run the static-detection commands from Hands-on: `plutil -p Info.plist | grep NSPinnedDomains`, `ls Frameworks/ | grep -i trustkit`, and `strings`/`otool` for `SecTrustEvaluate`, `didReceiveChallenge`, `TSKPinningValidator`.
2. Classify the app: no pinning / NSPinnedDomains / TrustKit / hand-rolled — and note *which bypass rung* that classification points you to. **Deliverable:** a one-row triage verdict (app, mechanism, evidence string, recommended bypass). **Fidelity caveat:** the bundle's `Info.plist` and embedded frameworks are the *real shipped artifacts*, so this static finding is fully faithful even on the Simulator.

### Lab 4 — Bypass your own pin with objection/Frida (Simulator)

1. Against the Lab 2 pinning app, attach objection: `objection -g "<DemoApp>" explore`, then `ios sslpinning disable`.
2. Re-issue the request and confirm the flow now decrypts in mitmproxy. Then *without* objection, write a 10-line Frida script that hooks **only** `SecTrustEvaluateWithError` to return `true`, and confirm it alone is sufficient for this app.
3. **Deliverable:** the working Frida snippet + the before/after mitmproxy capture, and a sentence on why hooking the *framework* function worked here but might fail an app that pins in a non-`URLSession` C core.

### Lab 5 — SSL Kill Switch & static-patch rungs (read-only walkthrough)

> ⚠️ **ADVANCED (device-only — you have no device).** Narrate, don't execute: on a jailbroken phone you'd install **SSL Kill Switch 3** via the package manager, which loads as an ElleKit tweak hooking `SSL_set_custom_verify` in `libboringssl.dylib` process-wide, then launch the target and capture with a trusted proxy CA — no per-launch injection. For the **static-patch** rung: FairPlay-decrypt the Store binary ([[fairplay-encryption-and-decrypting-app-store-apps]]), open it in a disassembler, find the call to `SecTrustEvaluateWithError` (or the SPKI compare), patch the result to always-trusted (`MOV W0, #1; RET` or NOP the failing branch), re-sign ([[code-signing-and-provisioning-in-depth]]), reinstall.

1. Map each step to its device-free analogue from Labs 1–4 (objection's BoringSSL hook ≈ SSL Kill Switch's `SSL_set_custom_verify` hook; the Frida `SecTrustEvaluateWithError` hook ≈ the static patch of the same call). **Deliverable:** a short table aligning each device-only step to the Simulator/Frida skill that stands in for it, plus the distinct chain-of-custody note for each rung.

## Pitfalls & gotchas

- **Don't fight a pin that isn't there.** Most apps don't pin. If interception fails, first re-confirm CA trust and proxy-awareness (an explicit proxy misses non-`URLSession` sockets and QUIC/HTTP-3 — see [[traffic-interception-and-tls]]) *before* assuming pinning. The pinning signature is specific: handshake completes, then the client drops or sends an alert, and **only the pinned host fails while others decrypt fine**.

- **`SecKeyCopyExternalRepresentation` ≠ SPKI.** Both as builder and breaker: the raw key bytes are not the DER `SubjectPublicKeyInfo`. A pin computed over the raw representation won't match the standard SPKI-SHA256-BASE64 from openssl/NSPinnedDomains/TrustKit. If a recovered hand-rolled hash refuses to reproduce with the openssl pipeline, suspect this — the app pins to a non-standard digest.

- **NSPinnedDomains only covers ATS-routed `URLSession`/`CFNetwork` traffic.** It does nothing for an app's own `BoringSSL`/`Network.framework` sockets or a bundled cross-platform networking core. Seeing some hosts pinned-via-plist and others not is normal; the plist is not the whole story.

- **`SecTrustEvaluate` vs. `SecTrustEvaluateWithError`.** The old boolean `SecTrustEvaluate(_:_:)` was deprecated in iOS 13; modern apps use `SecTrustEvaluateWithError`. Hooking only the deprecated symbol on a current app does nothing — hook the one the binary actually imports (check with `otool -L`/`nm`).

- **A BoringSSL hook defeats the standard stack but not custom TLS.** Apps that bundle their own TLS (a statically-linked OpenSSL/BoringSSL/mbedTLS in a C core, or do raw socket TLS) won't route through `/usr/lib/libboringssl.dylib`; you must find and hook *their* verify path. This is why objection sometimes "doesn't work" on otherwise-standard-looking apps.

- **Anti-instrumentation pairs with pinning on hardened apps.** A jailbreak/Frida/debugger detector can crash or fake-succeed your bypass, making it look like the pin held. If objection disconnects or the app dies on attach, you're fighting anti-tamper, not pinning — see [[anti-tamper-pinning-and-detection-both-sides]]. A static patch (Rung 4) sidesteps in-memory detectors entirely.

- **Certificate Transparency (`NSRequiresCertificateTransparency`) is not pinning** but produces a similar late failure: a proxy leaf with no SCTs is rejected. Rarer, but don't misdiagnose it as a pin you can't find.

- **A forgotten patched/re-signed binary or a lingering trusted CA is itself a finding against you.** Tear down trust roots and destroy derived patched binaries at engagement close; log them as artifacts, don't leave them deployed.

## Key takeaways

1. **Pinning adds a second gate** (does the SPKI/cert match a baked-in value?) *after* normal chain validation — which is exactly why your trusted-CA proxy passes validation but the pinned app still drops the connection. The signature is *handshake-complete-then-drop*, only on the pinned host.
2. **Four mechanisms, one foundation:** URLSession delegate trust evaluation, declarative `NSPinnedDomains` (Info.plist), TrustKit (swizzled session delegates), and hand-rolled SPKI/cert checks — all ultimately ride `SecTrust`/BoringSSL, the same trust core you know from macOS.
3. **SPKI pinning is the modern default**, computed as base64(SHA-256(DER `SubjectPublicKeyInfo`)). The trap: `SecKeyCopyExternalRepresentation` is the raw key, not the SPKI — rebuild the DER (prepend the ASN.1 header) or use openssl's `pkey -pubin -outform der`.
4. **Most apps don't pin, and pinning is increasingly viewed as net-negative** (the HPKP foot-gun: a lost/rotated pin bricks every install). Confirm pinning is actually present before deploying the bypass ladder.
5. **The bypass ladder is deterministic:** objection `ios sslpinning disable` → targeted Frida (hook `SSL_set_custom_verify` / `SecTrustEvaluateWithError` / `TSKPinningValidator` / the delegate) → SSL Kill Switch on a jailbroken device → static binary patch + re-sign. Stop at the first rung that works.
6. **Each rung has a different forensic footprint:** Frida/objection touch nothing on disk, SSL Kill Switch requires (and documents) a jailbroken device, and a static patch yields a *derived, re-signed* binary that is never the original evidence. The bypass is your method, not the evidence.
7. **MASVS-NETWORK-2 / MASTG-TEST-0068** is the framing: attempt trusted-CA interception, and judge presence/absence of pinning against the app's threat model — neither outcome is automatically pass or fail.

## Terms introduced

| Term | Definition |
|---|---|
| Certificate pinning | Restricting accepted certificates to a specific developer-chosen leaf, public key (SPKI), or CA, beyond normal chain validation |
| SPKI | `SubjectPublicKeyInfo` — the DER ASN.1 structure of a public key + its algorithm identifier; the thing modern pins hash |
| SPKI-SHA256-BASE64 | The standard pin format: base64-encoded SHA-256 of the DER `SubjectPublicKeyInfo`; used by NSPinnedDomains and TrustKit |
| `SecTrustEvaluateWithError` | `Security.framework` function that validates a `SecTrust` chain (iOS 12+; the older boolean `SecTrustEvaluate` was deprecated in iOS 13); the primary framework-level bypass hook |
| `NSPinnedDomains` | iOS 14+ declarative Identity Pinning: an ATS `Info.plist` dict mapping domains to pinned `SPKI-SHA256-BASE64` identities |
| `NSPinnedCAIdentities` / `NSPinnedLeafIdentities` | The two `NSPinnedDomains` arrays — pin a CA/intermediate vs. pin the leaf |
| TrustKit | Data Theorem's pinning library; swizzles `NSURLSession` delegates, validates via `TSKPinningValidator`, supports pin-failure reporting |
| `SSL_set_custom_verify` | BoringSSL (`libboringssl.dylib`) callback installer for custom TLS verification; the system-wide bypass choke point (iOS 13+) |
| `SecCertificateCopyKey` | iOS 12+ API returning a certificate's public key as `SecKey` (replaced the deprecated `SecCertificateCopyPublicKey`) |
| SSL Kill Switch (2/3) | Jailbreak tweak that patches BoringSSL system-wide to disable all standard-stack pinning |
| `objection ios sslpinning disable` | objection/Frida one-command disabler hooking the common framework + BoringSSL pinning choke points |
| MASVS-NETWORK-2 | OWASP MASVS v2 control requiring identity pinning for developer-controlled endpoints |
| MASTG-TEST-0068 | OWASP MASTG iOS procedure for testing custom certificate stores and certificate pinning |

## Further reading

- Apple — "Identity Pinning: How to configure server certificates for your app" (developer.apple.com/news/?id=g9ejcf8y) and the `NSPinnedDomains` Information Property List reference.
- Apple — `SecTrustEvaluateWithError`, `SecCertificateCopyKey`, `SecTrustCopyCertificateChain` in the `Security.framework` documentation; the TN-series notes on App Transport Security.
- OWASP MAS — MASTG-TEST-0068 (iOS certificate pinning), MASTG-KNOW-0015 (pinning knowledge), MASVS-NETWORK category, and the MASWE testing profiles (mas.owasp.org).
- Guardsquare — "Leveraging Info.plist Based Certificate Pinning on iOS (and Making Its Shortcomings)" and "How to Prevent SSL Pinning Bypass in iOS Applications" (guardsquare.com/blog).
- Data Theorem — TrustKit (github.com/datatheorem/TrustKit), README + `TSKPinningValidator` API.
- Alban Diquet (nabla-c0d3) — SSL Kill Switch 2 (github.com/nabla-c0d3/ssl-kill-switch2); NyaMisty — SSL Kill Switch 3 fork.
- NetSPI — "Four Ways to Bypass iOS SSL Verification and Certificate Pinning"; Redfox/Appknox iOS pinning-bypass walkthroughs.
- Frida & objection docs (frida.re, github.com/sensepost/objection) — the `ios sslpinning disable` implementation and BoringSSL hooking patterns.
- `man openssl-x509`, `man openssl-pkey`, `man openssl-dgst` — the exact flags for the SPKI pipeline on your OS version.

---
*Related lessons: [[traffic-interception-and-tls]] | [[dynamic-analysis-with-frida]] | [[objection-swizzling-and-runtime-exploration]] | [[anti-tamper-pinning-and-detection-both-sides]] | [[owasp-mastg-and-app-security-testing]] | [[static-analysis-class-dump-and-disassemblers]]*
