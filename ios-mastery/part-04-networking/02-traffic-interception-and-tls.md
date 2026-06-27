---
title: "Traffic interception & TLS"
part: "04 — Networking & Connectivity"
lesson: 02
est_time: "45 min read + 25 min labs"
prerequisites: [the-ios-networking-stack]
tags: [ios, networking, tls, mitmproxy, interception, ats, app-security]
last_reviewed: 2026-06-26
---

# Traffic interception & TLS

> **In one sentence:** Decrypting an iOS app's HTTPS traffic for authorized app-security testing is a *trust-store* problem, not a network problem — you become a man-in-the-middle the app willingly trusts by planting your proxy's CA root, and on iOS that requires a **two-step trust** (install the cert, then separately *enable full trust*) that has no macOS equivalent and is the single most common reason interception "silently fails."

> ⚖️ **Authorization:** Intercepting traffic is interception. Do it only against apps and accounts you own or are contractually authorized to assess (a signed engagement letter / scope document). MITM'ing third-party services you don't control can violate the Computer Fraud and Abuse Act, the Wiretap Act, the service's ToS, and the app vendor's IP. Capture only in-scope hosts, store decrypted flows as evidence under your engagement's handling rules, and tear down the trusted CA when you're done — a forgotten interception root on a device is itself a vulnerability.

## Why this matters

Almost every mobile assessment begins the same way: you point the app at a proxy and read what it actually sends. Static analysis tells you what an app *can* do; the wire tells you what it *does* — which API it calls, what tokens it leaks, whether it pins, whether it downgrades, what telemetry it ships to third parties. For a forensics professional, the same skill answers different questions: reconstructing a suspect app's server-side behavior in a controlled lab, validating that an "encrypted" messenger really is, or proving an app exfiltrates location to an ad SDK. The mechanism is identical; only the authorization changes.

The reason this deserves its own lesson — rather than "just run Burp" — is that iOS deliberately makes interception harder than macOS. Apple split CA trust into two gates specifically to defeat the social-engineered-MITM attack, and App Transport Security raises the floor so cleartext and weak TLS are off by default. Understanding *why* those gates exist is what turns "it doesn't work" into a deterministic setup.

## Concepts

### The interception model: a man-in-the-middle the app trusts

TLS interception is not breaking TLS. You never factor a key or downgrade a cipher. You terminate the client's TLS connection at your proxy, then open a second TLS connection from the proxy to the real origin — two healthy TLS sessions stitched together, with cleartext in the middle where you can read and modify it.

```
  App (URLSession)              mitmproxy / Burp / Charles            Origin server
        │                              │                                   │
        │ ── ClientHello (SNI:api.x) ─▶│                                   │
        │                              │ ── ClientHello (SNI:api.x) ──────▶│
        │                              │ ◀──── real leaf for api.x ────────│
        │ ◀─ FORGED leaf for api.x ────│  (proxy mints a leaf on the fly,  │
        │    signed by mitmproxy CA    │   signs it with its own CA root)  │
        │                              │                                   │
   validates the forged leaf      cleartext request/response          talks normal
   against its trust store        visible + editable here             TLS to origin
```

The whole trick lives in one question the client asks during the handshake: *does this leaf certificate chain up to a root I trust?* The proxy mints a leaf for `api.example.com` on demand and signs it with **its own** CA. If that CA is in the client's trust store, validation passes and the app is none the wiser. If it isn't, the handshake aborts with a certificate error — which on iOS looks like the app failing to load with no obvious cause, and in the proxy looks like a TLS handshake/`Client TLS handshake failed` error.

So the entire setup reduces to: **(1) route the app's traffic through your proxy, and (2) get the app to trust the proxy's CA.** Step 2 is where iOS diverges sharply from macOS.

### App Transport Security: the HTTPS-only floor

Before you can intercept anything, understand the baseline your traffic already obeys. **App Transport Security (ATS)** has been the default network security policy for apps linked against the iOS 9+ SDK. It is enforced by the `CFNetwork`/`Network.framework` stack for every `URLSession`/`NSURLConnection` connection (it does **not** govern raw `Network.framework` sockets, `BSD` sockets, or most third-party C TLS stacks — a gap worth remembering). When ATS is on, a connection must satisfy *all* of:

| Requirement | Default |
|---|---|
| Protocol | HTTPS only — cleartext HTTP is blocked |
| TLS version | TLS 1.2 minimum (1.3 negotiated where available) |
| Forward secrecy | Required — ECDHE key-exchange cipher suites only |
| Certificate | SHA-256+ signature; RSA ≥ 2048-bit or ECC ≥ 256-bit key |
| Certificate transparency | Not required by default (opt-in via `NSRequiresCertificateTransparency`) |

Developers carve holes in ATS through the `NSAppTransportSecurity` dictionary in the app's `Info.plist`:

| Key | Effect |
|---|---|
| `NSAllowsArbitraryLoads` | Global kill switch — disables ATS for all domains (the red flag) |
| `NSAllowsArbitraryLoadsInWebContent` | Permits cleartext/weak TLS inside `WKWebView` only |
| `NSAllowsArbitraryLoadsForMedia` | Same, for `AVFoundation` media loads |
| `NSAllowsLocalNetworking` | Permits unqualified/`.local`/IP-literal hosts |
| `NSExceptionDomains` → per-domain dict | Scope exceptions to named hosts |
| `NSExceptionAllowsInsecureHTTPLoads` | Allow plain HTTP to that domain |
| `NSExceptionMinimumTLSVersion` | Lower the floor (`TLSv1.0`/`TLSv1.1`) for that domain |
| `NSExceptionRequiresForwardSecrecy` | Set `NO` to allow non-ECDHE ciphers for that domain |
| `NSIncludesSubdomains` | Apply the exception to subdomains too |

A non-obvious gotcha codified since iOS 10: if `NSAllowsArbitraryLoads` is `YES` **and** any of the more-specific arbitrary-loads keys (`...InWebContent`, `...ForMedia`, `NSAllowsLocalNetworking`) are also present, the global flag is **ignored** for everything else — ATS is re-enabled for normal connections. App-store review also requires a justification for blanket `NSAllowsArbitraryLoads`.

A scoped exception in a real `Info.plist` looks like this — note how much it tells you before you touch the network:

```xml
<key>NSAppTransportSecurity</key>
<dict>
  <key>NSExceptionDomains</key>
  <dict>
    <key>legacy-api.example.com</key>
    <dict>
      <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>      <!-- cleartext HTTP allowed here -->
      <key>NSExceptionMinimumTLSVersion</key><string>TLSv1.0</string> <!-- downgraded floor -->
      <key>NSExceptionRequiresForwardSecrecy</key><false/>      <!-- non-ECDHE ciphers OK -->
      <key>NSIncludesSubdomains</key><true/>
    </dict>
  </dict>
</dict>
```

Read top to bottom that is three findings: a host that accepts plaintext, a host that will negotiate a decade-old TLS version, and a host that permits ciphers without forward secrecy — all reachable by an on-path attacker even *without* a trusted CA. That is the value of reading ATS statically: it surfaces network weaknesses you don't need interception to exploit.

The app-sec payoff is that the `Info.plist` *is* a static report card. Reading `NSAppTransportSecurity` out of an IPA (or a Simulator-installed bundle) tells you, before you send a single packet, whether the app permits cleartext, downgrades TLS, or disables forward secrecy on any host — this is exactly OWASP MASTG's ATS check (MASVS-NETWORK).

> 🔬 **Forensics note:** ATS posture is a durable static artifact. In a full-file-system extraction the installed app bundle lives under `/private/var/containers/Bundle/Application/<UUID>/<App>.app/Info.plist`; `NSAllowsArbitraryLoads == true` on a "secure messenger" is an immediate lead. ATS is **not** pinning — it validates the chain against the trust store but says nothing about *which* root is acceptable. That distinction is why a trusted interception CA sails straight through ATS (covered in [[03-certificate-pinning-and-bypass]]).

> ⚠️ **ATS does not stop you.** A common misconception is that ATS blocks proxying. It does not. ATS checks that the presented chain is valid and modern; a leaf minted by your *trusted* CA with a TLS-1.3 ECDHE handshake satisfies every ATS rule. ATS only bites when your proxy presents an *untrusted* chain — which is the trust-store problem, not an ATS problem.

### The iOS trust store and the two-step CA trust

This is the heart of the lesson. On **macOS**, trusting a CA is one move you already know: drop the cert into the System (or login) keychain and mark it *Always Trust* in Keychain Access, or `security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.pem`. From that instant the root is trusted for TLS server validation system-wide. One step, done.

iOS deliberately refuses to do that in one step. There are effectively **two** trust tiers:

1. **System (built-in) roots** — Apple's curated trust store, shipped read-only with the OS. These are trusted for everything automatically.
2. **User-installed roots** — any CA you add via a configuration profile (`.mobileconfig`) or a downloaded `.cer`/`.pem`. These land in a *separate* user trust store managed by **`trustd`**, and by default they are **NOT** trusted for evaluating TLS server certificates. They are installed, listed, present — and inert for HTTPS.

To activate a user-installed root for TLS server authentication you must take the second, separate step that has **no macOS analogue**:

> **Settings → General → About → Certificate Trust Settings → "Enable Full Trust for Root Certificates" → toggle ON for your CA.**

```
   TLS server cert arrives at the app
              │
   does the chain anchor in a SYSTEM (Apple) root?
              ├─ yes ─────────────────────────────────▶ TRUSTED  (normal app traffic)
              │
   does the chain anchor in a USER-INSTALLED root?
              │
              ├─ "Enable Full Trust" OFF (the default) ▶ REJECTED  ← "interception silently fails"
              │
              └─ "Enable Full Trust" ON                ▶ TRUSTED for TLS server auth
```

Apple added this gate in iOS 10.3 precisely to defeat the *social-engineered MITM*: a user tricked into tapping "Install" on a profile from a phishing page used to silently get a fully trusted root. The toggle forces a second, deliberate, deep-in-Settings action that an attacker can't trigger and that even most engineers forget. That is why your perfectly installed CA produces nothing but TLS errors until you flip it — the #1 universal interception gotcha on iOS.

> 🖥️ **macOS contrast:** On macOS the analogue is a single `security add-trusted-cert … trustRoot` (or Keychain Access → *Always Trust*) and the root is live immediately — there is no second "enable full trust" gate for user-added roots. iOS splits *install* from *trust-for-TLS* on purpose. If you carry the macOS muscle-memory (install = trusted) to iOS, your proxy will appear broken even though the cert is plainly listed under installed profiles.

> 🔬 **Forensics note:** A non-Apple root in the user trust store is a high-signal artifact. In a full-file-system acquisition, `trustd`'s user trust store is the SQLite file `TrustStore.sqlite3` (historically `/private/var/Keychains/TrustStore.sqlite3`; on recent iOS it lives under `/private/var/protected/trustd/private/` — **verify the exact path against your target OS build**). Its `tsettings` table keys each row on the `sha1` column — the SHA-1 hash of the certificate's *subject* (not the cert fingerprint) — alongside `subj` (the subject DER), `tset` (the per-cert trust-settings plist), and `data` (the full DER certificate). Cross-reference with installed configuration profiles (managed by `profiled` / the `ManagedConfiguration` framework). An interception CA — `mitmproxy`, `PortSwigger CA`, `Charles Proxy CA` — in that store on a *non-managed* device means someone set up MITM: legitimate corporate MDM, an analyst, or an attacker. The *combination* of a trusted custom root **and** the full-trust flag set is the proof the device was actually positioned to decrypt TLS, not merely had a cert dropped on it.

### The Simulator shortcut: `simctl keychain add-root-cert`

You have no physical device, so most of your work happens in the **iOS Simulator**, which changes the trust mechanics in your favor. The Simulator is a macOS process running the iOS runtime; it shares the host's network stack, so its `URLSession` traffic obeys the **Mac's system proxy settings**. And Apple gives you a one-shot command to inject a CA directly into a booted simulator's trust store, bypassing the whole profile-install dance:

```bash
xcrun simctl keychain booted add-root-cert ~/.mitmproxy/mitmproxy-ca-cert.pem
```

`booted` targets the currently running simulator (or pass an explicit device UDID). For Xcode Previews' separate device set: `xcrun simctl --set previews keychain booted add-root-cert …`. This writes the cert into the simulator device's keychain/trust store on disk (under the device's `data/Library/Keychains/` — you'll locate the exact file in Lab 4 rather than trusting a hardcoded path).

Because `add-root-cert` injects into the device's trust store directly — not through the user-profile path — it is generally trusted for TLS **without** the Certificate Trust Settings toggle. That said, some recent Simulator runtimes have reintroduced the need to flip *Settings → General → About → Certificate Trust Settings* even for `simctl`-added roots, so treat the toggle as the Simulator's stand-in for the device two-step: if flows still show handshake errors after `add-root-cert`, that's the first thing to check. (**Verify on your exact runtime** — behavior has drifted across Xcode 26.x point releases.)

> 🖥️ **macOS contrast:** `simctl keychain booted add-root-cert` is the iOS-Simulator cousin of `security add-trusted-cert` on the host — a single CLI move that makes a root trusted. It's the closest iOS gets to macOS's one-step trust, and it exists *only* for the Simulator. On a real device there is no `simctl`; you're back to the profile + full-trust two-step.

### Packaging a CA as a configuration profile (the device path)

On hardware there is no `simctl`, so the CA reaches the device as a **configuration profile** — a signed-or-unsigned XML `.mobileconfig` containing a `com.apple.security.root` (or `...pkcs1`/`...pem`) certificate payload. `mitm.it` and Burp/Charles generate this for you, but knowing the shape demystifies what "Install Profile" actually does:

```xml
<dict>
  <key>PayloadType</key>            <string>com.apple.security.root</string>
  <key>PayloadContent</key>         <data>MIID…base64-DER-of-the-CA…</data>
  <key>PayloadCertificateFileName</key><string>mitmproxy-ca-cert.cer</string>
  <key>PayloadIdentifier</key>      <string>org.mitmproxy.ca</string>
  <key>PayloadUUID</key>            <string>…</string>
</dict>
```

Installing this profile (Settings → General → VPN & Device Management) puts the root in the **user** trust store — present but inert until the full-trust toggle. An *unsigned* profile shows a red "Not Verified" warning, which is exactly the friction Apple wants on a self-signed interception root. The profile format, payload types, and signing are covered in depth in [[04-configuration-profiles-and-mobileconfig]].

> 🔬 **Forensics note:** Installed configuration profiles are themselves artifacts, recorded by `profiled` / the `ManagedConfiguration` framework (the on-device profiles store; **verify the exact path on your target build** — it has moved across iOS versions). A CA-bearing profile in that store, paired with a matching root in `TrustStore.sqlite3` and the full-trust flag set, is a three-point corroboration that the device was deliberately configured for TLS interception — distinguishable from a benign cert merely sideloaded and never trusted. If the profile is *unsigned* and *removable* and the issuer is a known proxy vendor, that points at analyst/attacker setup rather than enterprise MDM (which ships signed, often non-removable, profiles).

### Proxy plumbing: explicit proxy vs. transparent/WireGuard

There are two fundamentally different ways to get traffic into your proxy, and the choice determines what you can see:

- **Explicit HTTP(S) proxy.** The client is *told* to send everything to `127.0.0.1:8080`. You set this in the Mac's system proxy (which the Simulator inherits) or, on a device, in Wi-Fi → Configure Proxy. Works for any *proxy-aware* client — which includes `URLSession`/`CFNetwork`, i.e. the overwhelming majority of app traffic. **Limitation:** apps that open their own sockets and ignore the system proxy (some games, some VoIP/RTC stacks, anything using a bundled TLS library that doesn't read proxy settings) are invisible to an explicit proxy.

- **Transparent / WireGuard mode.** mitmproxy 9+ ships a **WireGuard** mode (`--mode wireguard`): it stands up a WireGuard VPN server, you connect the device with the standard WireGuard client and import the config mitmproxy prints, and *all* traffic is captured at the network layer — including proxy-unaware apps. This is the modern recommended way to intercept a **physical** device (no manual proxy fiddling, captures more). The CA still has to be trusted: you browse to the magic host **`mitm.it`** through the tunnel, install the profile, and flip full trust. (Note a known wrinkle: on some iOS builds the client fails to trust the mitmproxy CA in WireGuard mode *even with full trust enabled* — mitmproxy issue **#7932**, which as of 2026-06 is **still open and unresolved**, with reinstalling the profile reportedly *not* fixing it; it's unclear whether the root cause is iOS or mitmproxy. The dependable fallback is the **explicit-HTTP-proxy** path — set on the device's Wi-Fi, or layered on top of the WireGuard tunnel — instead of relying on WireGuard's transparent capture. Re-verify the issue's status before planning a device engagement around WireGuard mode.)

For Simulator work you almost always use the explicit-proxy path because the Simulator rides the host network. For device walkthroughs, WireGuard mode is the cleaner story.

> ⚠️ **ADVANCED (device walkthrough — you have no device).** On a real iPhone the full sequence is: (1) `mitmweb --mode wireguard` (or set Wi-Fi proxy to your Mac's LAN IP:8080); (2) connect WireGuard / set the proxy; (3) Safari → `http://mitm.it` → download the iOS profile; (4) **Settings → General → VPN & Device Management** → install the profile (enter passcode); (5) **Settings → General → About → Certificate Trust Settings** → enable full trust; (6) open the target app. Skipping step 5 is the silent failure. None of this is reproducible without hardware — the Labs below replicate steps 1–6's *downstream* skill (reading decrypted flows, recognizing the failure signature) entirely on the Simulator.

### The tool landscape and where each keeps its CA

The CA-trust mechanics are identical across proxies; only the UI and the CA file location differ. Knowing where each stores its root matters because that's the file you feed to `simctl add-root-cert` or convert to a `.mobileconfig`.

| Tool | CA root location | Strengths for iOS app-sec |
|---|---|---|
| **mitmproxy** (`mitmproxy`/`mitmweb`/`mitmdump`) | `~/.mitmproxy/mitmproxy-ca-cert.pem` (+ `.cer`/`.p12`) | Free, scriptable Python addons, WireGuard mode, headless capture; the lab default here |
| **Burp Suite** (Community/Pro) | Proxy → Options → *Import/export CA cert* → DER; served at `http://burpsuite` (or `http://<ip>:8080`) | Repeater/Intruder, the PortSwigger workflow most pentest reports assume |
| **Charles Proxy** | Help → SSL Proxying → *Save Charles Root Certificate*; served at `chls.pro/ssl` | Friendly GUI, good for quick triage and throttling |
| **Proxyman** | Certificate menu → *Export*; first-class "Install for iOS Simulator" automation | Best-in-class Simulator integration, per-app filtering |

All four still require the **same two-step trust on a device** and a trusted root in the **Simulator**; none of them magically bypass it.

> 🖥️ **macOS contrast:** Each of these tools also intercepts *your Mac's* own traffic the instant its CA is in the System keychain — one `Always Trust` and the whole machine is proxied. The Simulator inheriting the host proxy means a CA trusted for Mac browsing is *not* automatically in the Simulator's separate iOS trust store; the iOS runtime keeps its own trust DB, which is why `simctl add-root-cert` is a distinct step even on the same machine.

### What interception can and cannot defeat

A trusted-CA MITM beats *default* TLS validation and ATS. It does **not** beat:

- **Certificate / public-key pinning** — apps that ship the expected leaf/intermediate/SPKI hash and reject anything else, including your trusted CA. This is the next lesson, [[03-certificate-pinning-and-bypass]]; bypassing it needs runtime instrumentation (Frida/objection) or a patched binary, not just a trusted root.
- **Non-`URLSession` TLS stacks that ignore the system proxy** — capture these with WireGuard/transparent mode (still subject to pinning).
- **End-to-end-encrypted payloads inside TLS** — if the app encrypts the *body* (e.g. Signal's protocol, MLS, a custom envelope) you'll see the TLS plaintext but the application payload is still ciphertext.
- **Data-Protection-encrypted state at rest** — irrelevant to live interception, but the reason Simulator captures can't tell you anything about on-device key handling.

### Reading the decrypted flow: turning capture into findings

A decrypted flow list is raw material; the assessment is what you extract from it. Work each flow against a checklist:

- **Credentials & tokens** — `Authorization: Bearer …`, session cookies, API keys in query strings or bodies. Are they short-lived? Scoped? Sent to third-party hosts they shouldn't be?
- **PII & telemetry** — does the app ship device identifiers, location, contacts, or analytics to ad/SDK domains (often a *different* host than the app's own API)? This is the classic "secure app, leaky SDK" finding.
- **Authorization logic on the client** — replay or tamper a request (mitmproxy's intercept/edit, Burp Repeater): does the server re-check authorization, or did the client enforce it? Trusting client-supplied IDs/prices is a top finding.
- **Payload-level crypto** — if the body is itself encrypted/signed inside TLS, note the scheme; you've found defense-in-depth (or a custom rolled cipher worth scrutinizing).
- **Transport hardening** — missing HSTS, weak ciphers, cleartext fallbacks the `triage.py` addon flags automatically.

The mindset shift from forensics is that here you may *modify* and *replay*, not just observe — interception is the gateway to active testing, and every later RE technique ([[05-dynamic-analysis-with-frida]], pinning bypass) exists to keep that gateway open against hardened apps.

## Hands-on

All commands run on the **Mac** — there is no on-device shell. Install the tooling first:

```bash
brew install mitmproxy        # mitmproxy 12.2.x as of 2026-06; ships mitmproxy / mitmdump / mitmweb
# Burp Suite Community/Pro and Charles/Proxyman are GUI alternatives — same CA-trust mechanics.
```

### Generate and inspect the proxy CA

mitmproxy mints its CA on first run:

```bash
mitmdump --version        # 'Mitmproxy: 12.2.x' — also creates ~/.mitmproxy on first launch
ls -l ~/.mitmproxy
# mitmproxy-ca.pem          ← CA cert + PRIVATE KEY (guard this; it can sign for any host)
# mitmproxy-ca-cert.pem     ← CA certificate only (this is what you trust on the client)
# mitmproxy-ca-cert.cer     ← DER form for iOS/Android profile install
# mitmproxy-ca-cert.p12     ← PKCS#12 bundle
# mitmproxy-dhparam.pem

# Read what you're about to trust:
openssl x509 -in ~/.mitmproxy/mitmproxy-ca-cert.pem -noout -subject -issuer -fingerprint -sha256
# subject=CN=mitmproxy   issuer=CN=mitmproxy   (self-signed root)
# SHA256 Fingerprint=AB:CD:...   ← note this; you'll match it in the device trust store later
```

### Boot a Simulator, route it, trust the CA

```bash
# List runtimes/devices, boot one, open the Simulator UI
xcrun simctl list devices available
xcrun simctl boot "iPhone 17 Pro"        # or a UDID
open -a Simulator

# Point the Mac's system proxy at mitmproxy (the Simulator inherits it).
# Find your active service name first:
networksetup -listallnetworkservices
networksetup -setwebproxy   "Wi-Fi" 127.0.0.1 8080
networksetup -setsecurewebproxy "Wi-Fi" 127.0.0.1 8080

# Inject the CA into the booted simulator's trust store:
xcrun simctl keychain booted add-root-cert ~/.mitmproxy/mitmproxy-ca-cert.pem
```

### Capture and read a decrypted flow

```bash
mitmweb --listen-port 8080 --web-port 8081
# mitmweb opens http://127.0.0.1:8081 — the live flow list with a decrypted request/response inspector.
# (Headless alternative: `mitmdump -w capture.flows` writes a binary flow file you can replay/parse later.)
```

In the Simulator, open Safari and load `https://example.com`, or launch the app under test. Each flow appears in mitmweb fully decrypted — request line, headers, body, and the response — because the leaf mitmproxy minted for the host validated against the CA you just trusted. Click a flow to see, for an app's API call, the bearer token in the `Authorization` header, the JSON body, and the response. That readable bearer token is the entire point: it's what you'd flag as "credential observable on the wire to anyone holding a trusted root."

A scriptable peek without the GUI:

```bash
# Replay a saved capture and dump request URLs + a header of interest
mitmdump -nr capture.flows \
  -s <(printf 'def response(f):\n    print(f.request.pretty_url, f.request.headers.get("authorization",""))\n')
```

### A reusable app-sec addon

The real power of mitmproxy over a GUI proxy is the addon API — a few lines turn passive capture into an automated check. Save this as `triage.py` and load it with `mitmweb -s triage.py`:

```python
# triage.py — flag cleartext, plaintext credentials, and missing transport hardening
from mitmproxy import http

SENSITIVE = ("password", "token", "authorization", "api_key", "secret")

def request(flow: http.HTTPFlow) -> None:
    if flow.request.scheme == "http":
        print(f"[CLEARTEXT] {flow.request.pretty_url}")          # ATS hole actually exercised
    body = (flow.request.get_text() or "").lower()
    for k in SENSITIVE:
        if k in body or k in flow.request.headers.get("authorization", "").lower():
            print(f"[CREDENTIAL] {k} on {flow.request.pretty_host}")

def response(flow: http.HTTPFlow) -> None:
    h = flow.response.headers
    if flow.request.scheme == "https" and "strict-transport-security" not in h:
        print(f"[NO-HSTS] {flow.request.pretty_host}")
```

This is the seed of a repeatable methodology: the same hooks let you *rewrite* responses (test client-side trust of server data), inject headers, or fuzz parameters — all against a Simulator with no device in the loop.

When you're done, **restore the proxy** or the Mac will keep trying to reach a dead listener:

```bash
networksetup -setwebproxystate   "Wi-Fi" off
networksetup -setsecurewebproxystate "Wi-Fi" off
```

### Read an app's ATS posture statically

```bash
# From a Simulator-installed app's bundle (no device needed):
APP=~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Bundle/Application/<UUID>/Foo.app
plutil -extract NSAppTransportSecurity xml1 -o - "$APP/Info.plist" 2>/dev/null

# From an IPA: unzip and read Payload/<App>.app/Info.plist the same way.
# Look for: NSAllowsArbitraryLoads, per-domain NSExceptionAllowsInsecureHTTPLoads,
#           lowered NSExceptionMinimumTLSVersion, NSExceptionRequiresForwardSecrecy=false.
```

### Verify the trust actually took

Before blaming the app, prove the plumbing. Confirm from the Mac side that the proxy is reachable and the CA validates a forged leaf:

```bash
# 1) Is mitmproxy actually proxying? Trust its CA explicitly and fetch through it.
curl -x http://127.0.0.1:8080 --cacert ~/.mitmproxy/mitmproxy-ca-cert.pem https://example.com -sI | head -1
# HTTP/2 200   ← proxy is interposing and its CA validates the forged leaf

# 2) What leaf is the proxy actually presenting? (should be CN=example.com, issuer CN=mitmproxy)
echo | openssl s_client -connect example.com:443 -proxy 127.0.0.1:8080 2>/dev/null \
  | openssl x509 -noout -subject -issuer
```

If `curl` succeeds but the **Simulator** still fails, the gap is the iOS-side trust (re-run `add-root-cert`, or check Certificate Trust Settings), not the proxy. If `curl` itself fails, the proxy/route is wrong — fix that before touching the device side. This split-the-problem step turns "interception doesn't work" from guesswork into a two-line diagnosis.

## 🧪 Labs

> **Substrate note:** Labs 1–4 run entirely on the **iOS Simulator** and your Mac — no device, no jailbreak. Fidelity caveat: the Simulator shares the **host** network stack and has **no SEP, no Data-Protection-at-rest, and no on-device trust UI parity** — its `add-root-cert` shortcut does not exist on hardware, and the device-only pattern-of-life daemons (`knowledged`, `biomed`, `powerlogHelperd`/PowerLog, `routined`) never populate. These labs teach the *interception and trust mechanics and the failure signatures*; the device-only two-step is a read-only walkthrough (Lab 3 reproduces its failure mode on the Simulator instead).

### Lab 1 — Stand up the proxy and read a TLS flow (Simulator)

1. `brew install mitmproxy`, then `mitmdump --version` once to create `~/.mitmproxy`.
2. Boot a simulator (`xcrun simctl boot "iPhone 17 Pro"; open -a Simulator`).
3. Set the Mac proxy (`networksetup -setwebproxy`/`-setsecurewebproxy "Wi-Fi" 127.0.0.1 8080`).
4. `xcrun simctl keychain booted add-root-cert ~/.mitmproxy/mitmproxy-ca-cert.pem`.
5. `mitmweb` → in the Simulator's Safari load `https://example.com`.
6. In mitmweb, open the flow. Confirm you can read the full decrypted request/response. Identify the negotiated TLS version in the flow's connection detail. **Deliverable:** one decrypted flow with the host, method, and a response header.

### Lab 2 — The ATS report card (Simulator app bundle / sample IPA)

1. Install any app into the simulator (`xcrun simctl install booted Foo.app`) or unzip a sample IPA's `Payload/`.
2. Locate its `Info.plist` and run the `plutil -extract NSAppTransportSecurity` command from Hands-on.
3. Classify the posture: full ATS, blanket `NSAllowsArbitraryLoads`, or scoped `NSExceptionDomains`. For each exception, state the concrete risk (cleartext? downgraded TLS? PFS disabled?).
4. **Deliverable:** a one-line verdict per app in OWASP-MASTG terms ("MASVS-NETWORK: fails — cleartext permitted to api.foo.com").

### Lab 3 — Reproduce the "silent failure" signature (Simulator)

1. With the proxy running and the system proxy set, **do not** add the CA (or boot a fresh simulator that has never had it). Load an HTTPS site.
2. Watch mitmweb's event log / the flow: you'll see TLS handshake failures (`Client TLS handshake failed`, certificate-verify errors) and the Simulator app failing to load with a vague network error. **This is exactly what an analyst sees on a device when they forgot the full-trust toggle** — learn the signature.
3. Now `add-root-cert` and reload. Watch the same host go from handshake error to decrypted flow. **Deliverable:** the before/after — the handshake-error event and the subsequent successful decrypted flow — and a sentence mapping this to the device-side "Certificate Trust Settings → Enable Full Trust" step it stands in for.

### Lab 4 — Find the trust artifact on disk (Simulator filesystem)

1. Get the booted device UDID: `xcrun simctl list devices | grep Booted`.
2. Locate the trust store rather than hardcoding it:
   ```bash
   find ~/Library/Developer/CoreSimulator/Devices/<UDID>/data -iname 'TrustStore*' 2>/dev/null
   ```
3. **Copy before you query** (SQLite write-locks even on SELECT and spawns `-wal`/`-shm`): `cp <found path> /tmp/sim_truststore.db`.
4. Inspect it: `sqlite3 /tmp/sim_truststore.db '.tables'`, then read the trusted-cert table (commonly `tsettings`, whose `sha1` column is the SHA-1 of each cert's *subject* — **not** the cert fingerprint — and whose `data` column holds the DER cert). To attribute a row to your CA, pull its DER back out and recompute the fingerprint: `sqlite3 /tmp/sim_truststore.db "SELECT writefile('/tmp/row.der', data) FROM tsettings LIMIT 1;"` then `openssl x509 -inform DER -in /tmp/row.der -noout -subject -fingerprint -sha256` — confirm `subject=CN=mitmproxy` and that the SHA-256 fingerprint matches the one you noted in Hands-on.
5. **Deliverable:** the row proving the interception CA is present, plus a note on how the equivalent artifact (`TrustStore.sqlite3` + installed profiles) would appear in a *device* full-file-system extraction — the forensic tell that a device was positioned for MITM.

> 🔬 **Forensics note (Lab 4 framing):** This is the same investigative move you'd make against a real extraction: enumerate the user trust store and installed configuration profiles, hash every non-Apple root, and flag anything matching known interception CAs. The Simulator's store schema differs from a device's, but the *technique* — copy, enumerate, hash, attribute — is identical.

### Lab 5 — ATS triage across a sample corpus (public sample image / IPA set)

1. Substrate: a public iOS sample image (Josh Hickman / Digital Corpora) or a folder of sample IPAs — the device-only stores aren't needed here, only app bundles.
2. For every `<App>.app/Info.plist`, batch-extract the ATS dictionary:
   ```bash
   find . -name Info.plist -path '*.app/*' -exec sh -c \
     'echo "== $1"; plutil -extract NSAppTransportSecurity xml1 -o - "$1" 2>/dev/null' _ {} \;
   ```
3. Rank apps by posture: full ATS → scoped exceptions → blanket `NSAllowsArbitraryLoads`.
4. **Deliverable:** a short table (app, ATS verdict, riskiest exception) — the static half of a network assessment that scopes which apps even warrant live interception. **Fidelity caveat:** a Simulator/sample-image bundle's `Info.plist` is the *real* shipped plist, so this static finding is fully faithful; only the *runtime* behavior (pinning, proxy-awareness) needs the live capture from Labs 1–3.

## Pitfalls & gotchas

- **The full-trust toggle (device) / re-trust (Simulator) is the #1 silent failure.** Cert installed, listed under profiles, and *still* every HTTPS request fails: you skipped *Settings → General → About → Certificate Trust Settings*. macOS muscle-memory (install = trusted) is the trap.
- **System proxy ≠ all traffic.** An explicit proxy only catches proxy-aware (`URLSession`/`CFNetwork`) clients. Apps with their own sockets/TLS bypass it entirely — switch to WireGuard/transparent mode. Seeing *some* but not *all* of an app's traffic is usually this, not a partial-pinning situation.
- **Pinning looks like a trust failure but isn't.** If most apps decrypt fine but one fails *only after* the CA is trusted, suspect pinning, not a misconfigured proxy. Confirm in mitmproxy: a pinned client completes the handshake then drops/sends an alert, versus an untrusted-CA client that rejects the certificate. Bypass is [[03-certificate-pinning-and-bypass]].
- **The CA private key is a loaded weapon.** `~/.mitmproxy/mitmproxy-ca.pem` (and the Burp/Charles equivalents) can mint a valid leaf for *any* host any client that trusts it talks to. Don't commit it, don't share it, and revoke trust on every device when the engagement ends.
- **Forgetting to unset the proxy.** After testing, `networksetup -setwebproxystate "Wi-Fi" off` (and the secure variant). A left-on proxy pointing at a dead mitmproxy makes the Mac and Simulator look "offline."
- **Per-app re-trust on iOS 26 is not automatic across reboots/wipes.** A reset Simulator (`xcrun simctl erase`) loses the injected root; re-run `add-root-cert`.
- **HSTS and CT can complicate, not block.** Apps requiring Certificate Transparency (`NSRequiresCertificateTransparency`) may reject a proxy leaf with no SCTs — rarer than pinning but a real failure mode on hardened apps.
- **Don't read the trust-store SQLite live.** As with all forensic SQLite work, `cp` first; opening the DB in place mutates it (`-wal`/`-shm`) and contaminates evidentiary value.
- **`add-root-cert` is Simulator-only.** There is no `simctl` for hardware. Every "just run `simctl`" tutorial silently assumes the Simulator; the device path is always the profile + full-trust two-step.
- **The host keychain's trust is not the Simulator's trust.** Trusting the proxy CA in macOS Keychain Access proxies *Mac* apps but does nothing for the iOS runtime — the Simulator keeps its own trust DB. Two separate stores on one machine; trust both if you're capturing both.
- **QUIC/HTTP-3 can slip past an HTTP proxy.** Apps that negotiate HTTP/3 over QUIC (UDP) won't traverse a classic TCP HTTP proxy; you'll see them fall back to TLS-over-TCP only if the proxy refuses QUIC, or you need transparent/WireGuard mode to see them at all. Missing an app's "main" API on an explicit proxy is sometimes this, not pinning.
- **`-wal`/`-shm` contamination cuts both ways.** It applies to the proxy's own state and any forensic SQLite alike — always operate on copies, and never let a capture tool write into an evidence directory you'll later hash.

## Key takeaways

1. TLS interception is a **trust** exploit, not a crypto break: you become a MITM the client willingly trusts by planting your proxy's CA root, terminating one TLS session and opening another.
2. iOS splits CA trust into **two gates** — install the cert, then *separately* "Enable Full Trust for Root Certificates" in Settings → General → About. macOS has no second gate. Missing the toggle is the universal silent failure.
3. On the **Simulator**, `xcrun simctl keychain booted add-root-cert` collapses the two-step into one CLI move and the sim rides the **host** network/system proxy — making it your no-device interception lab.
4. **ATS** is the HTTPS-only/TLS-1.2+/forward-secrecy floor enforced for `URLSession`; its `NSAppTransportSecurity` exceptions are a static security report card you can read from the `Info.plist`. ATS is *not* pinning and does not block a trusted-CA proxy.
5. **Explicit proxy** catches proxy-aware clients; **WireGuard/transparent mode** catches everything (still subject to pinning). Choose by what the app honors.
6. A trusted-CA MITM defeats default validation and ATS but **not** certificate pinning, payload-level E2E encryption, or non-proxy-aware stacks (without transparent mode).
7. **Forensically**, a non-Apple root in `TrustStore.sqlite3` plus the full-trust flag — alongside installed configuration profiles — is durable proof a device was positioned to decrypt TLS; ATS posture in app `Info.plist`s is a parallel static artifact.
8. **Copy before query, restore the proxy, revoke the CA.** Operational hygiene is part of authorized interception.

## Terms introduced

| Term | Definition |
|---|---|
| TLS interception (MITM proxy) | Terminating a client's TLS at a proxy and re-originating a second TLS session to the server, exposing cleartext in between |
| Forged leaf certificate | A per-host server certificate the proxy mints on the fly and signs with its own CA, presented to the client during the handshake |
| Trust store (iOS) | The set of trusted roots managed by `trustd`; split into read-only system (Apple) roots and a separate user-installed store |
| `trustd` | The iOS/macOS daemon that evaluates certificate trust and owns the trust-store databases |
| Two-step CA trust | iOS's requirement to (1) install a user root then (2) *separately* enable full trust under Certificate Trust Settings before it's valid for TLS server auth |
| Certificate Trust Settings | iOS UI at Settings → General → About → "Enable Full Trust for Root Certificates"; the second trust gate, added in iOS 10.3 |
| `simctl keychain add-root-cert` | `xcrun simctl` subcommand that injects a CA directly into a booted Simulator's trust store (Simulator-only) |
| App Transport Security (ATS) | The default `URLSession`/`CFNetwork` policy: HTTPS-only, TLS 1.2+, forward secrecy, modern certs |
| `NSAppTransportSecurity` | The `Info.plist` dictionary that declares ATS exceptions (e.g. `NSAllowsArbitraryLoads`, `NSExceptionDomains`) |
| `NSAllowsArbitraryLoads` | ATS global kill switch; disables ATS for all domains (re-enabled if more-specific arbitrary-loads keys coexist) |
| `mitmproxy` / `mitmweb` / `mitmdump` | The interactive / web-UI / scriptable variants of the open-source intercepting proxy |
| WireGuard mode | mitmproxy's transparent-VPN capture mode that intercepts even proxy-unaware apps |
| `mitm.it` | mitmproxy's magic host serving the per-platform CA cert/profile to a connected client |
| `TrustStore.sqlite3` | The on-disk user trust-store database (cert subject hashes + DER blobs); a forensic MITM indicator |
| Configuration profile (`.mobileconfig`) | Signed/unsigned XML carrying payloads (e.g. a `com.apple.security.root` CA) installed via VPN & Device Management |
| Explicit proxy vs. transparent mode | Client-configured `127.0.0.1:8080` proxy (proxy-aware clients only) vs. network-layer capture (e.g. WireGuard) that catches all traffic |
| HSTS | HTTP Strict-Transport-Security response header forcing HTTPS; its absence is a transport-hardening finding |
| Certificate pinning | An app validating a specific expected cert/SPKI rather than any trusted CA; defeats a trusted-CA proxy |

## Further reading

- Apple Support, "Trust manually installed certificate profiles in iOS, iPadOS, and visionOS" (support.apple.com/en-us/102390) — the official two-step trust description.
- Apple Developer, `NSAppTransportSecurity` (developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity) — the authoritative ATS key reference.
- Apple Platform Security Guide — trust evaluation, configuration profiles, and the user vs. system trust split.
- mitmproxy docs — "Proxy Modes" (docs.mitmproxy.org/stable/concepts/modes/) and the WireGuard-mode post (mitmproxy.org/posts/wireguard-mode/); `man mitmproxy`, `man mitmdump`.
- `man simctl` / `xcrun simctl help keychain` — the Simulator trust-injection command.
- OWASP MASTG — MASVS-NETWORK tests, including the ATS check (MASTG-KNOW-0071) and pinning-bypass methodology (mas.owasp.org).
- NowSecure, "Security Analyst's Guide to NSAppTransportSecurity / ATS Exceptions" — field reference for reading ATS posture.
- PortSwigger Web Security Academy / Burp Suite docs — installing Burp's CA on iOS; same two-step trust mechanics.
- Charles Proxy & Proxyman docs — GUI alternatives with identical CA-trust requirements.
- `networksetup(8)` man page — scripting the host proxy the Simulator inherits.

---
*Related lessons: [[00-the-ios-networking-stack]] | [[03-certificate-pinning-and-bypass]] | [[05-the-sandbox-and-tcc]] | [[04-configuration-profiles-and-mobileconfig]] | [[01-simulator-internals-and-on-disk-filesystem]] | [[05-dynamic-analysis-with-frida]] | [[10-owasp-mastg-and-app-security-testing]]*
