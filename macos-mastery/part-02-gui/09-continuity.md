---
title: "Continuity: Handoff, AirDrop, Universal Clipboard, Sidecar, and the Full Feature Family"
part: P02 GUI
est_time: 50 min read + 40 min labs
prerequisites: [part-01-architecture/08-security-architecture, part-02-gui/00-finder-mastery]
tags: [macos, continuity, airdrop, handoff, sidecar, universal-control, iphone-mirroring, networking, bluetooth, forensics]
---

# Continuity: Handoff, AirDrop, Universal Clipboard, Sidecar, and the Full Feature Family

> **In one sentence:** Apple's Continuity stack is a tight coupling of Bluetooth Low Energy discovery, Wi-Fi Direct peer sessions, iCloud relay, and local XPC bridging that lets your Mac treat nearby Apple devices as shared peripherals — and every link in that chain leaves investigable artifacts.

---

## Why this matters

Continuity is not a single feature — it is a family of seventeen-plus discrete capabilities, each with its own transport, daemon, entitlement requirements, and failure modes. Windows users arriving on macOS expect USB cables or a network share to move files. The paradigm shift is radical: your iPhone's keyboard literally becomes part of your Mac's input surface; your iPad becomes a second monitor with zero driver installation; files cross the air-gap in seconds without any authentication ceremony if the security setting is wrong.

For a forensics professional, every one of these features is both a capability and an attack surface. AirDrop files bypass network monitoring. iPhone Mirroring metadata leaks app lists to corporate MDM tools. Handoff activities are brokered through iCloud and stored as `NSUserActivity` objects. Knowing the mechanism tells you exactly where to look.

---

## Concepts

### The prerequisite stack — what must be true for anything to work

Before touching any individual feature's toggle, verify this base condition:

| Requirement | Where to check |
|---|---|
| Same Apple ID on all devices | System Settings → Apple Account |
| Wi-Fi on (even for BLE-only discovery, the data channel needs Wi-Fi) | Menu bar / Control Center |
| Bluetooth on | Menu bar / Control Center |
| Handoff enabled on Mac | System Settings → General → AirDrop & Handoff |
| Handoff enabled on iPhone/iPad | Settings → General → AirDrop & Handoff |
| Devices within ~30 ft (BLE range) | Physical |
| Same local network OR Bluetooth pairing (feature-dependent) | Router admin / BT prefs |

macOS 26 Tahoe (released September 2025) tightened Apple ID verification for several Continuity features; older devices must meet minimum iOS/iPadOS 18 / macOS 26 requirements for the newest capabilities.

### Transport layers — what actually moves the bits

```
┌─────────────────────────────────────────────────────────────┐
│  Feature             Discovery    Data channel              │
├─────────────────────────────────────────────────────────────┤
│  AirDrop             AWDL/BLE     AWDL (peer Wi-Fi session) │
│  Handoff             iCloud/BLE   iCloud relay              │
│  Universal Clipboard BLE beacon   iCloud relay              │
│  Universal Control   BLE          Direct Wi-Fi (same LAN)   │
│  Sidecar             USB or Wi-Fi USB or AirPlay protocol   │
│  Continuity Camera   USB or Wi-Fi Direct Wi-Fi              │
│  iPhone Mirroring    BLE          Direct local session      │
│  Instant Hotspot     BLE          Wi-Fi (hotspot join)      │
│  SMS/Call relay      iCloud/BT    iCloud → VOIP channel     │
│  Auto Unlock/Approve BLE          BLE + Secure Enclave      │
└─────────────────────────────────────────────────────────────┘
```

**AWDL (Apple Wireless Direct Link)** is the custom 802.11 protocol Apple uses for peer-to-peer Wi-Fi. It time-multiplexes the Wi-Fi radio between the infrastructure AP connection and the peer channel using its own channal hopping scheme. The `awdl0` virtual interface is created by `airportd`/`wifid` and is visible in `ifconfig`. AWDL powers AirDrop and Sidecar's wireless mode.

The daemon responsible for coordinating nearly all Continuity features is **`sharingd`** (`/usr/libexec/sharingd`). It registers for BLE advertisements, coordinates with `bluetoothd`, and spawns the relevant subsystem code through XPC. A second key player is **`rapportd`** (`/usr/libexec/rapportd`), which maintains the authenticated persistent channel between nearby Apple devices — this is what makes Universal Clipboard and Handoff feel instantaneous.

### Handoff — resuming an activity

Handoff works through `NSUserActivity`. An app that adopts the API creates a named activity object encoding its current state (URL, scroll position, form data, whatever). macOS advertises that activity via a BLE beacon. The other device's `rapportd` picks it up, correlates it with the same Apple ID via iCloud, and surfaces it in:
- The Dock (a small icon of the source device at the far-right edge of the Dock)
- App Switcher (⌘Tab)
- Lock screen

The actual state data is transferred through iCloud, not directly over BLE — BLE is only the signal that an activity exists. This means Handoff works at range beyond BLE line-of-sight as long as both devices are on a cellular or Wi-Fi iCloud connection.

Apps must explicitly adopt `NSUserActivity` (`com.apple.developer.usernotifications.handoff` entitlement on iOS; `NSUserActivityTypes` key in Info.plist). First-party apps (Safari, Mail, Maps, Notes, Pages, Numbers, Keynote, FaceTime, Messages, Reminders, Calendar, Contacts) all do. Third-party adoption is variable.

### Universal Clipboard

Copy something on iPhone; paste it on Mac within about two minutes. The mechanism: `rapportd` watches the pasteboard daemon (`pboard`) for changes, encrypts the payload, and routes it through iCloud's CKShare infrastructure. The paste endpoint decrypts locally. No pasteboard content touches Apple's servers unencrypted — the iCloud relay uses end-to-end encryption for this channel.

The two-minute window is a TTL on the advertised activity. After that the remote pasteboard is considered stale.

> 🪟 **Windows contrast:** Windows 10+ has a Clipboard History (Win+V) that can sync across devices via a Microsoft account. The mechanism is similar — cloud relay with TTL — but Windows does not have a low-latency local BLE channel. macOS Universal Clipboard typically delivers in under a second on the same LAN.

### AirDrop — the deep mechanism

AirDrop has three discoverability modes:
- **Receiving Off** — device does not advertise
- **Contacts Only** — advertises, but hashes your Apple ID email + phone against the sender's contact list; transfer only proceeds if the hash matches
- **Everyone** — advertises to all; macOS 13+ requires physical proximity (AWDL range) for Everyone mode and added a 10-minute auto-reset to Contacts Only

**Protocol walkthrough:**

1. Sender opens AirDrop in Finder (Cmd+Shift+R) or uses the Share sheet. macOS brings up `awdl0`, starts BTLE advertising with a 6-byte ephemeral AirDrop ID.
2. Nearby devices receive the BLE advertisement. In **Contacts Only** mode, the advertisement includes SHA-256 hashes (truncated to 2 bytes) of the sender's email addresses and phone numbers. The receiver checks these truncated hashes against its local Contacts DB. This is the "hash oracle" vulnerability (PrivateDrop, 2021) — the short hash is reversible with a precomputed table.
3. If discovery passes, devices establish an AWDL session, exchange TLS 1.2 certificates (self-signed, pinned to Apple ID), and open an HTTP/HTTPS connection over AWDL.
4. Transfer proceeds as an HTTP multipart upload over the AWDL Wi-Fi peer session, completely invisible to your router or any network monitor.
5. Files land in `~/Downloads/` by default. They arrive with a quarantine extended attribute (`com.apple.quarantine`) and the `com.apple.metadata:kMDItemWhereFroms` xattr encoding the sender's AirDrop ID.

**Forensically important:** AirDrop transfers do not appear in router logs, proxy logs, or packet captures on the LAN switch — the AWDL traffic never touches the AP. The only reliable artifact trail is the macOS Unified Log.

> 🔬 **Forensics note:** Query AirDrop artifacts from the Unified Log:
> ```bash
> # Stream live AirDrop activity
> log stream --level=info \
>   --predicate "process == 'sharingd' AND subsystem == 'com.apple.sharing' AND category == 'AirDrop'"
>
> # Pull up to 7 days of historical AirDrop sends/receives
> log show --last 7d \
>   --predicate "subsystem == 'com.apple.sharing' AND category == 'AirDrop'" \
>   --style compact > /tmp/airdrop_log.txt
> ```
> The log entries include the sending device's AirDrop hash identifier, filenames, and file sizes. Log entries persist for approximately 7 days before rotation. For received files, check `~/Downloads/` for quarantine xattrs:
> ```bash
> xattr -p com.apple.quarantine ~/Downloads/suspect_file.pdf
> xattr -p com.apple.metadata:kMDItemWhereFroms ~/Downloads/suspect_file.pdf | xxd
> ```
> `QuarantineEventsV2.db` at `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` also records AirDrop receipts with timestamp and sender node name.

**macOS 26 Tahoe addition:** AirDrop now supports **AirDrop Codes** for unknown senders — a 6-digit code appears on the receiver's screen that the sender must enter before the transfer proceeds. This applies when receiving from non-contacts and provides a TOTP-style authentication layer that was missing from the original design.

### Universal Control — one keyboard/mouse, two screens

Universal Control lets your Mac's keyboard, trackpad, and mouse operate a nearby iPad (or another Mac). Unlike Sidecar, the iPad runs its own native iPadOS apps; you're just hijacking its input.

Transport: `rapportd` establishes a persistent authenticated channel over Wi-Fi (both devices on the same network, or Bluetooth pairing as fallback). HID events from the Mac keyboard/trackpad are serialized and forwarded; clipboard content follows via Universal Clipboard.

Requirements that trip people up:
- Both devices must be signed in with the **same Apple ID**
- "Handoff" must be on (System Settings → General → AirDrop & Handoff)
- "Allow Handoff between this Mac and your iCloud devices" specifically
- Both on same Wi-Fi network OR within Bluetooth range
- Mac: macOS 12.3+; iPad: iPadOS 15.4+

Activation: drag your cursor beyond the left or right edge of your Mac display — it "pushes through" to the iPad. System Settings → Displays → Add Display arranges which edge to push through.

> 🪟 **Windows contrast:** Windows has no equivalent. The closest third-party approximations (Synergy, Barrier, ShareMouse) use TCP connections and require manual configuration; Universal Control requires none.

### Sidecar — iPad as a second display

Sidecar extends or mirrors your Mac display onto an iPad, with the iPad running Apple's Sidecar app (not exposed as a user-installable app; it's a system daemon). The iPad also gains a virtual Touch Bar (now an onscreen sidebar with macOS control strip) and supports Apple Pencil for pressure-sensitive input in compatible apps.

Transport modes:
- **USB cable:** lowest latency (~10ms), no wireless congestion, charges the iPad, works without Wi-Fi
- **Wireless:** uses AWDL + AirPlay protocol stack; latency ~20-50ms in good conditions, degrades with Wi-Fi interference

Resolution: The iPad runs at its native resolution. macOS treats it as an additional `CGDirectDisplayID`; it appears in System Settings → Displays like any external monitor, with its own arrangement, scaling, and rotation settings.

The Sidecar daemon is `/System/Library/CoreServices/Sidecar.app` on the Mac side; `sidecarRelay` handles the frame transport. On the iPad, `SidecarDisplayAgent` is the receiving process.

Pencil input: Apple Pencil events are translated to macOS `NSEvent` pressure data, which Photoshop, Procreate (iPad), Pixelmator Pro, and other apps consume natively. This makes Sidecar useful as a pressure-sensitive graphics tablet even without any drawing software open on the iPad itself.

### Continuity Camera — iPhone as webcam and scanner

Three distinct sub-modes under the Continuity Camera umbrella:

**1. Webcam mode** (macOS 13+, iOS 16+): Your iPhone, when physically locked (screen off) and placed near your Mac on a MagSafe mount or holder, is automatically detected as a video input device — it appears in FaceTime, Zoom, Teams, etc. as "iPhone Camera." The iPhone must be on the same Apple ID and have Wi-Fi + BT on. No app installation. The USB cable path also works.

Special iPhone camera features available in webcam mode:
- **Center Stage** — crops and pans to keep you centered
- **Portrait** — background blur
- **Studio Light** — softens lighting on your face
- **Desk View** — uses the iPhone's ultra-wide camera with perspective correction to show your desk as if from above (a top-down document camera)

Transport: USB for zero-latency; AWDL for wireless. The Mac receives a compressed H.264/HEVC stream via the `AVCapture` framework, which treats the iPhone identically to a USB UVC device from the application layer's perspective.

**2. Document scan** (Insert from iPhone/iPad in any document): In any app with a document well (TextEdit, Pages, Keynote, etc.), right-click → Insert from iPhone or iPad → Scan Documents. The iPhone camera opens in scanning mode; OCR runs on-device; the result (as PDF or image) appears in the Mac document immediately via iCloud Handoff.

**3. Continuity Markup / Sketch**: Same mechanism — right-click → Add Sketch or Annotate — hands off a graphic to iPad/Apple Pencil and returns it signed or annotated.

### iPhone Mirroring

Introduced in macOS 15 (Sequoia), matured in macOS 26 Tahoe: your iPhone screen is rendered in a macOS window. You interact with it via your Mac keyboard and trackpad. The iPhone's screen goes physically dark (you can't use it simultaneously — this is enforced at the hardware level to prevent split-attention security issues).

**Transport:** Local encrypted channel negotiated by `rapportd` over BLE + local Wi-Fi. No Apple server relay — the stream is direct device-to-device on the local network. This means it works without internet access.

**Live Activities on Mac** (new in macOS 26 Tahoe): iPhone Lock Screen Live Activities — delivery countdowns, sports scores, rideshare ETAs — now appear on the Mac in the Notification Center and as menu bar widgets, even when iPhone Mirroring is not active. The data still flows through `rapportd`'s local channel.

**Data isolation:** Files, photos, and clipboard on the iPhone remain on the iPhone. The Mac receives only a video stream and sends back HID events. No iPhone files are indexed by Spotlight on the Mac.

> 🔬 **Forensics note (iPhone Mirroring):** A significant privacy issue was discovered in macOS 15.0: when iPhone Mirroring was active, stub app entries for iOS apps were created in the Mac's application database and indexed by Spotlight/MDM tooling, exposing the user's installed app list to corporate MDM software even though no app data was shared. Apple patched this in macOS 15.1 by excluding mirroring stubs from Spotlight indexing. On pre-15.1 systems you may find iOS app stubs at `~/Library/Application Support/iPhone Mirroring/Apps/` and corresponding Spotlight entries. This is a live artifact on un-patched systems in enterprise investigations.

### AirPlay to/from Mac

**AirPlay to Mac** (macOS 12+): Your Mac appears as an AirPlay receiver to any iOS/tvOS/macOS device on the same network. Any app (or the entire iOS screen) can be mirrored or cast to your Mac — your Mac runs the AirPlay receiver daemon `AirPlayXPCHelper`. Enable in System Settings → General → AirDrop & Handoff → AirPlay Receiver.

**AirPlay from Mac**: Your Mac can stream to Apple TV, HomePod, or AirPlay 2-compatible speakers. The status bar shows the AirPlay icon; Control Center shows output routing. The AirPlay protocol is RAOP (Remote Audio Output Protocol) for audio and a custom video framing protocol for video; both negotiate over TCP 7000/7001 with mDNS discovery.

### Instant Hotspot

When your iPhone has a cellular data connection and Personal Hotspot is enabled, your Mac automatically sees it in Wi-Fi preferences without any password entry — the Wi-Fi password is delivered out-of-band via BLE. The Mac and iPhone must share the same Apple ID. The iPhone's hotspot name appears in Network Preferences pre-authenticated.

Signal/battery status for the hotspot is relayed via BLE and shown in the Mac's Wi-Fi menu next to the SSID.

### Phone and SMS relay

- **iPhone Cellular Calls on Mac**: When your iPhone is on the same Wi-Fi network and both devices share an Apple ID, incoming calls ring on your Mac too. FaceTime handles the audio relay; the Mac shows a banner notification and can accept/decline. Enable on iPhone: Settings → Phone → Calls on Other Devices. macOS 26 added a standalone **Phone app** that surfaces voicemail, call history, and dial-out from the Mac.

- **Text Message Forwarding (SMS/MMS/RCS)**: iMessage works natively via your Apple ID; SMS/MMS from non-Apple contacts are relayed from your iPhone over iCloud. Enable: iPhone Settings → Messages → Text Message Forwarding → [your Mac].

### Apple Watch unlock and approve

**Auto Unlock**: Wear your Apple Watch; walk to your sleeping Mac; it wakes and unlocks without a password. The Watch must be on your wrist (worn detection via wrist sensor + heart rate), unlocked, and within BLE range of the Mac.

**Approve with Apple Watch**: Instead of typing your password for `sudo`, Keychain access, or app installation, a tap of the Watch's side button approves. This replaces the `SecurityAgentPlugin` password UI with a Watch prompt. Enable: System Settings → Touch ID & Password → Apple Watch (shows Watch name).

Under the hood, the Watch holds a credential that the Mac's Secure Enclave validates — neither party transmits the user's macOS password. The transaction is signed via the Watch's own Secure Enclave (sep0) over BLE.

> 🪟 **Windows contrast:** Windows Hello with a paired Bluetooth device exists but requires explicit Bluetooth pairing setup and is device-specific. The macOS Watch integration is friction-free because the same Apple ID already asserts device ownership.

---

## Hands-on (CLI & GUI)

### Check Continuity daemons

```bash
# Are the key daemons running?
pgrep -la sharingd rapportd
# Expected: two lines with PIDs

# What is rapportd connected to?
lsof -p $(pgrep rapportd) -i | grep ESTABLISHED
# Shows active remote peers (IP:port for each connected nearby Apple device)
```

### Inspect the awdl0 interface

```bash
ifconfig awdl0
# Look for flags: UP BROADCAST RUNNING MULTICAST
# If AirDrop is actively discovering, you'll see traffic here:
netstat -I awdl0 -w1
```

### AirDrop discoverability audit

```bash
# Read current AirDrop discoverability setting
defaults read com.apple.sharingd DiscoverableMode
# 0 = Off, 1 = Contacts Only, 2 = Everyone

# Set to Contacts Only (safest for daily use)
defaults write com.apple.sharingd DiscoverableMode -int 1
killall -HUP sharingd
```

### Query Handoff activity

```bash
# Handoff goes through rapportd; see what activities are being advertised
log show --last 1h \
  --predicate "process == 'rapportd'" \
  --style compact | grep -i handoff
```

### Diagnose Universal Clipboard failures

```bash
# Watch pboard (pasteboard daemon) and rapportd together
log stream --predicate "(process == 'pboard' OR process == 'rapportd') AND subsystem == 'com.apple.sharing'"
# Then copy something on your iPhone — you should see log lines within ~1 second
```

### Check Sidecar status

```bash
# List connected displays including Sidecar
system_profiler SPDisplaysDataType | grep -A5 "Online\|Offline\|iPad"

# Check the Sidecar relay process
pgrep -la sidecarRelay
```

### Toggle AirPlay Receiver

```bash
# Disable AirPlay Receiver (reduce attack surface on untrusted networks)
defaults write com.apple.controlcenter "AirplayRecieverEnabled" -bool false
# Or via System Settings → General → AirDrop & Handoff → AirPlay Receiver
```

---

## Labs

### Lab 1 — AirDrop a file and trace the artifacts

> ⚠️ **ADVANCED:** This lab intentionally transfers a test file and inspects system logs. No destructive operations. Rollback: delete the received file and clear logs with `sudo log erase --all` if you need a clean slate.

1. On your iPhone, open Photos and select any photo.
2. Share → AirDrop → [your Mac].
3. Accept on the Mac.
4. Immediately run:
   ```bash
   log show --last 5m \
     --predicate "subsystem == 'com.apple.sharing' AND category == 'AirDrop'" \
     --style compact
   ```
5. Locate the received file and inspect its xattrs:
   ```bash
   ls -la ~/Downloads/
   xattr -l ~/Downloads/<received_file>.jpg
   ```
   You should see `com.apple.quarantine` and `com.apple.metadata:kMDItemWhereFroms`.
6. Query the quarantine database:
   ```bash
   sqlite3 ~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2 \
     "SELECT datetime(LSQuarantineTimeStamp + 978307200, 'unixepoch', 'localtime'), \
      LSQuarantineAgentName, LSQuarantineDataURLString \
      FROM LSQuarantineEvent \
      ORDER BY LSQuarantineTimeStamp DESC LIMIT 5;"
   ```
   AirDrop receipts appear with `com.apple.sharingd` as the agent.

**Expected findings:** Log entry names the sender's device (hash or display name), lists the filename and byte count. QuarantineEventsV2 records the AirDrop event with a timestamp matching the transfer.

---

### Lab 2 — Set up Continuity Camera (iPhone as webcam)

> No destructive operations.

**Requirements:** iPhone 12 or later on iOS 16+; Mac on macOS 13+; same Apple ID on both; Wi-Fi and Bluetooth on.

1. Mount your iPhone landscape on the back of your Mac's display or a stand — camera facing the room. iPhone must be locked (screen off).
2. Open FaceTime on the Mac (or any video-calling app).
3. In FaceTime → Video menu, look for your iPhone as a camera option (e.g., "Quentin's iPhone").
4. Select it. Your iPhone camera feed appears.
5. Explore the Video Effects: FaceTime → Video → Portrait Mode, Center Stage, Studio Light, Desk View.
6. Confirm the transport interface:
   ```bash
   # While Continuity Camera is active:
   ifconfig | grep -A4 awdl0
   netstat -I awdl0 -w1
   # Watch for traffic if on wireless; or check for USB device if cabled
   ```
7. For the Desk View angle (requires iPhone 13+): place a piece of paper with writing on your desk below the iPhone. Enable Video → Desk View. You should see a top-down perspective of your desk surface.

**Expected result:** iPhone camera appears as a standard `AVCaptureDevice` in macOS; no driver installation was needed; switching between Desk View and front-facing is instantaneous.

---

### Lab 3 — Universal Clipboard round-trip

> No destructive operations. Requires iPhone or iPad on same Apple ID.

1. On your Mac, ensure Handoff is on: System Settings → General → AirDrop & Handoff → "Allow Handoff between this Mac and your iCloud devices" is checked.
2. Start a log stream in Terminal:
   ```bash
   log stream --predicate "(process == 'rapportd' OR process == 'pboard')" \
     --style compact 2>&1 | grep -i "clipboard\|pasteboard\|handoff"
   ```
3. On your iPhone, copy a short piece of text (long-press any text → Copy).
4. Immediately switch to a Mac app (TextEdit, etc.) and press ⌘V.
5. Observe: the iPhone text pastes on the Mac in under 2 seconds.
6. Watch the log stream — you'll see `rapportd` receive the pasteboard payload and `pboard` update its contents.

**Reverse test:** Copy text on the Mac, paste on iPhone. If it doesn't paste within 2 seconds, check:
```bash
# Is rapportd actually running?
pgrep rapportd
# Check BT status
system_profiler SPBluetoothDataType | grep -A2 "State:"
```

---

## Pitfalls & gotchas

### The "Handoff icon won't appear" checklist

Work through this in order — do NOT skip steps:

1. **Same Apple ID?** Verify on both devices — account mismatch is the #1 cause.
2. **Handoff toggle on both devices?** Mac: System Settings → General → AirDrop & Handoff. iPhone: Settings → General → AirDrop & Handoff.
3. **Bluetooth on?** Handoff requires BLE even if iCloud does the heavy relay. A Bluetooth off state prevents discovery.
4. **Same Wi-Fi network?** Some features (Universal Control, Sidecar wireless) require network adjacency, not just BLE proximity.
5. **Private Relay or VPN disrupting iCloud relay?** iCloud Private Relay can interfere with rapportd's device-to-device channel on some configurations. Try disabling temporarily.
6. **Firewall blocking?** System Settings → Network → Firewall. Sidecar and Universal Control need inbound local connections.
7. **Are both devices within ~30 feet?** BLE range is ~30 ft in open space; walls reduce it significantly.
8. **Has rapportd restarted recently?** After OS updates, `rapportd` sometimes doesn't reconnect correctly:
   ```bash
   sudo killall rapportd
   # It restarts automatically via launchd
   ```
9. **Is the specific app Handoff-capable?** Check: do the three dots (…) appear under the app's Dock icon on the other device? If not, the app hasn't implemented `NSUserActivity`.

### AirDrop "not showing" on the receiver side

- On iPhone/iPad: pull down Control Center and long-press the network tile cluster → AirDrop. Confirm it's not set to "Receiving Off."
- macOS discovery is instantaneous if `sharingd` is healthy; if a restart is needed: `sudo killall sharingd`.
- In "Contacts Only" mode, you must be in each other's contacts with matching email/phone. AirDrop computes SHA-256 hashes of your Apple ID email/phone and compares them against the receiver's Contacts database — if the email in your Apple ID is not in the receiver's contacts (or vice versa), discovery silently fails.
- macOS 13+ limits "Everyone" to 10 minutes. If you expect to receive from strangers repeatedly, the setting reverts; build it into your muscle memory to re-enable.

### Sidecar resolution and scaling surprises

Sidecar renders at the iPad's native pixel resolution but scales macOS points to fit. An iPad Pro 12.9" shows noticeably more screen real estate than an iPad mini. If text looks tiny, go to System Settings → Displays → [iPad display] → Resolution → Larger Text.

If Sidecar wireless latency is high (>100ms), switch to USB. Wireless Sidecar shares your Wi-Fi radio with all other traffic; USB eliminates that contention entirely.

### Universal Control cursor "stuck at the edge"

Move the cursor toward the edge of the display that faces the iPad (set up in System Settings → Displays). The push-through gesture requires a deliberate slow push, not a fast swipe — a fast swipe stops at the edge. If the cursor never crosses: disconnect and re-add the Display in System Settings → Displays → Add Display.

### iPhone Mirroring and MDM / enterprise Macs

On a company-managed Mac: MDM profiles can disable iPhone Mirroring entirely (`com.apple.applicationaccess` restriction key `allowiPhoneMirroring`). If the feature is absent from your Mac, MDM has removed it. Don't file a bug; check with IT.

On pre-macOS 15.1 systems, iPhone Mirroring exposed iOS app metadata to MDM tooling (app names, versions, icons). This was patched in 15.1 / 26.x. If you're running an older system on a corporate Mac with iPhone Mirroring, stop until you update.

### Auto Unlock stops working after password change

Changing your macOS login password invalidates the Watch authentication credential. Go to System Settings → Touch ID & Password → Apple Watch → Remove, then re-add the Watch. The Watch re-enrolls its Secure Enclave credential against the new password verifier.

---

## Key takeaways

- Continuity is seventeen-plus features built on three transports: BLE (discovery), AWDL (direct Wi-Fi peer sessions for AirDrop/Sidecar), and iCloud relay (Handoff, Universal Clipboard, SMS relay).
- The gating daemon is `rapportd`; the AirDrop/Sidecar coordinator is `sharingd`. Both are launchd agents that restart automatically.
- AirDrop bypasses all network infrastructure. The Unified Log (`com.apple.sharing` subsystem) is the only system record of what was transferred to or from whom.
- AirDrop "Contacts Only" mode leaks truncated SHA-256 hashes of your email and phone number in BLE advertisements; these are reversible with precomputed tables (PrivateDrop vulnerability, unpatched in the BLE advertisement layer).
- iPhone Mirroring is a local-only encrypted stream; no Apple server relay. The macOS 15.0 metadata leak (iOS app stubs visible to MDM) was patched in 15.1.
- Universal Clipboard uses end-to-end encryption over iCloud relay; clipboard content is not stored on Apple servers.
- Apple Watch Auto Unlock/Approve uses Secure Enclave credential exchange, not password transmission.
- macOS 26 Tahoe adds AirDrop Codes (sender-must-enter verification), Live Activities from iPhone in Notification Center, and a Phone app for voicemail/call history.
- Troubleshooting order: Apple ID match → Handoff toggle → Bluetooth → Wi-Fi adjacency → `rapportd` restart → app-level NSUserActivity adoption.

---

## Terms introduced

| Term | Definition |
|---|---|
| AWDL | Apple Wireless Direct Link — Apple's proprietary 802.11 peer-to-peer protocol, creates the `awdl0` virtual interface |
| rapportd | Daemon maintaining authenticated persistent channel between nearby Apple devices for Handoff, Universal Clipboard, Universal Control |
| sharingd | Daemon coordinating AirDrop, Sidecar, and related sharing services |
| NSUserActivity | Foundation class apps use to encode resumable state; the API powering Handoff |
| AirDrop ID | Ephemeral 6-byte BLE identifier used during AirDrop discovery sessions |
| Contacts Only | AirDrop mode that gate-checks discovery via truncated SHA-256 hashes of sender contact identifiers |
| AWDL peer session | Direct Wi-Fi connection established between two Apple devices without going through a router |
| sidecarRelay | macOS process handling frame transport for wireless Sidecar |
| QuarantineEventsV2 | SQLite database at `~/Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2` recording file receipts including AirDrop |
| pboard | The pasteboard daemon managing clipboard state; updated by rapportd for Universal Clipboard |
| Live Activities | Dynamic iPhone Lock Screen widgets; macOS 26 surfaces them in Notification Center via rapportd |
| AirDrop Codes | macOS 26 verification step: 6-digit code receiver shows that sender must enter before transfer completes |

---

## Further reading

- [[part-01-architecture/08-security-architecture]] — SIP, Gatekeeper, TCC; the security model that Continuity features operate within
- [[part-01-architecture/10-unified-logging-and-diagnostics]] — Deep dive on the Unified Log and how to query it for forensic investigation
- [[part-02-gui/00-finder-mastery]] — AirDrop surface within Finder (Cmd+Shift+R, sidebar AirDrop item)
- [[part-05-security-forensics]] — macOS forensics: artifact locations, Unified Log analysis, QuarantineEventsV2
- [[part-08-networking]] — AWDL, mDNS, Bonjour, and the network stack Continuity runs on
- Apple Platform Security guide (developer.apple.com/documentation/security) — sections on iCloud E2E encryption and device authentication
- PrivateDrop (privatedrop.github.io) — academic analysis of AirDrop's BLE privacy vulnerabilities; the SHA-256 oracle attack and proposed fix
- Kinga Kięczkowska, "Introduction to AirDrop Forensics" (Medium) — practical Unified Log and xattr analysis walkthrough
- Howard Oakley, Eclectic Light Company (eclecticlight.co) — ongoing coverage of AWDL behavior, Sidecar internals, and macOS network changes
- Sevco Security, "Broken Mirror: iPhone Mirroring at Work" — the enterprise app-exposure disclosure; MDM implications for corporate Mac management
