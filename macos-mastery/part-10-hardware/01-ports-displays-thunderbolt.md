---
title: Ports, Displays, Thunderbolt & Docks
part: P10 Hardware
est_time: 60 min read + 45 min labs
prerequisites: [none]
tags: [macos, hardware, thunderbolt, usb4, displays, docks, hidpi, scaling]
---

# Ports, Displays, Thunderbolt & Docks

> **In one sentence:** Every USB-C port on your Mac is physically identical but may be electrically and logically vastly different — knowing which protocol is tunneled over each connector, what the display-pipeline count for your chip tier is, and where docks can and cannot help you prevents hours of debugging and embarrassing hardware purchases.

---

## Why this matters

Coming from Windows/PC, you are accustomed to a world where a GPU has discrete outputs: two HDMI ports are two display pipelines. You buy a graphics card with four outputs, you get four monitors. macOS on Apple Silicon works differently in a way that regularly surprises experienced engineers: the number of external displays your Mac can drive is determined by the SoC die, not by how many ports you plug into. A $300 Thunderbolt dock on an M2 MacBook Air drives exactly one external display — the same number as a bare cable. A $10 USB-C hub "adds" a second monitor output but it won't work. Knowing the real limits upfront lets you spec hardware correctly the first time.

This lesson covers the full stack: the physical connectors and cable taxonomy, Thunderbolt architecture and bandwidth budgets, the display pipeline model, scaling and color on external displays, dock selection criteria, and practical diagnostics.

---

## Concepts

### 1. The USB-C shape is not a protocol

USB-C (officially "USB Type-C") is a **connector form factor**, not a speed or feature. Every modern Mac port uses this shape, but the electrical and protocol layers tunneled over it differ wildly:

| Protocol | Bandwidth (bidirectional) | Video out | Power Delivery | Notes |
|---|---|---|---|---|
| USB 2.0 | 480 Mbps | No | 5W (basic) | Rare on modern Macs; some hubs downgrade here |
| USB 3.2 Gen 1 | 5 Gbps | No (or alt-mode only) | Up to 15W | Common on cheap USB-C hubs |
| USB 3.2 Gen 2 | 10 Gbps | DP Alt Mode optional | Up to 100W | Mid-range hubs/docks |
| USB4 Gen 2×2 | 20 Gbps | DP 2.0 alt mode | Up to 100W | All Apple Silicon, TB4-equivalent minimum |
| USB4 Gen 3×2 | 40 Gbps | DP 2.1 alt mode | Up to 240W | Equivalent feature set to TB4 without Intel cert |
| Thunderbolt 3 | 40 Gbps | DP 1.4 | Up to 100W | Intel cert, PCIe ×4 tunnel |
| Thunderbolt 4 | 40 Gbps | DP 1.4 (two streams) | Up to 100W | Mandates PCIe ×32 tunneling, two 4K@60Hz |
| Thunderbolt 5 | 80 Gbps (120 Gbps Boost) | DP 2.1 UHBR20 | Up to 240W | On M4 Pro/Max and M4/M5 MacBook Pro |

The critical insight: **every Apple Silicon Mac port meets at minimum USB4 Gen 2×2 (20 Gbps) spec**, and the Thunderbolt-certified ports go to 40 Gbps (TB4) or 80/120 Gbps (TB5). A cheap cable or hub can silently negotiate down to USB 3.2 or even USB 2.0, which is why "Thunderbolt cable" is not a marketing term but an electrical requirement.

> 🪟 **Windows contrast:** On Windows, USB-C ports can be "USB only" or "Thunderbolt only" on the same chassis. macOS machines have been uniformly USB4 across all USB-C ports since M1, but the distinction between base ports and Thunderbolt-certified ports still matters for TB-specific features (PCIe tunnel, daisy-chain, Thunderbolt-only docks).

### 2. Thunderbolt architecture: tunneling and daisy-chains

Thunderbolt is built on three tunnel types sharing the physical link bandwidth:

- **PCIe tunnel** — exposes a PCIe ×4 (TB4) or ×8 (TB5) lane to an external device. This is how eGPUs, Thunderbolt NVMe enclosures, capture cards, and Thunderbolt NICs work.
- **DisplayPort tunnel** — carries raw DP signal to a display or dock.
- **USB tunnel** — for USB devices hanging off a Thunderbolt hub/dock.

On Thunderbolt 4 (40 Gbps), the bandwidth budget is shared across all three tunnels simultaneously. A realistic daisy-chain scenario on one TB4 port: one 4K@60Hz display (about 14 Gbps) + USB peripherals (5–10 Gbps effective) + file transfer to an NVMe enclosure (remaining ~16 Gbps) — you can saturate a single port.

**Thunderbolt 5 (80/120 Gbps Boost):** The M4 Pro/Max MacBook Pro and M4 Pro Mac mini introduced TB5 ports. Boost mode (120 Gbps) kicks in asymmetrically — it uses extra bandwidth in the receive direction, enabling a single cable to drive an 8K display or multiple 4K@240Hz displays. DisplayPort 2.1 with UHBR20 (Ultra High Bit Rate 20, meaning 20 Gbps per lane × 4 lanes) is tunneled here.

**Daisy-chaining:** Thunderbolt devices can be chained, up to 6 devices per host port, each consuming from the shared pool. The last device in the chain sees what's left after upstream devices claim their allocations. Total cable run: up to 2 m for passive cables, 40+ m for active optical TB cables.

**DFU port caveat:** Howard Oakley's research (The Eclectic Light Company, 2026) confirmed that Apple Silicon Macs have one port designated as the DFU (Device Firmware Update) port. It looks identical to all others but is restricted: it cannot be used to boot macOS from an external disk or create a LocalPolicy. On MacBook Pros it is typically the left rear port. If you are booting from external media for forensic imaging, use any *non-DFU* port.

> 🔬 **Forensics note:** When acquiring an Apple Silicon Mac via Target Disk Mode (TDM), confirm you are plugged into a non-DFU port — the DFU port will fail silently for TDM in some firmware revisions. Also note: eGPUs are not supported on Apple Silicon at all; macOS refuses to enumerate external GPUs on AS Macs even if the hardware is physically connected.

### 3. The display pipeline model — the number that burns switchers

On Apple Silicon, each display pipeline is implemented in silicon on the SoC die, not in the GPU cluster. The consequence: **the maximum number of external displays is a chip-tier constant, not a port count or cable count.**

| Chip | MacBook / Desktop model | External display count | Lid-open rule |
|---|---|---|---|
| M1 base | MacBook Air/Pro 13" M1, Mac mini M1 | **1** | 1 external always |
| M2 base | MacBook Air/Pro 13" M2 | **1** | 1 external always |
| M3 base | MacBook Air 15" M3, MacBook Pro 14" base M3 | **2** (lid closed only for second) | 1 with lid open; 2 only if built-in disabled |
| M4 base | MacBook Air M4, Mac mini M4 | **2** | 2 external + built-in open simultaneously |
| M5 base | MacBook Air M5 | **2** | 2 external + built-in open simultaneously |
| M1/M2 Pro | MacBook Pro 14"/16" M1/M2 Pro | **2** | 2 external + built-in |
| M3 Pro | MacBook Pro 14"/16" M3 Pro | **2** | 2 external + built-in |
| M4 Pro | MacBook Pro 14"/16" M4 Pro, Mac mini M4 Pro | **3** (2×TB5 + HDMI) | 3 external + built-in |
| M5 Pro | MacBook Pro M5 Pro | **3** | 3 external + built-in |
| M1/M2/M3 Max | MacBook Pro 14"/16" Max | **4** | 4 external + built-in |
| M4 Max | MacBook Pro 16" M4 Max, Mac Studio M4 Max | **5** | 5 external + built-in |
| M5 Max | MacBook Pro M5 Max | **4** | 4 external + built-in |
| M2/M3 Ultra | Mac Pro, Mac Studio Ultra | **8** | 8 external |
| M4 Ultra | Mac Studio M4 Ultra | **10** | 10 external |

**The dock does not add pipelines.** A Thunderbolt dock with four USB-C video outputs still only passes through the pipelines the Mac provides. Plugging into a CalDigit TS4 on an M2 MacBook Air gives you one external display regardless of how many ports the dock has.

### 4. DisplayLink: the software workaround and its tradeoffs

DisplayLink (now a Synaptics product) solves the pipeline limit by bypassing the hardware display controller entirely. A DisplayLink dock or adapter:

1. Runs a macOS kernel extension (kext) / system extension.
2. Captures framebuffer updates via the CoreGraphics display server.
3. Compresses and streams them over USB to a dedicated DisplayLink chip in the dock.
4. The chip decodes and drives the display independently.

The practical result: any USB-A/USB-C port becomes a display output, pipeline limit bypassed.

**Tradeoffs:**
- **CPU overhead:** Compression runs on the CPU (typically 5–15% extra CPU use per DisplayLink display, varies by resolution and content). On M-series this is usually negligible, but video playback and GPU-heavy work on a DisplayLink display can stutter.
- **Latency:** Adds 1–2 frames of lag. Fine for code/docs; noticeable for video/games.
- **DRM content:** Apple's Fairplay will not output DRM-protected content (Apple TV+, Netflix 1080p, etc.) to a DisplayLink display — the path is not hardware-trusted. You'll get a black rectangle or "HDCP not supported" error.
- **HDR:** DisplayLink's HDR support is limited and inconsistent in practice (as of macOS 26).
- **Driver install required:** Privacy & Security → approval for the system extension; also requires Screen Recording permission to capture the framebuffer. After a macOS major upgrade, re-approve the driver.

DisplayLink docks typically cost $20–40 more than equivalent non-DisplayLink models.

> 🔬 **Forensics note:** The DisplayLink system extension injects itself deep into the graphics stack and must capture the full screen to function. On a machine under investigation, its presence in `/Library/Application Support/Synaptics/` and the kernel log (`log show --predicate 'process == "DisplayLinkUserAgent"'`) is an artifact worth noting. It is also a potential attack surface for sensitive-display capture.

### 5. Ports on specific Mac models (what's actually there)

**MacBook Pro 14"/16" (M4 Pro/Max, 2024+):**
- 3× Thunderbolt 5 (left side: 2, right side: 1 on 14"; left: 3 on 16")
- 1× HDMI 2.1 (up to 8K@60Hz or 4K@240Hz on Max)
- 1× SDXC card reader (UHS-II, ~312 MB/s)
- 1× MagSafe 3
- 1× 3.5mm headphone jack (high-impedance DAC)

**MacBook Air (M4, 2025):**
- 2× Thunderbolt 4 (left side only)
- 1× MagSafe 3
- 1× 3.5mm headphone jack

**Mac mini (M4, 2024):**
- 2× Thunderbolt 5 (rear, M4 Pro: 3× TB5)
- 2× USB-A 3.2 Gen 2 (rear)
- 1× HDMI 2.1 (rear)
- 1× 3.5mm headphone jack (front)
- 2× USB-C 3.2 Gen 2 (front, M4 base only — NOT Thunderbolt)
- Gigabit or 10GbE Ethernet (M4 Pro)

**Mac Studio (M4 Max/Ultra, 2025):**
- 4× Thunderbolt 5 (rear) + 2× Thunderbolt 5 or USB4 (front)
- 3× USB-A 3.2 Gen 2
- 1× HDMI 2.1
- 1× SDXC (UHS-II)
- 1× 3.5mm front, 1× 3.5mm rear (rear is high-impedance)

### 6. The headphone jack — it's not just a headphone jack

The headphone jack on MacBook Pros and Mac Studio is not a commodity audio output. Apple ships a built-in high-impedance DAC capable of driving professional headphones rated up to 1000Ω. macOS auto-detects plug impedance and adjusts output voltage accordingly. Headphones rated at 150–600Ω (Sennheiser HD 800, AKG K712, Beyerdynamic DT 1990) that require a dedicated headphone amp on a PC can run directly from a MacBook Pro jack with adequate volume. MacBook Air jacks are standard-impedance only.

> 🪟 **Windows contrast:** Virtually no Windows laptop ships with a high-impedance headphone output. This is a genuinely differentiating feature, not marketing.

### 7. MagSafe vs. USB-C charging and power delivery

MagSafe 3 on MacBook Pro/Air carries power only — no data, no video. It uses a proprietary connector but the upstream charger end is USB-C. The negotiation protocol is Apple-proprietary, but the physical cable is USB-C on the brick side.

**USB-C Power Delivery (PD):** You can charge any modern Mac via any Thunderbolt/USB4 port using a USB-C PD charger. Wattage matching matters:

| Mac | Recommended wattage | Minimum to not drain | Max input |
|---|---|---|---|
| MacBook Air M4 | 30–45W | 20W (idle only) | 70W |
| MacBook Pro 14" M4 | 70W | 45W (light load) | 140W |
| MacBook Pro 16" M4 | 140W | 70W (light load) | 140W |

Under-wattage charging works but the Mac may discharge slowly under load. Over-wattage is fine — the Mac negotiates what it needs. When charging via the Thunderbolt port and running peripherals, bandwidth is slightly reduced because USB PD negotiation shares the signal channel, but in practice on TB4/TB5 this is negligible.

A dock's power passthrough: a Thunderbolt dock charges the host Mac via a single USB-C cable. Cheap docks passthrough 60–85W; a quality powered dock (CalDigit TS4, OWC Thunderbolt 4 Hub) passes through 96–100W, sufficient for a MacBook Pro 14" under moderate load.

### 8. The SDXC slot

MacBook Pros and Mac Studio have a native SDXC slot rated for UHS-II (bus speed up to 312 MB/s). The slot is controlled by Apple's SoC directly — no USB-to-SD bridge chip in the path. This matters forensically: `diskutil` sees SD cards as `/dev/disk2` type devices with full read/write access. `dd` imaging works. Write-blocking requires either a hardware write blocker in the SD slot path or leveraging macOS's "read-only" mount flag (which is advisory to the OS, not enforced at the hardware level on native slots).

> 🔬 **Forensics note:** SD cards in the native slot enumerate in `system_profiler SPUSBDataType` under the IOService tree differently from USB card readers — they appear as `IOSDCard` under the Apple SD Host Controller. Knowing this distinguishes a native slot acquisition from a USB reader acquisition in your chain-of-custody notes.

### 9. Display connection protocols and refresh/resolution limits

Not all connections carry the same maximum bandwidth to a display:

| Connection | Max resolution | Max refresh | HDR | Notes |
|---|---|---|---|---|
| TB4 (DP 1.4 tunnel) | 6K@60Hz, 4K@120Hz | 120Hz | HDR10/Dolby Vision | Apple Pro Display XDR, LG UltraFine 5K |
| TB5 (DP 2.1 tunnel) | 8K@60Hz, 4K@240Hz | 240Hz | HDR10/DV | Requires TB5-capable display or adapter |
| HDMI 2.1 (Pro/mini/Studio) | 8K@30Hz or 4K@240Hz | 240Hz (4K) | HDR10/eARC | Direct, no tunnel overhead |
| USB-C Alt Mode (DP 1.4) | 4K@60Hz | 60Hz | HDR10 | Non-TB USB-C ports (Mac mini front) |
| DisplayLink (any USB) | Up to 4K@60Hz | 60Hz | Limited | CPU-driven; DRM blackout |

**Apple Pro Display XDR over TB4:** Despite the 6K resolution (6016×3384), Apple uses a compressed pixel format over the DisplayPort tunnel and a proprietary timing to fit inside 40 Gbps. If you attach a third-party 6K display that doesn't implement Apple's timing, you may only get 4K@60Hz out of a TB4 port without a specific driver.

### 10. macOS scaled resolution and HiDPI

macOS renders to a "logical resolution" and then scales to the display's physical pixels. The system calls this "Retina" when the scale factor is 2× (or when it uses subpixel positioning to appear sharp on high-density panels).

**The HiDPI model:**
- The OS maintains a "backing store" at 2× the logical resolution.
- At 2× integer scale, every logical pixel maps to exactly 4 physical pixels — sharp, no blurring.
- At non-integer scales (e.g. 1.5×, the "Looks like 1440p" setting on a 4K display), the OS renders to an intermediate resolution and then scales — introducing mild resampling blur. This is the trade-off macOS makes to offer more desktop space.

The "Looks like…" presets in **System Settings → Displays → Resolution** show you the equivalent desktop space, not the actual render resolution. "Looks like 1440p" on a 4K display (3840×2160) renders the backing store at 2880×1620 (exactly 2× the 1440×810 logical) — which is then upscaled to 3840×2160. Slightly blurry on exact diagonal pixels, fine for text.

**ProMotion (120Hz):** MacBook Pro 14" and 16" have ProMotion built-in displays that dynamically switch from 24Hz to 120Hz based on content. External displays also run at whatever refresh they are connected at. Select the refresh rate in System Settings → Displays → Refresh Rate. macOS will not offer refresh rates the GPU cannot sustain at the chosen resolution/color depth.

**Color profiles and reference modes (MacBook Pro/Studio Display):**
- macOS uses ICC profiles to color-manage all display output.
- MacBook Pro has Apple reference modes: "Pro Display XDR (P3-1600 nits)", "True Tone reference", etc. These override the standard sRGB mapping for color-critical work.
- For forensic/color-neutral display, use "sRGB IEC61966-2.1" in System Settings → Displays → Color Profile. This disables Apple's tone mapping and gives you a flat, standard output.
- `displayplacer` (third-party CLI) and `system_profiler SPDisplaysDataType` expose the current ICC profile in use.

**MonitorControl:** A free/open-source app that sends DDC/CI commands to control external monitor brightness and volume from the macOS menu bar, mimicking the keyboard shortcuts that only work natively on Apple displays. It works on most modern monitors via HDMI/DisplayPort; Thunderbolt-only paths may require "software brightness" mode (which dims the macOS framebuffer instead of the panel backlight). Install via Homebrew: `brew install --cask monitorcontrol`.

**BetterDisplay:** A more powerful paid alternative offering custom HiDPI resolutions, XDR brightness unlock, virtual screens, and DDC control. Particularly useful for forcing HiDPI on a 1080p external display by creating a virtual 4K mirror. Compatible with macOS 26 Tahoe.

### 11. Docks and hubs — the quality ladder

```
Cheap USB-C hub ($20-50)
├── USB 3.2 Gen 1 data ports (5 Gbps)
├── USB-C Power Delivery passthrough (60-85W)
├── HDMI 1.4 or 2.0 (one display, limited to hardware pipeline)
└── No PCIe tunnel — it's a USB hub with Alt-Mode video, not Thunderbolt

Thunderbolt 4 dock ($150-350) — CalDigit TS4, OWC TB4, LG UltraFine 4K w/ hub
├── Full 40 Gbps TB4 upstream
├── PCIe tunnel (NVMe enclosures, capture cards work)
├── Multiple downstream TB4 ports (daisy-chain)
├── USB-A 3.2 Gen 2 ports (10 Gbps each)
├── Ethernet (2.5GbE typical)
├── SD card reader
├── 96-100W host charging passthrough
└── Displays: limited by host Mac's pipeline count (dock doesn't add)

Thunderbolt 5 dock ($200-400+) — OWC TB5 Hub, Plugable TB5 Dock
├── 80 Gbps upstream (120 Gbps Boost)
├── Required for 8K or 4K@240Hz display passthrough from TB5 Mac
├── 2-4 downstream TB5/USB4 ports
└── 140-180W host charging

DisplayLink dock ($150-300) — Plugable UD-6950, CalDigit Element Hub + DL adapter
├── Includes standard USB hub + DisplayLink chip
├── Requires Synaptics DisplayLink driver (kext/system extension)
├── Bypasses Mac display pipeline limit (extra displays via USB)
├── CPU overhead, no DRM video, limited HDR
└── Good for extra monitor for Slack/Terminals; not ideal for primary creative display
```

**The "just buy a cheap hub" trap:** USB-C hubs labeled "7-in-1" or "USB-C Hub with 4K HDMI" are almost never Thunderbolt. They are USB 3.2 hubs using DisplayPort Alt Mode. They will output one display (consuming one of your Mac's native pipelines), and USB bandwidth is shared across all ports. Fine for low-demand setups; not for NVMe enclosures or high-bandwidth peripherals.

---

## Hands-on (CLI & GUI)

### Enumerate ports and their actual capabilities

```bash
# Full Thunderbolt bus information — shows controller, speed, connected devices
system_profiler SPThunderboltDataType

# USB devices and their negotiated speed (look for "Speed:" field)
system_profiler SPUSBDataType

# Display information: resolution, color profile, refresh rate, connection type
system_profiler SPDisplaysDataType

# Compact one-liner: display name + resolution + color profile
system_profiler SPDisplaysDataType | grep -E "Resolution:|Color Profile:|Framebuffer Depth:|Display Type:"
```

**Expected output snippet from `SPThunderboltDataType`:**
```
Thunderbolt Bus:
  Vendor Name: Apple Inc.
  Device Name: Mac mini
  UID: 0x...
  Port: 1
  Speed: Up to 40 Gb/s     ← TB4 confirmed
  ...
  Device Name: CalDigit TS4
    Port: 1
    Speed: Up to 40 Gb/s
    ...
```

If a device shows "Up to 480 Mb/s" or "Up to 5 Gb/s", it has negotiated USB 2.0/3.0 — your cable or device is the bottleneck.

### Identify your display pipeline limit from software

```bash
# Shows how many displays are connected and what the GPU is using
system_profiler SPDisplaysDataType | grep -E "^    [A-Z]|Resolution|Connection Type"

# Check the chip model to infer pipeline limit
sysctl -n machdep.cpu.brand_string
# or
system_profiler SPHardwareDataType | grep "Chip:"
```

Cross-reference your chip against the table in the Concepts section to know your hard ceiling.

### Check what cable you actually have

If a device is underperforming, check the negotiated speed:

```bash
# List USB device tree with speeds
system_profiler SPUSBDataType | grep -A5 "Speed:"

# For Thunderbolt, check device speed tier:
system_profiler SPThunderboltDataType | grep "Speed:"
```

A Thunderbolt 4 cable should show "Up to 40 Gb/s". A cable advertised as "USB-C" but not TB-certified will frequently negotiate at "Up to 10 Gb/s" or lower.

### Configure an external display resolution

1. **System Settings → Displays** — select the external display tile.
2. **Resolution:** Click "Show all resolutions" to see every supported mode including non-HiDPI options.
3. **Refresh Rate:** Set to maximum supported (60Hz/120Hz/144Hz depending on display and connection).
4. **Color Profile:** Choose "sRGB" for neutral reference or your display's calibration profile.
5. **Night Shift / True Tone:** Disable both for color-accurate work.

To check the render resolution macOS is actually using (the backing store resolution, not just logical):
```bash
# displayplacer shows physical vs logical resolution
brew install jakehilborn/jakehilborn/displayplacer
displayplacer list
```

Output includes `resolution:3840x2160 hz:60 color_depth:8 scaling:on origin:(0,0) degree:0` — `scaling:on` means HiDPI 2× mode is active.

### MonitorControl setup

```bash
brew install --cask monitorcontrol
# Grant Accessibility permission when prompted
# Menu bar icon appears — scroll or click to adjust brightness/volume on DDC-capable monitors
```

If DDC does not work on your monitor (some displays block DDC over HDMI), MonitorControl falls back to software brightness (dims the framebuffer). This is visually identical but reduces color depth at low values — prefer the hardware path when available.

---

## 🧪 Labs

### Lab 1 — Audit every port's real capability

> ⚠️ **Read-only audit, non-destructive.** No backup needed.

1. Run `system_profiler SPThunderboltDataType > /tmp/tb-audit.txt 2>&1` and `system_profiler SPUSBDataType >> /tmp/tb-audit.txt`.
2. Open the file: `open /tmp/tb-audit.txt`.
3. For each port/device, note the "Speed:" field. Record in a table: Port (left/right, position), Protocol, Negotiated Speed, Device attached.
4. Identify which is your DFU port: typically the left-rear port on MacBook Pro. Attempt to boot from a USB stick in each port and confirm only the non-DFU ports succeed.
5. Run `system_profiler SPDisplaysDataType | grep "Connection Type:"` and confirm your display is connecting as Thunderbolt/DisplayPort, not HDMI (or if HDMI, that it's the dedicated port, not an adapter).

**Verification:** You should have a complete port map. Any port showing "Up to 480 Mb/s" on a device you expected to be fast is your first troubleshooting clue.

---

### Lab 2 — Determine and test your display pipeline limit

> ⚠️ **Non-destructive.** You need at least one external display. A second display (or a second cable/adapter) is needed to test the limit.

1. Run: `system_profiler SPHardwareDataType | grep "Chip:"` — note your chip.
2. Look up your display pipeline limit from the table above.
3. Connect one external display and verify it appears in System Settings → Displays.
4. If your Mac's limit is 2+, connect a second display. If limit is 1, attempt to connect a second display anyway and observe the behavior: macOS will typically show a "Cannot connect display" notification or simply ignore the second connection.
5. Run `system_profiler SPDisplaysDataType` before and after connecting the second display. Note whether the second display enumerates.

**Expected behavior on an M2 MacBook Air (1-display limit):**
- First display: enumerated, functional.
- Second display (via hub/direct): not enumerated in `SPDisplaysDataType`, or shows as "mirror only".

**Expected behavior on an M4 MacBook Air (2-display limit, lid open):**
- Both external displays enumerate.
- Built-in display remains active simultaneously.

---

### Lab 3 — Force HiDPI on a 1080p external display using BetterDisplay

> ⚠️ **Requires installing BetterDisplay and granting Screen Recording permission.** To roll back: delete the app and revoke Screen Recording in System Settings → Privacy → Screen Recording. No data is modified.

1. `brew install --cask betterdisplay` (paid license optional; free features include this lab).
2. Launch BetterDisplay. In the BetterDisplay menu bar, select your external 1080p display → "Create Virtual Screen".
3. Set the virtual screen resolution to 3840×2160 (4K), connected to your 1080p display.
4. macOS now renders at 4K backing store and downsamples to 1080p — each logical pixel is effectively 4 physical pixels. Text will visibly sharpen.
5. Compare: `displayplacer list` — note `scaling:on` for the virtual screen entry.
6. Take a screenshot (Cmd-Shift-4, drag a region) of text on the 1080p display before and after. The screenshot file will be 2× the region dimensions in HiDPI mode.

---

### Lab 4 — Cable identification and speed negotiation test

> ⚠️ **Non-destructive. Safe.** Requires at least two USB-C cables.

1. Connect an external SSD or fast USB device to your Mac using cable A.
2. Run: `dd if=/dev/zero of=/Volumes/<device>/speedtest bs=1m count=1000 2>&1 | tail -1` — note MB/s.
3. Check: `system_profiler SPUSBDataType | grep -A2 "Speed:"` — note negotiated speed.
4. Swap to cable B and repeat.
5. Compare results. A genuine TB4/USB4 cable should deliver 400–3000 MB/s to an NVMe enclosure; a USB 3.2 Gen 1 cable caps at ~400 MB/s; a USB 2.0 cable caps at ~40 MB/s.

> ⚠️ **Cleanup:** Delete the `speedtest` file: `rm /Volumes/<device>/speedtest`.

---

### Lab 5 — Diagnose "second monitor won't work"

This is the most common support request from Apple Silicon switchers. Work through it systematically:

```
Step 1: Identify chip and pipeline limit
    system_profiler SPHardwareDataType | grep "Chip:"
    → Look up limit in this lesson's table

Step 2: Check how many displays are already active
    system_profiler SPDisplaysDataType | grep -c "Resolution:"
    → Count includes built-in display

Step 3: Is the limit already reached?
    YES → you need DisplayLink or a Mac with more pipelines
    NO → continue

Step 4: Is the connection negotiating correctly?
    system_profiler SPThunderboltDataType
    → Is the dock/cable showing 40 Gbps or 10 Gbps?
    LOW SPEED → replace cable or dock

Step 5: Is the display itself being seen by macOS?
    system_profiler SPDisplaysDataType | grep "Display Type:"
    → If missing entirely, try: disconnect/reconnect, different port, different cable
    → If present but black: check display power, input source selection

Step 6: DisplayLink option
    → Install Synaptics DisplayLink driver
    → Connect USB DisplayLink dock
    → Verify System Settings → Privacy → Screen Recording shows DisplayLink approved
    → Restart DisplayLinkUserAgent: killall DisplayLinkUserAgent
```

---

## Pitfalls & gotchas

**1. Dock does not add display pipelines.** The single most common misconception. A Thunderbolt dock with 4 display outputs is not a KVM switch — it distributes your Mac's fixed pipeline count across multiple physical outputs, and ignores the surplus. See Lab 2.

**2. M3 lid-open second display gotcha.** The M3 base chip technically supports 2 external displays but only when the built-in display is disabled (lid closed). Opening the lid reclaims one pipeline for the built-in, dropping you back to 1 external. The M4 base chip removed this restriction.

**3. Thunderbolt vs. USB4 dock compatibility.** A dock labeled "USB4" (not "Thunderbolt 4") may not support all TB features — specifically PCIe tunnel is optional in USB4 but mandatory in TB4. NVMe enclosures or video capture cards attached to a USB4-but-not-TB4 dock may not enumerate.

**4. "Charge-only" cables.** Apple ships charge cables with some accessories that are USB 2.0 data speed (480 Mbps). These will charge your Mac but cannot pass display or high-speed data. Label your cables or check with `system_profiler` before debugging "why is my fast drive slow."

**5. eGPU on Apple Silicon: it does not work.** macOS on Apple Silicon has never shipped eGPU support. If you plug a Thunderbolt eGPU enclosure into an M-series Mac, macOS ignores it completely. This is an architectural decision, not a driver gap. For extra GPU compute, you need a Mac Pro/Mac Studio or a machine with a discrete GPU.

**6. DisplayLink and DRM.** Protected content (Netflix 1080p, Apple TV+, Amazon Prime Video in 1080p) will not play to any DisplayLink-driven display. The DRM stack requires a hardware-trusted display path. Use native TB/HDMI output for content playback.

**7. HDMI adapter bandwidth loss.** A USB-C-to-HDMI adapter on a TB4 port routes through the DP tunnel, converts to HDMI, and loses TB-specific features. If you need HDMI 2.1 performance (4K@120Hz), use the MacBook Pro's native HDMI port, not an adapter from a TB port — TB4 DP tunnel is limited to DP 1.4 which caps at 4K@120Hz with DSC compression; the native HDMI 2.1 output bypasses this.

**8. Non-integer scaling blur.** If text looks slightly soft on an external display, you are likely using a non-integer HiDPI scale. The fix: use BetterDisplay to create a virtual 2× resolution display or switch to a resolution that results in an exact 2:1 mapping.

---

## Key takeaways

- USB-C is a shape, not a speed. Always verify negotiated protocol via `system_profiler SPThunderboltDataType` or `SPUSBDataType`.
- The display pipeline ceiling is in silicon, not cables or ports. Match your Mac tier to your monitor count requirement before buying.
- Thunderbolt docks extend bandwidth and ports but do not add display pipelines. DisplayLink adds displays via CPU compression with tradeoffs (CPU overhead, no DRM, limited HDR).
- Thunderbolt 5 (80/120 Gbps) enables 8K and 4K@240Hz over a single cable; only M4 Pro/Max and later ship TB5.
- The MacBook Pro headphone jack drives high-impedance headphones up to 1000Ω natively — a meaningful differentiator.
- MagSafe charges faster but USB-C PD works on any TB/USB4 port; under-wattage charges slowly but safely.
- Cable quality directly determines negotiated speed; always test with `dd` when throughput is disappointing.
- `system_profiler SPDisplaysDataType`, `SPThunderboltDataType`, and `SPUSBDataType` are your forensic ground truth for the entire physical connectivity stack.

---

## Terms introduced

| Term | Definition |
|---|---|
| USB-C | The oval connector form factor; distinct from protocol |
| USB4 | Protocol specification unifying USB3 and Thunderbolt; 20–80 Gbps |
| Thunderbolt 4 | Intel-certified USB4 superset; mandates PCIe tunnel, 40 Gbps |
| Thunderbolt 5 | 80 Gbps base, 120 Gbps Boost mode; DP 2.1 UHBR20; on M4 Pro/Max+ |
| PCIe tunnel | Thunderbolt protocol that exposes PCIe lanes to external devices |
| Display pipeline | A hardware-dedicated path from SoC to external display output; count is fixed per chip |
| DFU port | Device Firmware Update port on Apple Silicon; identical appearance, restricted capabilities (no external boot) |
| DisplayLink | Software display technology using USB to bypass hardware pipeline limits; requires driver and CPU |
| HiDPI | macOS rendering at 2× logical resolution for sharp pixel doubling on Retina-equivalent displays |
| DDC/CI | Display Data Channel Command Interface — serial protocol to control monitor brightness/volume via video cable |
| MagSafe | Magnetic proprietary connector for charging; data/video-free; power only |
| USB PD | USB Power Delivery — negotiated charging wattage standard over USB-C |
| ProMotion | Apple's adaptive sync display technology (24–120Hz) on MacBook Pro built-in display |
| UHS-II | SD card bus standard, up to 312 MB/s; used in native Mac SDXC slots |

---

## Further reading

- Apple Support: [How many displays can connect to MacBook Pro](https://support.apple.com/en-us/101571) — official display count table by model
- Howard Oakley, The Eclectic Light Company: [Apple Silicon Macs have 2 types of Thunderbolt ports](https://eclecticlight.co/2026/02/06/apple-silicon-macs-have-2-types-of-thunderbolt-ports/) — the DFU port distinction
- Plugable Knowledge Base: [Understanding External Display Support on Apple M1–M5 Chips](https://kb.plugable.com/docking-stations-and-video/understanding-external-display-support-on-apple-m1-m2-m3-and-m4-chips) — per-chip display matrix with refresh rates
- Jake Hilborn: [`displayplacer`](https://github.com/jakehilborn/displayplacer) — CLI for display arrangement, resolution, and HiDPI management
- waydabber: [`BetterDisplay`](https://github.com/waydabber/BetterDisplay) — HiDPI unlock, virtual screens, DDC control
- [MonitorControl](https://github.com/MonitorControl/MonitorControl) — open-source DDC brightness/volume for external monitors
- Apple Platform Security Guide — covers the DFU/recoveryOS security model behind port restrictions
- Intel Thunderbolt 5 specification overview — PCIe ×8 tunnel details, Boost mode asymmetric bandwidth
- [`m1displays.com`](https://m1displays.com/) — community-maintained guide to multi-monitor configs on Apple Silicon
