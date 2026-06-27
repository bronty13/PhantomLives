---
title: "Configuration profiles & .mobileconfig"
part: "06 — Automation & Operations"
lesson: 04
est_time: "45 min read + 20 min labs"
prerequisites: [mdm-supervision-and-abm, code-signing-amfi-entitlements]
tags: [ios, operations, configuration-profiles, mobileconfig, payloads, forensics]
last_reviewed: 2026-06-26
---

# Configuration profiles & .mobileconfig

> **In one sentence:** A configuration profile is just a property-list of typed payload dictionaries wrapped in an optional CMS signature, but because it is the *one* sanctioned channel for changing settings on a locked-down iOS device — no `defaults write`, no `/etc`, no shell — that single XML file can silently plant a trusted root CA, route every byte through an attacker's proxy, weaken the passcode policy, or drop a phishing web clip on the Home Screen, which makes "what profiles are installed, who signed them, and exactly what did they configure?" a first-order forensic question on every iPhone you examine.

## Why this matters

On macOS you had a dozen ways to change a setting: `defaults`, plists in `~/Library/Preferences`, `/etc`, login items, a shell. iOS has essentially **one** general-purpose configuration channel exposed to the outside world, and it is the configuration profile. That concentration is the whole story. For the **builder**, profiles are how you ship a Wi-Fi config, a VPN, a developer certificate, or an enterprise root to a fleet — and the unit MDM uses for everything (the `com.apple.mdm` payload from [[mdm-supervision-and-abm]] is just one payload type among dozens). For the **attacker**, a `.mobileconfig` is a no-exploit-required compromise primitive: it needs no jailbreak, no zero-day, no code execution — only a user who taps **Install** three times. APT operators have used exactly this against journalists and activists because it is quieter than a zero-click and survives reboots. For the **examiner**, the installed-profile inventory is among the highest-signal artifacts on the device: an unexpected root-CA payload, a global HTTP proxy, or a foreign MDM enrollment is a near-binary compromise indicator, and the profile's own payloads tell you *precisely* what was changed. You cannot triage an iPhone without reading this layer.

## Concepts

### The format: a plist of typed payloads

A configuration profile is an XML property list. Strip away the marketing and it is a **two-level structure**: one top-level dictionary describing the *profile*, and a `PayloadContent` array of *payload* dictionaries, each describing one setting group.

```
┌─ Configuration Profile (.mobileconfig) — top-level dict ──────────────┐
│  PayloadType            = "Configuration"   ← always, at the top      │
│  PayloadVersion         = 1                                           │
│  PayloadIdentifier      = "com.example.corp.wifi"  (reverse-DNS)      │
│  PayloadUUID            = "E1B2…"  (random; identity of THIS profile) │
│  PayloadDisplayName     = "Corp Wi-Fi & Root"   ← shown in Settings   │
│  PayloadDescription     = "Installs corp Wi-Fi and the corp root CA"  │
│  PayloadOrganization    = "Example Corp"                              │
│  PayloadRemovalDisallowed = <false/>   ← can the user delete it?      │
│  ConsentText            = { default = "By installing…"; }  ← install   │
│  PayloadContent = (                                                   │
│   ┌─ payload dict #1 ────────────────────────────────────────────┐   │
│   │ PayloadType       = "com.apple.wifi.managed"                  │   │
│   │ PayloadUUID       = "A3C4…"   PayloadVersion = 1              │   │
│   │ PayloadIdentifier = "com.example.corp.wifi.wifi1"            │   │
│   │ SSID_STR = "CorpNet"  EncryptionType = "WPA2"  …             │   │
│   └──────────────────────────────────────────────────────────────┘   │
│   ┌─ payload dict #2 ────────────────────────────────────────────┐   │
│   │ PayloadType = "com.apple.security.root"  (a trusted root CA)  │   │
│   │ PayloadContent = <DER bytes of the CA cert, base64>           │   │
│   └──────────────────────────────────────────────────────────────┘   │
│  )                                                                    │
└──────────────────────────────────────────────────────────────────────┘
```

Every payload dict carries the same five "envelope" keys — `PayloadType`, `PayloadVersion`, `PayloadIdentifier`, `PayloadUUID`, and usually `PayloadDisplayName` — plus the type-specific keys (`SSID_STR`, `RemoteAddress`, `PayloadContent` for cert bytes, etc.). The **`PayloadType`** is the discriminator: a reverse-DNS string that names the subsystem that will consume the payload. The **`PayloadUUID`** is the stable identity of that payload; re-installing a profile with the same UUIDs updates in place rather than duplicating.

A handful of top-level keys change the profile's *lifecycle and trust*, and they matter forensically:

| Top-level key | Effect |
|---|---|
| `PayloadRemovalDisallowed` | If `true`, the user cannot delete the profile from Settings (only MDM, a wipe, or — for non-MDM — a restore removes it). |
| `PayloadScope` | `User` or `System`. iOS user-installed profiles are user-scope; MDM device profiles are system-scope. |
| `ConsentText` | Localized text shown on the install sheet — social-engineering real estate in a malicious profile. |
| `PayloadExpirationDate` / `RemovalDate` / `DurationUntilRemoval` | Auto-expiry. A profile that self-removes after N seconds leaves a *narrower* on-disk trail. |
| `HasRemovalPasscode` / `RemovalPassword` | A passcode required to remove the profile — an anti-removal trick used by both MDM and malware. |

> 🖥️ **macOS contrast:** This is the *identical* format you met on the Mac. The same `.mobileconfig`, the same `PayloadType`/`PayloadUUID` envelope, the same `PayloadContent` array, signed with the same CMS machinery, pushed by the same Jamf/Kandji/Intune. A profile authored for macOS and one for iOS differ only in *which payload types each OS honors* (macOS supports `com.apple.loginwindow`, login items, `com.apple.MCX` managed prefs that iOS ignores; iOS supports cellular/APN, single-app-mode, and the mobile restriction set macOS lacks). Apple deliberately unified the format. What changes is the **threat concentration**: on the Mac a profile is one of many config paths; on iOS it is *the* path, so the same rogue-root-CA payload is proportionally far more dangerous.

### The payload taxonomy

The catalog is large and grows every release; the official enumeration is Apple's open-source [`apple/device-management`](https://github.com/apple/device-management) YAML schemas (and the legacy *Configuration Profile Reference* PDF). The ones you will actually meet — and that carry security weight — group like this:

| `PayloadType` | What it configures | Risk note |
|---|---|---|
| `com.apple.wifi.managed` | Wi-Fi SSID/auth (incl. EAP, hidden, auto-join) | Can auto-join an attacker SSID |
| `com.apple.vpn.managed` | VPN (IKEv2, IPsec, or a per-app/3rd-party NE tunnel) | **Routes traffic** through chosen server |
| `com.apple.security.root` | A trusted **root CA** certificate (DER) | **The TLS-interception primitive** |
| `com.apple.security.pem` / `.pkcs1` | A DER/PEM certificate | Cert injection |
| `com.apple.security.pkcs12` | An identity (cert + private key, password-wrapped) | Client-auth identity |
| `com.apple.security.scep` / `…acme` | Dynamic cert enrollment (SCEP / modern ACME) | Provisions device identity for MDM |
| `com.apple.applicationaccess` | **Restrictions** (disable camera, App Store, AirDrop, screenshots, …) | Weakens posture |
| `com.apple.mobiledevice.passwordpolicy` | **Passcode policy** (length, complexity, max-failed, grace) | Can *weaken* the passcode requirement |
| `com.apple.webClip.managed` | A **Web Clip** — a Home-Screen icon pointing at a URL | Phishing launcher disguised as an app |
| `com.apple.mail.managed` / `com.apple.eas.account` | IMAP/POP mail / Exchange ActiveSync account | Mail exfil / credential capture |
| `com.apple.dnsSettings.managed` | Encrypted **DNS** (DoH/DoT) | Redirects all name resolution |
| `com.apple.proxy.http.global` | **Global HTTP proxy** (supervised) | Funnels web traffic to a proxy |
| `com.apple.webcontent-filter` | **Web content filter** (built-in or a plug-in NE filter) | Can MITM/inspect web content |
| `com.apple.app.lock` | **Single App Mode** / Autonomous SAM (supervised) | Kiosk lock-in |
| `com.apple.mdm` | **MDM enrollment** (see [[mdm-supervision-and-abm]]) | Hands a remote actor the device |
| `com.apple.notificationsettings` | Per-app notification config | Low risk, useful telemetry |

A profile may carry **any mix** of these in one `PayloadContent` array — which is exactly why a single tap can do several malicious things at once.

> ⚖️ **Authorization:** Authoring a profile that *weakens* a device you do not own — or installing one on someone else's phone — is unauthorized access. Build and test only against your own host Mac and your own Simulator. The threat payloads below are dissected so you can *recognize* them in evidence and *defend* against them, not deploy them.

### The certificate payloads in depth

Certificates deserve their own treatment because they are the highest-leverage payloads and the ones an examiner most needs to disambiguate. There are three functionally distinct kinds, and conflating them is a classic reporting error:

- **Trust anchors** (`com.apple.security.root`, and the generic `…pem`/`…pkcs1` carrying a CA cert) — install a certificate the device will *trust as an issuer*. This is the one that enables TLS interception, **but only if it is a CA and only once Full Trust applies** (see below). A leaf/server cert in a `pem` payload is *not* a trust anchor and cannot intercept anything.
- **Identities** (`com.apple.security.pkcs12`) — install a certificate **plus its private key** (PKCS#12, password-wrapped in the payload). These are *client* credentials the device presents (e.g. for EAP-TLS Wi-Fi, an IPsec VPN, or MDM mutual-TLS). Forensically, a PKCS#12 identity tells you the device was provisioned to authenticate *to* something — a strong link to the controlling organization.
- **Dynamic enrollment** (`com.apple.security.scep`, and the modern `com.apple.security.acme`) — the payload contains no cert; it contains the *parameters to go get one*. At install time the device generates a keypair and enrolls with a CA (SCEP server or ACME endpoint) named in the payload, then uses the issued identity for MDM/VPN/Wi-Fi mutual-TLS. The payload reveals the **enrollment URL** and challenge — another attributable lead.

The reason this matters: an examiner who sees "a certificate payload" and writes "TLS interception capability" without checking *which kind*, *whether it is a CA*, and *whether Full Trust is enabled* has overstated the finding. A SCEP identity for corporate Wi-Fi is mundane; a self-signed root CA with Full Trust enabled, installed by an unrecognized profile, is an incident.

> 🔬 **Forensics note:** The literal certificate bytes live *inside* the profile record (base64 DER) and, for trust anchors, *also* in `trustd`'s store — two independent copies. Extract the DER and inspect it directly: `openssl x509 -inform der -in cert.der -noout -subject -issuer -dates -fingerprint`. A CA whose subject/issuer is an organization the owner doesn't recognize, with a validity window that starts at the suspected compromise time, is about as clear a finding as iOS forensics offers.

### Signing: unsigned, signed, and the install-time trust UI

A `.mobileconfig` can be delivered **unsigned** (a plain XML plist) or **CMS-signed**. Signing wraps the plist as the signed content inside a **CMS / PKCS#7 `SignedData`** structure (DER-encoded). The signature does two things: it lets iOS show the user a trust verdict, and it tamper-seals the payloads (any edit breaks the signature).

When the user opens a profile, iOS renders an install sheet whose colored verdict label is the thing to teach:

```
┌────────────── Install Profile ──────────────┐
│  Corp Wi-Fi & Root                           │
│  Example Corp                                │
│                                              │
│  Signed   Example Corp  ✔ Verified  (green)  │  ← CMS signer chains to a
│  Description  Installs corp Wi-Fi + root CA  │     trusted root in the device store
│  Contains   Wi-Fi · Certificate              │
│  More Details ›                              │  ← lists every payload
└──────────────────────────────────────────────┘
```

The verdict resolves to one of:

- **Verified** (green) — the profile is CMS-signed and the signer's certificate **chains to a CA already trusted by the device**. This is the *only* state that means anything; it tells you *who* signed it.
- **Not Verified / not trusted** — signed, but the signer does not chain to a trusted root (self-signed, or an unknown CA). The label is *not* green.
- **Unsigned** (the warning state, no green) — no signature at all. iOS shows a red "**Unsigned**" / "The profile is not signed" warning.

The brutal usability fact — and the heart of the threat — is that **"Verified" green is not "safe," and "Unsigned" red does not stop installation.** A self-signed or unsigned malicious profile installs fine; the user just has to tap through one more red warning. Conversely a *legitimately* CMS-signed profile from a CA the device happens to trust shows green even if its payloads are hostile. The signature authenticates the *author*, not the *intent*.

Below the verdict, the sheet warns about specific high-risk payloads in plain language — these strings are durable and worth memorizing because they are what a victim *should* have read:

- Root certificate → *"Installing the certificate '…' will add it to the list of trusted certificates on your iPhone. This certificate will not be trusted for websites until you enable it in Certificate Trust Settings."*
- MDM → *"Installing this profile will allow the administrator '…' to remotely manage your iPhone."*
- Web content filter / global proxy / VPN → each names what it will route or inspect.

> 🖥️ **macOS contrast:** Same CMS signing, same green-"Verified" semantics — but the *install ergonomics* diverged. Since macOS Big Sur the `profiles install -path …` CLI no longer installs arbitrary user profiles; double-clicking a `.mobileconfig` now drops it into **System Settings → General → Device Management (Profiles)**, where the user must explicitly approve it (often with admin auth), and `sudo profiles` is reserved for MDM/DEP-bootstrapped flows. iOS keeps the in-Settings tap-through install. The trust-label model and the rogue-root-CA risk are identical on both; only the click path differs.

### The on-device install path, and the root-CA trust gate

On a real device, a `.mobileconfig` arrives by email, AirDrop, iMessage, a website download, a QR code, or a captive portal. Tapping it does **not** install it — it stages a *Downloaded Profile* that the user must then approve at:

```
Settings → General → VPN & Device Management → (Downloaded Profile)
  → Install → [passcode] → Next → Install → Install
```

(The pane was renamed across versions — "Profiles", then "Profiles & Device Management", and **"VPN & Device Management"** in current iOS/iPadOS 26.x. *Verify the exact label at author time.*) The passcode prompt and the repeated taps are the only friction.

The **certificate-trust gate** is a critical nuance that has tripped real attacks and real defenders since iOS 10.3:

- A root CA delivered by a **manually installed** profile is added to the trust store **but is *not* trusted for TLS/SSL** until the user *separately* flips it on under **Settings → General → About → Certificate Trust Settings → Enable Full Trust for Root Certificates**. So a manual rogue-CA attack needs a *second* deliberate user action — a meaningful (if thin) speed bump.
- A root CA delivered via **MDM**, **Apple Configurator**, or **as part of an MDM enrollment profile** is **automatically trusted for SSL** with no second toggle. This is why supervision (from [[mdm-supervision-and-abm]]) raises the stakes: a malicious or compromised MDM can silently make its CA fully trusted.

> 🔬 **Forensics note:** When you find a non-Apple root CA on a device, two questions decide whether it could intercept TLS: (1) was it installed by a profile, and (2) is **Full Trust** enabled for it? The first is answered by the installed-profile inventory; the second by the per-user trust store that `trustd` maintains (a `TrustStore.sqlite3` under the protected `trustd` container — *verify the exact path for your image version*; it records user/admin-added anchors independently of the profile). A CA present *and* fully trusted *and* installed by an unrecognized profile is a strong TLS-interception finding. Cross-reference [[traffic-interception-and-tls]] and [[certificate-pinning-and-bypass]].

### Where installed profiles live on disk

Two daemons own this layer. **`profiled`** (backed by the private **ManagedConfiguration.framework**) parses, validates, and *applies* a profile — handing each payload to the relevant subsystem (Wi-Fi, `trustd`, the VPN config store, the passcode policy engine) — and persists the profile's record. **`mdmd`** is the MDM client that *receives* `InstallProfile`/`RemoveProfile` commands and feeds them to `profiled` (see the command catalog in [[mdm-supervision-and-abm]]).

The persistent store lives in a **system-group container**, not a normal app sandbox:

```
/private/var/containers/Shared/SystemGroup/
   systemgroup.com.apple.configurationprofiles/
      Library/ConfigurationProfiles/
         SharedDeviceConfiguration.plist     ← Setup-Assistant skip flags, etc.
         <profile store: the installed profile records + an index>
```

The exact per-profile filenames inside `ConfigurationProfiles/` have shifted across iOS versions (older releases also used `/private/var/mobile/Library/ConfigurationProfiles/` with `.stub` files and a `PublicInfo` index). **Do not hard-code a filename — enumerate the directory on your actual image and let your parser identify the records.** The durable facts are: (a) the store is under `systemgroup.com.apple.configurationprofiles`, (b) the records are property lists containing the *full payload content* (so the on-disk record reveals exactly what each profile configured — SSIDs, server URLs, the literal CA bytes), and (c) it survives reboot and lands in backups.

> 🔬 **Forensics note:** In an iTunes/Finder backup (see [[the-itunes-finder-backup-format]]), this store is the backup **domain** `SysSharedContainerDomain-systemgroup.com.apple.configurationprofiles`, with the relative path `Library/ConfigurationProfiles/…`. So you can recover the installed-profile inventory — including a rogue CA's bytes and a foreign MDM's `ServerURL` — from a *logical backup alone*, without a full filesystem extraction. `iLEAPP` parses this into a "Profiles" / "Configuration Profiles" report; `mvt-ios` flags suspicious profiles during its triage; both are the fast path.

Two corroborating trails exist beyond the store itself, and they are where you catch a profile that was *installed and then removed*:

- **Unified logs** (`com.apple.ManagedConfiguration` / `profiled` / `mdmd` subsystems) record install, apply, and removal events with timestamps — cross-reference [[unified-logs-sysdiagnose-crash-network]]. A sysdiagnose captures a `ManagedConfiguration` / profiles snapshot too.
- The **downstream artifacts** each payload created: the Wi-Fi payload writes the SSID into the known-networks store, the cert payload writes an anchor into `trustd`'s `TrustStore.sqlite3`, the web clip writes an icon + metadata to the Home-Screen layout. These persist *independently* of the profile record, so a removed profile can still be reconstructed from the wreckage it left.

> 🖥️ **macOS contrast:** Same two-daemon shape, different names and store. macOS uses **`mdmclient`** + the **`profiles`** CLI, and persists profiles under **`/var/db/ConfigurationProfiles/`** (with managed prefs landing in `/Library/Managed Preferences/`). On macOS you can *query* the live store with `profiles list -all` / `profiles show`; on iOS there is **no on-device `profiles` command** and no shell, so you read the store from an acquired image, a backup, or via the MDM `ProfileList` command. The mental model — a daemon persists a profile record plus per-payload side effects — is the one you already have from the Mac.

### Lifecycle: install, update, expire, remove

A profile is not a one-shot event; it has a lifecycle, and each transition leaves a different trace. Understanding the lifecycle is what lets you read a *timeline* off the profile layer rather than a single snapshot.

| Transition | What happens | Forensic trace |
|---|---|---|
| **Install** | `profiled` validates the signature, applies each payload to its subsystem, writes the record to the store. | Store record (with timestamp metadata); `ManagedConfiguration` install log; the per-payload side effects appear. |
| **Update** | Re-installing a profile whose top-level `PayloadUUID` matches an existing one *replaces* it in place (same UUID = same identity). | Store record's content changes; payload UUIDs that survived vs. changed tell you what was added/removed. |
| **Expire** | If `PayloadExpirationDate`/`RemovalDate`/`DurationUntilRemoval` is set, the profile self-removes at that time. | A removal event with no corresponding user action; an expiry-driven gap is a deliberate stealth choice. |
| **Remove (user)** | User deletes it in Settings — *blocked* if `PayloadRemovalDisallowed` or gated by `RemovalPassword`. | Removal log event; store record gone; side effects mostly torn down (a removed Wi-Fi/VPN payload is unconfigured) **but** trust anchors and log history persist. |
| **Remove (MDM)** | `RemoveProfile` command, or removing the MDM profile cascades-removes everything *that MDM installed*. | `mdmd` command log; correlates to the MDM `ServerURL`. |

The investigatively important asymmetry: **the store is a snapshot of what is installed *now*, but the unified log and the downstream side effects are a *history*.** A profile that was installed for an hour during an attack window and then expired or was removed leaves nothing in the live store — but the `ManagedConfiguration` install/remove pair is still in the log, and the rogue CA it dropped may still sit in the `trustd` trust store (cert removal and profile removal are separate operations and one can outlive the other). Always reconcile the three layers.

> 🔬 **Forensics note:** Re-install-in-place via matching `PayloadUUID` is an under-appreciated stealth technique: an attacker can *update* an existing benign-looking profile to add a malicious payload without creating a visibly "new" profile entry, keeping the same display name the user once approved. Diffing the payload UUID set inside a profile record against an earlier backup of the same `PayloadIdentifier` is how you catch it.

### The malicious-profile threat class

Put the pieces together and the attack writes itself. A single `.mobileconfig`, delivered by phishing (a captive portal that says "install this to get Wi-Fi," a QR code, an email attachment, an iMessage), can carry:

1. **A rogue root CA** (`com.apple.security.root`) → with Full Trust enabled (silent if MDM-delivered, one extra tap if manual), the attacker's proxy can present certificates for *any* domain and the padlock still shows. This is the classic **TLS-interception** primitive — the same Burp/PortSwigger CA you use for [[certificate-pinning-and-bypass]], weaponized.
2. **A VPN or global HTTP proxy** (`com.apple.vpn.managed` / `com.apple.proxy.http.global`) → routes traffic through attacker infrastructure so the rogue CA actually sees the bytes.
3. **A weakened passcode/restrictions set** (`com.apple.mobiledevice.passwordpolicy`, `com.apple.applicationaccess`) → degrade the device's security posture, disable a protection, suppress a warning surface.
4. **A web clip** (`com.apple.webClip.managed`) → a Home-Screen icon that looks like a bank or webmail app but opens an attacker URL — phishing that lives *on the Home Screen*.
5. **An MDM enrollment** (`com.apple.mdm`) → the heaviest outcome: persistent remote control, covered fully in [[mdm-supervision-and-abm]].

The defining property is **no exploit**: nothing here touches a memory-safety bug, the SEP, or the boot chain. It rides entirely on user consent, which is why it is favored against high-value targets and why it survives the mitigation ladder (PAC/SPTM/MIE) entirely — those defend code execution, not social engineering. [[lockdown-mode-and-enterprise-posture]] hardens against some of this (Lockdown Mode blocks configuration-profile installation while active unless the device is already supervised), and supervised devices can restrict which profiles install, but a stock un-managed phone has only the tap-through warnings between it and a rogue CA.

**Delivery** is the other half of the technique, and the vector shapes both the social-engineering pretext and the trace you'll find:

| Vector | Pretext | Notes for the examiner |
|---|---|---|
| Email / iMessage attachment | "Install this corporate/security profile" | The message itself is corroborating evidence; the staged download may persist. |
| Website download | A page serves the `.mobileconfig` directly | Safari download history, the `WebKit`/quarantine-adjacent traces, the staging record. |
| **Captive portal** | "Install this profile to use the Wi-Fi" | The most effective pretext — users are conditioned to comply at hotspots; correlate with the joined SSID. |
| **QR code** | A printed/displayed code links to a profile URL | No on-device link text to inspect; trivially spoofed. |
| AirDrop | Hand-off in physical proximity | Leaves AirDrop/BT proximity traces; implies the actor was nearby. |

> 🔬 **Forensics note:** Because installation requires the user to navigate to **Settings → General → VPN & Device Management** and tap **Install** through warnings, a malicious profile is *consent-backed* — which cuts both ways. It means the device owner saw (and dismissed) the warnings, but it also means the act is timestamped and the pretext is usually still recoverable (the phishing email, the portal, the message thread). Pair the profile's install timestamp with the messaging/Safari artifacts from [[third-party-app-methodology]] to reconstruct *how* it got there, not just *that* it is there.

> 🔬 **Forensics note:** Treat the installed-profile inventory as a tier-one triage artifact, right next to MDM enrollment. Red flags: a root-CA payload from a non-recognized organization; a global proxy or VPN you can't attribute to an employer; an MDM `ServerURL` the owner doesn't recognize; a web clip mimicking a known brand; `PayloadRemovalDisallowed = true` or a `RemovalPassword` on a profile the user "doesn't remember installing." Each payload is self-documenting — the profile record *names* the SSID it joins, the server it tunnels to, the CA it trusts. You rarely need to guess what a malicious profile did; you just read it.

## Hands-on

> All commands run on the **Mac**. There is no on-device shell. macOS shares the `.mobileconfig` format and the CMS-signing toolchain with iOS, so authoring, signing, linting, and signature-verification are *fully faithful* on the host; only the on-device install/apply behavior needs a device or a sample image.

### Author a minimal unsigned profile

A profile is just a plist — write it by hand and lint it:

```bash
cat > /tmp/corp-wifi.mobileconfig <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>PayloadType</key>            <string>Configuration</string>
  <key>PayloadVersion</key>         <integer>1</integer>
  <key>PayloadIdentifier</key>      <string>com.example.corp.wifi</string>
  <key>PayloadUUID</key>            <string>11111111-1111-1111-1111-111111111111</string>
  <key>PayloadDisplayName</key>     <string>Corp Wi-Fi</string>
  <key>PayloadOrganization</key>    <string>Example Corp</string>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>        <string>com.apple.wifi.managed</string>
      <key>PayloadVersion</key>     <integer>1</integer>
      <key>PayloadIdentifier</key>  <string>com.example.corp.wifi.wifi1</string>
      <key>PayloadUUID</key>        <string>22222222-2222-2222-2222-222222222222</string>
      <key>PayloadDisplayName</key> <string>CorpNet</string>
      <key>SSID_STR</key>           <string>CorpNet</string>
      <key>EncryptionType</key>     <string>WPA2</string>
      <key>AutoJoin</key>           <true/>
    </dict>
  </array>
</dict></plist>
PLIST

plutil -lint /tmp/corp-wifi.mobileconfig      # -> "OK" if well-formed
plutil -p     /tmp/corp-wifi.mobileconfig      # pretty-print the parsed plist
```

`plutil` is the same plist tool you used on macOS; a `.mobileconfig` is nothing it doesn't already understand.

### Inspect any profile's payload inventory

The single most useful one-liner for triage — list every `PayloadType` in a profile:

```bash
# Works on an unsigned profile. For a signed one, decode first (next section).
plutil -extract PayloadContent xml1 -o - /tmp/corp-wifi.mobileconfig \
  | plutil -p - | grep -i PayloadType

# Or pull every PayloadType across a directory of profiles you're triaging:
for f in *.mobileconfig; do
  echo "== $f =="
  /usr/libexec/PlistBuddy -c 'Print :PayloadContent' "$f" 2>/dev/null \
    | grep -i 'PayloadType' 
done
```

A profile whose inventory includes `com.apple.security.root`, `com.apple.proxy.http.global`, or `com.apple.mdm` jumps to the top of your review pile.

### Sign a profile (CMS) and verify it

```bash
# Sign with a code-signing / Developer ID identity already in your login Keychain.
# The plist becomes the signed content of a CMS SignedData structure.
security cms -S -N "Developer ID Application: Example Corp (TEAMID1234)" \
  -i /tmp/corp-wifi.mobileconfig \
  -o /tmp/corp-wifi.signed.mobileconfig

# Decode a SIGNED profile back to its embedded plist (this is how you read one):
security cms -D -i /tmp/corp-wifi.signed.mobileconfig | plutil -p -

# OpenSSL alternative (self-signed test CA), and how to read the signer chain:
openssl smime -sign -signer signer.pem -inkey signer.key -nodetach \
  -outform der -in /tmp/corp-wifi.mobileconfig -out /tmp/corp-wifi.signed.mobileconfig
openssl pkcs7 -inform der -in /tmp/corp-wifi.signed.mobileconfig -print_certs -noout
```

`security cms -D` is your forensic decoder: hand it a `.mobileconfig` and it prints the embedded plist *and* validates the signature, telling you who signed it. (Cross-reference the CMS/code-signing machinery in [[code-signing-amfi-entitlements]] and [[the-code-signature-blob-and-entitlements-on-ios]] — a profile signature is the same CMS world as a code signature.)

### Extract and identify a certificate from a profile

When triage flags a `com.apple.security.root` (or `…pkcs12`) payload, pull the actual certificate out and read it — never report on a cert you haven't inspected:

```bash
# 1. Get the base64 DER of the cert payload's PayloadContent (decode if signed first).
/usr/libexec/PlistBuddy -c 'Print :PayloadContent:1:PayloadContent' \
  rogue.mobileconfig | base64 -d > /tmp/cert.der        # index :1 = the cert payload

# 2. Identify it. Is it a CA? Who issued it? When was it minted?
openssl x509 -inform der -in /tmp/cert.der -noout \
  -subject -issuer -dates -fingerprint -ext basicConstraints
# CA:TRUE in basicConstraints + a validity window starting at the incident time
# + an unrecognized subject = a planted interception root.
```

The `CA:TRUE` basic-constraint is the single bit that separates a trust anchor (interception-capable) from a harmless leaf certificate.

### Read the on-disk profile store from an iOS image or backup

```bash
# In a full-filesystem extraction, the store is under the system-group container:
ls -la "extraction/private/var/containers/Shared/SystemGroup/\
systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/"

# Pretty-print any record you find (they are plists carrying full payload content):
plutil -p "…/ConfigurationProfiles/SharedDeviceConfiguration.plist"

# From a logical backup, the same data is the backup domain
# SysSharedContainerDomain-systemgroup.com.apple.configurationprofiles —
# let a parser map the hashed backup filenames back to readable paths:
ileapp -t fs   -i extraction/        -o out/   # full-filesystem
ileapp -t itunes -i backup_dir/      -o out/   # logical backup
# -> open out/index.html and read the "Configuration Profiles" / "Profiles" report
```

### Find install/removal events in the unified log

```bash
# Against a sysdiagnose / .logarchive collected from the device:
log show --archive sysdiagnose_*/system_logs.logarchive \
  --predicate 'subsystem == "com.apple.ManagedConfiguration" OR process == "profiled" OR process == "mdmd"' \
  --info --style syslog | grep -iE 'install|remove|profile|trust' | head -50
```

## 🧪 Labs

> Substrate note: Labs 1–3 run entirely **Mac-side** and are *fully faithful* — the `.mobileconfig` format, the CMS signature, and the payload inventory are byte-identical to what an iPhone parses. Lab 4 uses your **host Mac** as the install substrate (the on-disk *store* concept is faithful; the **path differs** — macOS uses `/var/db/ConfigurationProfiles/`, iOS uses the `systemgroup.com.apple.configurationprofiles` container). Lab 5 uses a **public sample iOS image** for the genuine iOS store. The **iOS Simulator cannot faithfully install a profile** — it has no `profiled`/ManagedConfiguration daemon, no `mdmd`, and no `trustd` trust-store apply path, so its Settings has no working "VPN & Device Management" install flow; use it only to confirm a profile *parses*, never to study install/apply behavior.

### Lab 1 — Author and lint a multi-payload profile (Mac, fully faithful)

1. Start from the `/tmp/corp-wifi.mobileconfig` above. Add a second payload: a `com.apple.webClip.managed` web clip with `URL = https://example.com` and `Label = "Corp Portal"`. (Look up the web-clip keys in `apple/device-management`.)
2. `plutil -lint` it until it is `OK`, then `plutil -p` and confirm both payloads appear in `PayloadContent`.
3. Run the payload-inventory one-liner. Confirm it reports `com.apple.wifi.managed` and `com.apple.webClip.managed`.
4. Note: each payload needs its *own* unique `PayloadUUID`. Duplicate one deliberately and observe nothing breaks in `plutil` — UUID collisions are a *semantic* bug iOS catches at install, not a parse error. This is why on-device validation matters.

### Lab 2 — Sign, verify, and tamper-detect (Mac, fully faithful)

1. Sign your profile with a Developer ID (or a self-signed test cert via the OpenSSL path).
2. `security cms -D` the signed file and confirm it prints your embedded plist and names the signer.
3. Now **tamper**: open the signed `.mobileconfig` in a hex/text editor and flip one byte inside the embedded plist (e.g. change a character in the SSID). Re-run `security cms -D`. Observe the signature **fails to verify** — this is the tamper seal that makes "Verified" mean *this exact payload set was signed by this author*.
4. Reflect on the gap: a *self-signed* signer still produces a structurally valid signature, but on a device it would show **Not Verified** (no chain to a trusted root), not green "Verified." Signature validity ≠ trust.

### Lab 3 — Dissect a malicious-pattern profile (Mac, read-only walkthrough)

> ⚖️ **Authorization:** Build this only to *recognize* the pattern. Do not install it on any device you do not own; do not enable Full Trust for a test CA on a device you use for real traffic.

1. Author a profile that combines three payloads: a `com.apple.security.root` (paste the DER bytes of a self-signed test CA you generate with `openssl req -x509`), a `com.apple.proxy.http.global` (point `ProxyServer` at `127.0.0.1`, `ProxyServerPort` at `8080`), and a `com.apple.mobiledevice.passwordpolicy` that sets `minLength = 4` and `forcePIN = false`.
2. Run the payload-inventory one-liner. In one glance, you have the whole attack: *trust my CA, send your web traffic to my proxy, and stop requiring a strong passcode.*
3. Write down, payload by payload, exactly what this profile changes and which downstream artifact each leaves (trust-store anchor; a proxy setting; a relaxed passcode policy). This is the report you would write as an examiner — the profile is self-documenting.
4. Map the install ergonomics: unsigned → red "Unsigned" warning but still installable; the root-CA payload → the "will not be trusted for websites until you enable it in Certificate Trust Settings" warning (manual install) vs. silent full trust (MDM install). Articulate why MDM delivery is strictly more dangerous.

### Lab 4 — Install on the host Mac and trace the on-disk store (Mac substrate; iOS path differs)

> ⚠️ **ADVANCED:** This *actually installs* a profile on your Mac. Use the harmless Wi-Fi/web-clip profile from Lab 1 (no CA, no proxy, no passcode payload). Remove it at the end. Do **not** install the Lab 3 malicious-pattern profile on a Mac you care about.

1. Double-click `corp-wifi.mobileconfig`. macOS routes it to **System Settings → General → Device Management (Profiles)**. Review the same install sheet iOS would show (note the green/Unsigned verdict), then approve.
2. Query the live store the way you cannot on iOS:
   ```bash
   profiles list -all
   profiles show -all | sed -n '1,60p'
   sudo ls -la /var/db/ConfigurationProfiles/Store/
   ```
   Find your profile by its `PayloadIdentifier` and confirm the store holds the *full payload content*.
3. Remove it: System Settings → Profiles → select → **Remove**. Re-run `profiles list -all` and confirm it is gone.
4. Translate to iOS: the *concept* you just exercised (a daemon persists a profile record + per-payload side effects, queryable after the fact) is identical; on iOS the record lives in `systemgroup.com.apple.configurationprofiles` and there is no live CLI — you read it from an image/backup, as in Lab 5.

### Lab 5 — Parse iOS configuration profiles from a public sample image (sample-image substrate)

1. Obtain a public iOS reference image that includes installed profiles (Josh Hickman's iOS images on thebinaryhick.blog / Digital Corpora, or the iLEAPP test data).
2. Run `iLEAPP` against it (`ileapp -t fs -i <image> -o out/`) and open the **Configuration Profiles / Profiles** report. Identify: each profile's `PayloadDisplayName`, `PayloadIdentifier`, organization, signer, and its payload list.
3. Independently, enumerate the raw store directory under `…/systemgroup.com.apple.configurationprofiles/Library/ConfigurationProfiles/` and `plutil -p` a record. Confirm the parser's output matches the raw plist — never trust a single tool's parse on a forensic finding.
4. Cross-check the corroborating trails: grep the image's unified logs for `com.apple.ManagedConfiguration` install events, and look for the downstream artifacts (known Wi-Fi networks, `trustd` `TrustStore.sqlite3` anchors) that a profile would have created. Note any profile present in the logs/side-effects but *absent* from the live store — that is a *removed* profile, and the most interesting kind.

## Pitfalls & gotchas

- **"Verified" green ≠ trustworthy; "Unsigned" red ≠ blocked.** The signature authenticates the author, not the payloads, and an unsigned malicious profile installs after one extra warning tap. Never equate the green label with safety in a report.
- **The root-CA Full-Trust two-step.** A manually installed root CA is *not* trusted for TLS until the user toggles it in **Certificate Trust Settings** — but an MDM/Configurator-installed CA *is*, silently. When assessing TLS-interception capability you must check *both* "is the CA present?" *and* "is full trust enabled?", and *how it was installed*.
- **Don't hard-code the iOS store filenames.** The directory under `systemgroup.com.apple.configurationprofiles` and the older `/var/mobile/Library/ConfigurationProfiles/` layout have changed across releases. Enumerate the directory on *your* image; rely on the durable container name, not a remembered filename.
- **The Simulator will mislead you here.** No `profiled`, no `mdmd`, no `trustd` apply path — there is no faithful profile install in the Simulator. If a tutorial tells you to "test your MDM profile in the Simulator," it is wrong about the apply path; the Simulator validates parsing at best.
- **A removed profile is not a clean profile.** Removal deletes the store record but the per-payload side effects (a trusted CA anchor, a known Wi-Fi network, a web-clip icon, a relaxed passcode policy) and the unified-log install/remove events persist. Reconstruct from the wreckage.
- **`PayloadRemovalDisallowed` / `RemovalPassword` are dual-use.** Legitimate MDM uses them; so does malware to resist removal. On a non-supervised device, an un-removable profile the owner doesn't recognize is itself a finding.
- **Lockdown Mode changes the rules.** With [[lockdown-mode-and-enterprise-posture]] active, configuration-profile installation is blocked (unless the device is already enrolled/supervised). A target who runs Lockdown Mode is largely immune to the phishing-profile vector — relevant both to defense and to interpreting why a known-targeted device has no rogue profile.
- **Copy before you query the store.** As with every SQLite/plist artifact in this course, work on copies of the extracted store and the `trustd` trust-store DB; opening SQLite live spawns `-wal`/`-shm` sidecars. (You won't hit this on a dead image, but stay disciplined when triaging a live/mounted volume.)

## Key takeaways

- A configuration profile is a **plist of typed payload dicts** (`PayloadContent` array) under one top-level `Configuration` dict; the `PayloadType` is the discriminator and the `PayloadUUID` is the identity.
- The format, signing (CMS), and trust labels are **identical to macOS** — only the honored payload set, the install ergonomics, and the on-disk store path differ. iOS concentrates *all* outside configuration into this one channel, which is why the threat is proportionally larger.
- **Signing authenticates the author, not the intent.** Green "Verified" means "chains to a trusted CA," not "safe"; unsigned profiles install anyway. The CMS signature tamper-seals payloads — verify it with `security cms -D`.
- A single `.mobileconfig` is a **no-exploit compromise primitive**: a rogue root CA (TLS interception), a global proxy/VPN (traffic redirection), a weakened passcode policy, a phishing web clip, or a full MDM enrollment — alone or combined, defeated by nothing in the PAC/SPTM/MIE ladder because it rides on consent.
- The root-CA **Full-Trust gate** (manual install needs the Certificate Trust Settings toggle; MDM install is silent-trusted) is the hinge of the rogue-CA attack and the first thing to check forensically.
- Installed profiles persist in the **`systemgroup.com.apple.configurationprofiles`** store (backup domain `SysSharedContainerDomain-…`), recoverable from a *logical backup alone*; `profiled`/`mdmd` apply them and the **unified log** records install/removal.
- Treat the **installed-profile inventory as tier-one triage**: an unrecognized root CA, proxy, MDM `ServerURL`, or brand-mimicking web clip is a near-binary compromise indicator, and each payload is **self-documenting** — read it, don't guess.

## Terms introduced

| Term | Definition |
|---|---|
| Configuration profile (`.mobileconfig`) | A property-list of typed payload dictionaries, optionally CMS-signed, that configures an Apple device; the primary external configuration channel on iOS. |
| `PayloadContent` | The top-level array holding one dictionary per payload (setting group) in a profile. |
| `PayloadType` | Reverse-DNS string identifying the subsystem a payload configures (e.g. `com.apple.wifi.managed`, `com.apple.security.root`). |
| `PayloadUUID` | Random UUID identifying a specific payload or profile; stable across re-install for in-place update. |
| `PayloadIdentifier` | Reverse-DNS identifier of a payload/profile; together with the UUID, its addressable identity. |
| `PayloadRemovalDisallowed` | Top-level flag that, if true, prevents the user from deleting the profile. |
| CMS / PKCS#7 SignedData | The signature structure wrapping a signed `.mobileconfig`; tamper-seals payloads and identifies the signer. |
| Verified (trust label) | Green install-sheet verdict meaning the CMS signer chains to a device-trusted root; not a safety guarantee. |
| Certificate Trust Settings | iOS pane (General → About) where a *manually*-installed root CA must be enabled for full SSL trust; MDM-installed CAs skip this. |
| `com.apple.security.root` | Payload type that adds a trusted root CA — the TLS-interception primitive. |
| `com.apple.webClip.managed` | Payload type that adds a Home-Screen icon pointing at a URL; a phishing launcher when abused. |
| `profiled` | iOS daemon (ManagedConfiguration.framework) that parses, applies, and persists configuration profiles. |
| `mdmd` | iOS MDM client daemon that receives MDM `InstallProfile`/`RemoveProfile` commands and feeds them to `profiled`. |
| `systemgroup.com.apple.configurationprofiles` | The system-group container under `/var/containers/Shared/SystemGroup/` holding the installed-profile store. |
| `SysSharedContainerDomain-systemgroup.com.apple.configurationprofiles` | The iTunes/Finder backup domain exposing the profile store in a logical backup. |
| Malicious profile | A `.mobileconfig` weaponized to install a rogue CA, proxy/VPN, weak policy, web clip, or MDM enrollment without any exploit. |

## Further reading

- Apple — [`apple/device-management`](https://github.com/apple/device-management) (the authoritative, open-source payload schemas) and the legacy *Configuration Profile Reference* PDF; *Apple Platform Deployment* guide (profile distribution, certificate trust); Apple Support HT102400 (install a profile), HT102390 / HT204477 (trust manually installed certificates).
- Apple Platform Security guide — configuration enforcement, trust, and the supervised-vs-manual certificate-trust distinction.
- NetSPI — "Malicious MobileConfigs"; Security Scientist — "12 Questions and Answers About Malicious Profiles (iOS)"; Will Strafach (Sudo Security / Guardian) — research on TLS-interception via rogue CAs and profile abuse.
- Alexis Brignoni — `iLEAPP` (github.com/abrignoni/iLEAPP), the Profiles/Configuration-Profiles plugin; Amnesty Tech — `mvt` (Mobile Verification Toolkit), profile triage; Josh Hickman / Digital Corpora — public iOS reference images.
- `man security` (`cms` subcommand), `man profiles` (macOS), `man plutil`, `man PlistBuddy` — exact flag semantics for the toolchain above.
- WireGuard — `MOBILECONFIG.md` (a real-world worked `com.apple.vpn.managed` profile); Greg Neagle — `profiles` example repository (gregneagle/profiles).

---
*Related lessons: [[mdm-supervision-and-abm]] | [[declarative-device-management]] | [[code-signing-amfi-entitlements]] | [[certificate-pinning-and-bypass]] | [[traffic-interception-and-tls]] | [[lockdown-mode-and-enterprise-posture]]*
