---
title: Battery, thermal & power management
part: P10 Hardware
est_time: 50 min read + 40 min labs
prerequisites: [01-apple-silicon-architecture]
tags: [macos, battery, power, pmset, thermal, caffeinate, powermetrics, smс]
---

# Battery, thermal & power management

> **In one sentence:** macOS exposes a deep, script-friendly power stack — `pmset`, `powermetrics`, `caffeinate`, and the unified SoC architecture — that lets you observe, control, and extend every aspect of battery life, thermal behavior, and sleep policy with precision no Windows power plan ever offered.

---

## Why this matters

Battery health and thermal management are not "settings menu" topics. They determine whether your MacBook is still running at 90% capacity in three years or limping along at 60%, and they govern whether a long compile or forensic image job finishes on battery versus throttles into oblivion at 50°C ambient. For a forensics professional capturing disk images in the field, or a developer running parallel builds, the difference between knowing and not knowing this stack is real downtime.

Apple Silicon changed the underlying architecture significantly — the SMC as Intel knew it is gone, thermal management lives in the SoC, and the sleep/wake story is fundamentally different. This lesson covers what actually happens on M-series hardware, where the old Intel idioms still work, and where they do not.

---

## Concepts

### 1. The battery health model

MacBook batteries are lithium-ion polymer cells. Apple rates them for **~1000 charge cycles** before they are designed to retain at least 80% of original capacity. One cycle = 100% of total capacity discharged, not necessarily in a single session — draining from 100% to 50% twice counts as one cycle.

Three values matter for battery health assessment:

| Field | What it means |
|---|---|
| **Maximum Capacity %** | Current full-charge energy as % of design capacity. New = 100%. Apple flags "Service Recommended" around 80%. |
| **Cycle Count** | Cumulative discharge cycles. Meaningful relative to the ~1000-cycle rating. |
| **Condition** | Apple's categorical assessment: `Normal`, `Replace Soon`, `Replace Now`, `Service Battery`. |

These are surfaced in three places:
- **System Information.app** → Power (the human-readable path)
- `system_profiler SPPowerDataType` (scriptable, great for fleet checks or periodic logging)
- `About This Mac → More Info → Battery` (in Sequoia/Tahoe, this goes directly to the Battery system settings pane, which shows a compact health summary)

```bash
# Full battery data dump
system_profiler SPPowerDataType

# Just the health fields — useful in scripts
system_profiler SPPowerDataType | grep -E "Cycle Count|Maximum Capacity|Condition"
```

Expected output on a healthy machine:
```
          Cycle Count: 342
          Maximum Capacity: 94%
          Condition: Normal
```

> 🔬 **Forensics note:** `system_profiler SPPowerDataType` in a remote/MDM context or from a forensic image gives you battery history context for chain-of-custody timelines. A machine with 1,200 cycles and "Service Battery" condition has seen heavy use — relevant for establishing usage history. The raw data lives in IORegistry: `ioreg -rn AppleSmartBattery` gives even more granular fields including raw cycle count, design capacity in mAh, and instantaneous amperage.

### 2. Optimized Battery Charging and charge limiting

**Optimized Battery Charging** (System Settings → Battery → Battery Health → Optimized Battery Charging) uses on-device machine learning to learn your charging patterns. When it predicts you will be plugged in for an extended period (overnight at a desk), it charges to 80%, pauses, then charges to 100% in time for your typical unplug time. The goal: minimize time spent at high state of charge (SoC), which accelerates lithium-ion degradation.

macOS 14+ also added an explicit **80% Charge Limit** option (toggle in the same Battery Health panel). When enabled, charging simply stops at 80% and never tops up — no learning, no schedule. This is the right choice for machines that live on AC power most of the time (lab workstations, always-docked MacBook Pros).

**Should you leave it plugged in?** The old Windows laptop answer ("never leave it plugged in, it'll overcharge and die") does not apply to modern MacBooks. Apple's power circuitry bypasses the battery and runs directly from the adapter when the battery is full — the battery is not being charged while showing 100%. *But* holding a battery at 100% SoC long-term does cause measurable capacity loss over years. The practical guidance:

- Portable/field use: let macOS Optimized Charging handle it.
- Always-docked lab machine: enable the 80% limit in System Settings or use **AlDente**.

**AlDente** (AppHouseKitchen, free tier + Pro paid) is the go-to third-party charge limiter. It sets the charge ceiling anywhere from 20–100% via a private IOKit API that writes to the battery management IC. The free version covers the basic charge cap; Pro adds heat-protection (pauses charging when battery temp is elevated), Sailing Mode (80%→75% discharge cycle to avoid floating at the ceiling), and Calibration Mode. It persists across reboots via a launchd agent.

```bash
# Verify AlDente is installed and its launchd agent is loaded
launchctl list | grep -i aldente
```

> 🪟 **Windows contrast:** Windows laptops increasingly ship manufacturer charge-limiting utilities (Lenovo Vantage, Dell Power Manager, ASUS Battery Care), but they are OEM-specific, inconsistent, and often require running bloatware. Apple's Optimized Charging is OS-level and works identically across all MacBook hardware. AlDente is the equivalent of a clean third-party equivalent to Lenovo's BIOS-level 60%/80% cap.

**Calibration myths:** You do not need to calibrate modern lithium-ion batteries. The "drain to 0%, charge to 100%, repeat monthly" ritual was for NiCd and NiMH cells. For Li-ion, full discharge cycles are a *cost*, not a benefit. Ignore any advice suggesting calibration is necessary.

---

### 3. Power management: `pmset` is the king

`pmset` is the command-line interface to the `powerd` daemon, which is the user-space power management process on macOS. It reads/writes power policy via IOKit and coordinates with the kernel's `IOPMrootDomain`.

#### Reading the current power policy

```bash
# Read all current settings
pmset -g

# Read with active power source context
pmset -g custom

# Read what the current power source is
pmset -g batt

# List power management capabilities for this machine
pmset -g cap
```

Sample `pmset -g` output on a MacBook Pro (Apple Silicon, Tahoe):

```
System-wide power settings:
Currently in use:
 standby              1
 Sleep On Power Button 1
 hibernatemode        3
 powernap             1
 networkoversleep     0
 disksleep            10
 sleep                1
 autopoweroffdelay    28800
 hibernatefile        /var/vm/sleepimage
 autopoweroff         1
 ttyskeepawake        1
 displaysleep         10
 tcpkeepalive         1
 standbydelay         10800
 standbydelayhigh     86400
 standbydelaylow      10800
 highstandbythreshold 50
```

#### Key settings decoded

| Setting | What it does | Typical default |
|---|---|---|
| `sleep` | Minutes of inactivity before system sleep (0 = never) | 1 (macOS chooses adaptively) |
| `displaysleep` | Minutes before display sleeps | 10 |
| `disksleep` | Minutes before hard disks spin down (irrelevant on pure SSD configs) | 10 |
| `hibernatemode` | Sleep image behavior (see below) | 3 (portables) |
| `standby` | Enable transition from sleep → standby (deeper low-power state) | 1 |
| `standbydelay` / `standbydelaylow` | Seconds from sleep onset before standby kicks in (low-battery path) | 10800 (3 hrs) |
| `standbydelayhigh` | Seconds before standby when battery > `highstandbythreshold` | 86400 (24 hrs) |
| `highstandbythreshold` | Battery % threshold that selects high vs. low standby delay | 50 |
| `autopoweroff` | Enable auto-power-off from standby (replaces "safe sleep" on AS) | 1 |
| `autopoweroffdelay` | Seconds in standby before system powers off completely (memory image preserved) | 28800 (8 hrs) |
| `powernap` | Allow background activity (Mail fetch, backups, iCloud sync) during sleep | 1 |
| `tcpkeepalive` | Maintain TCP connections during Power Nap | 1 |
| `ttyskeepawake` | Prevent sleep when active terminal (tty/pty) sessions exist | 1 |

#### Hibernation modes

`hibernatemode` controls what happens to RAM contents when the system sleeps:

- **`0`** — RAM stays powered, no disk image written. Desktop Macs default. Fastest wake, zero disk wear, but data lost on power loss.
- **`3`** — Hybrid sleep (portable default). RAM stays powered *and* a hibernation image is written to `/var/vm/sleepimage`. Wake from RAM (fast) unless power was lost, in which case it restores from disk. Best of both.
- **`25`** — Full hibernation. RAM image written, RAM powered off. Slowest wake, but zero standby power draw. Not the default on AS Macs because the SoC idle power is already extremely low.

```bash
# View size of current sleep image (should match physical RAM)
ls -lh /var/vm/sleepimage

# On a 32 GB machine, expect ~32 GB file
```

> ⚠️ **ADVANCED:** Changing `hibernatemode` requires `sudo pmset`. If you set `hibernatemode 25` on a MacBook, wake time increases noticeably. To revert: `sudo pmset -a hibernatemode 3`. The sleepimage can be deleted manually only when the system is awake and only takes effect after the next sleep cycle.

#### Scoping changes

```bash
# Change only on battery power
sudo pmset -b standbydelay 3600

# Change only on AC
sudo pmset -c displaysleep 30

# Change globally (both sources)
sudo pmset -a sleep 0
```

#### Scheduling wake and sleep

```bash
# Wake at 7:00 AM every weekday, sleep at midnight daily
sudo pmset repeat wake MTWRF 07:00:00
sudo pmset repeat sleep MTWRFSU 00:00:00

# Check scheduled events
pmset -g sched

# Cancel all scheduled events
sudo pmset repeat cancel
```

This is useful for field forensic setups: schedule a Mac to wake for a timed acquisition, then sleep when done.

#### What is keeping the Mac awake? — power assertions

`powerd` implements a lock mechanism called **power assertions**. Any process can hold an assertion that prevents sleep, display sleep, or disk sleep. This is the mechanism behind Spotlight finishing an index, a video call holding the display on, or a misbehaving app blocking sleep indefinitely.

```bash
# Show all currently held power assertions
pmset -g assertions
```

Sample output showing a runaway process:

```
Assertion status system-wide:
   BackgroundTask                 1
   ApplePushServiceTask           0
   UserIsActive                   1
   PreventUserIdleDisplaySleep    0
   PreventUserIdleSystemSleep     1
   ExternalMedia                  0
   PreventSystemSleep             0
   DeclareSystemActivity          1

Listed by owning process:
 pid 1842(com.company.badapp): [0x000123ab56cd0001] 00:47:20 PreventUserIdleSystemSleep named: "MyApp is busy"
 pid 322(coreaudiod): [0x000098fe12340002] 02:11:05 PreventUserIdleSystemSleep named: "com.apple.audio.context"
```

The first field after the PID is the assertion type, the hex is the assertion token, the time is how long it has been held, and the name is self-reported by the process. This is your primary diagnostic when the Mac refuses to sleep.

```bash
# Watch assertions in real time (refreshes every 2 seconds)
watch -n 2 "pmset -g assertions | grep -A 20 'Listed by'"

# Correlate assertion-holding PIDs with process names
pmset -g assertions | grep -E "^[ ]+pid" | awk '{print $2}' | tr -d '(' | xargs -I{} ps -p {} -o pid,comm= 2>/dev/null
```

> 🔬 **Forensics note:** Power assertions leave artifacts in the unified log. `log show --predicate 'subsystem == "com.apple.powerd"' --last 24h` surfaces every assertion create/release, which can establish a timeline of when processes were actively running vs. system idle — useful in incident response to corroborate other activity timestamps.

---

### 4. `caffeinate` — keeping a task alive

`caffeinate` is a thin wrapper that creates power assertions for the duration of a command or until killed. It is the right tool for any long-running field task.

```bash
# Prevent idle sleep while a command runs; exits when command exits
caffeinate -i long_running_command.sh

# -i  prevent idle sleep
# -d  prevent display sleep  
# -s  prevent system sleep (requires AC power to be effective)
# -m  prevent disk idle
# -u  declare user is active (re-arms user-idle timer)
# -t  hold assertion for N seconds then exit
# -w  hold until process with given PID exits

# Prevent sleep for exactly 4 hours (forensic acquisition window)
caffeinate -i -t 14400 &

# Prevent sleep while a specific PID is running (e.g., a disk imager)
caffeinate -w 4921 &

# Keep display on + prevent sleep during remote session
caffeinate -dis &
CAFF_PID=$!
# ... do work ...
kill $CAFF_PID
```

`caffeinate` shows up in `pmset -g assertions` under its PID. When you `kill` it or the wrapped command exits, the assertion is released immediately.

> 🪟 **Windows contrast:** Windows has `SetThreadExecutionState()` / `powercfg /requests` for the same concept, but no built-in CLI equivalent to `caffeinate`. The closest is `powercfg /requests` to *read* what's blocking sleep, but there's no standard `caffeinate`-like wrapper. Scripts typically use `WScript.Shell` COM hacks or third-party tools like `caffeine.exe`.

---

### 5. Sleep states on Apple Silicon — the always-low-power model

Intel Macs had a meaningful distinction between sleep (S3), safe sleep, and hibernation, governed by `hibernatemode`. The architecture was: CPU → PCH → SMC, with discrete power rails that could be cut.

Apple Silicon Macs are fundamentally different. The M-series SoC integrates:
- CPU cores (P-cores + E-cores)
- GPU
- Neural Engine
- Memory controllers (LPDDR5 on-package)
- Media engines, ISP, Secure Enclave

**There is no discrete SMC chip on Apple Silicon.** The SMC's functions — power sequencing, thermal management, battery management, fan control — are handled by firmware running on the SoC's embedded microcontrollers (specifically, the always-on "AOP" coprocessor and the embedded T-class subsystem). This means:

- `pmset` flags like `sms` (sudden motion sensor) and `ring` are no longer relevant.
- `hibernatemode 3` still works and writes a sleepimage, but the standby power draw of an M-series Mac is so low (~0.1–0.3W in idle sleep vs. Intel's ~0.8–2W) that the urgency of standby/hibernate is reduced.
- Wake latency from sleep is extremely fast (sub-second) because the SoC never fully powers down in normal sleep — it's more analogous to a smartphone's suspend state than classic PC S3 sleep.
- **Power Nap** (`powernap 1`) allows the E-cores to service background tasks (iCloud, push notifications, Time Machine, Spotlight) during sleep without waking the full SoC.

The practical meaning: on Apple Silicon, the default `hibernatemode 3` + `standby 1` configuration works well for nearly all use cases. You don't need to tune aggressively.

---

### 6. Thermal management — fanless throttle vs. active cooling

Apple Silicon chips use a heterogeneous compute model with P-cores (high performance, high power) and E-cores (low power, always-on capable). macOS's scheduler (`QoS`-aware) assigns work to the appropriate core cluster:

- Background tasks, mail, indexing → E-cores
- Interactive work, UI rendering → P-cores + GPU
- Compute-intensive bursts → all P-cores at full frequency

**Thermal throttling** occurs when die temperature exceeds safe limits. The SoC reduces P-core frequency stepwise. On an M4 Pro under sustained thermal stress, P-core frequency can drop from ~4.4 GHz (boost) to 3.6 GHz (sustained) to 2.6 GHz (throttled). E-cores are less affected. This is not a catastrophic failure — it is the SoC protecting itself.

**Fanless Macs** (MacBook Air, Mac mini entry configurations) throttle more aggressively under sustained loads because they have no active cooling path. A 30-second compile burst is fine; a 60-minute parallel build will see sustained throttle. This is by design. If you regularly run sustained multi-core loads, the MacBook Pro (active fan) or Mac Studio/Pro (large heatsink + fan) is the correct hardware.

**Ambient heat matters more than you think.** The SoC measures die temperature, not ambient, but a hot room (35°C ambient) significantly reduces the thermal headroom before throttle onset. Field forensics in a hot car is a real concern — a MacBook Air can throttle within minutes when ambient is above 30°C.

#### Measuring thermals with `powermetrics`

`powermetrics` is the authoritative macOS tool for per-core CPU/GPU frequency, power draw, and thermal state. It requires root.

```bash
# Sample all relevant data every 5000ms, 5 samples
sudo powermetrics --samplers cpu_power,gpu_power,thermal -n 5 -i 5000

# Continuous thermal pressure monitoring (lightweight)
sudo powermetrics --samplers thermal -i 2000

# Watch for throttling events specifically
sudo powermetrics --samplers cpu_power -i 1000 | grep -i "thermal\|throttl\|pressure"
```

**Important Apple Silicon caveat:** The `smc` sampler (`--samplers smc`) that exposed raw die temperatures on Intel Macs is **not supported on Apple Silicon**. The command will either error or produce no data. Temperature information on AS comes through the `thermal` sampler's pressure-level output and through third-party tools that query private IOKit keys.

`powermetrics` thermal output uses **pressure levels**:
- `nominal` — no throttling
- `moderate` — light throttle, may be unnoticeable  
- `heavy` — significant frequency reduction, perceptible on compute tasks
- `tripping` — emergency thermal protection engaged

```bash
# Filter to just thermal pressure level changes
sudo powermetrics --samplers thermal -i 1000 2>/dev/null | grep -i "pressure"
```

For raw temperature values on Apple Silicon, third-party tools query private `SMCReadKey` IOKit calls:
- **`iStatMenus`** (commercial, best UI) — shows per-cluster temps, fan RPM, power watts
- **`TG Pro`** — thermal monitoring + fan control override
- **`sudo powermetrics --samplers smc`** on Intel Macs only

```bash
# Intel Macs only: CPU die temp via powermetrics smc sampler
sudo powermetrics --samplers smc -n 1 | grep -i "temperature"
```

#### `pmset -g thermlog`

For passive thermal event logging (what macOS logged historically, not live):

```bash
# Show thermal event log (may be sparse on AS, more useful on Intel)
pmset -g thermlog
```

---

### 7. Identifying battery drain and runaway processes

The **Energy tab in Activity Monitor** (`/Applications/Utilities/Activity Monitor.app` → Energy) is the GUI entrypoint. It shows:

- **Energy Impact** (composite score: CPU %, GPU %, I/O wake-ups per second weighted)
- **12 hr Power** (cumulative energy impact over 12 hours — catches daemons that spike briefly but frequently)
- **App Nap** status
- Whether an app **prevents sleep** (assertion column)

The "Apps Using Significant Energy" notification in the menu bar battery indicator fires when a process holds a high Energy Impact score for a sustained period.

CLI equivalent for scripting:

```bash
# Top 10 processes by energy impact (one snapshot)
sudo powermetrics --samplers tasks -n 1 -i 2000 | head -60

# CPU % sorted, useful for quick runaway identification
ps aux --sort=-%cpu | head -20

# Disk I/O wake-ups (waking the disk or SoC) via ioreg
ioreg -n IOPMrootDomain -r | grep -E "Wake|Sleep"
```

Cross-reference with the Instruments **Energy Log** instrument for deep per-subsystem power profiling — useful when profiling your own code or diagnosing a specific app.

---

### 8. `nvram` power-related boot arguments

While the SMC is gone on Apple Silicon, `nvram` still carries power-relevant flags through the boot chain:

```bash
# View all nvram variables
nvram -p

# View specifically power-related entries
nvram -p | grep -E "boot-args|sleep|hibernate"
```

The `boot-args` nvram variable can include debug flags for power management (`io=0x10d` for IOKit power management logging), though these are primarily for kernel/driver development. Forensically, `nvram -p` can reveal whether someone set unusual boot arguments — worth capturing in imaging.

> ⚠️ **ADVANCED / DESTRUCTIVE:** `nvram boot-args="..."` on Apple Silicon requires disabling SIP in recoveryOS first (Apple Silicon requires explicit user presence at boot to change security policy). Do not casually set boot-args on a production machine.

---

## Hands-on (CLI & GUI)

### Read battery health quickly

```bash
# One-liner for health fields
system_profiler SPPowerDataType | grep -E "Cycle Count|Maximum Capacity|Condition|Full Charge Capacity|Design Capacity"
```

### Read IORegistry for raw battery data (more fields than system_profiler)

```bash
ioreg -rn AppleSmartBattery | grep -E '"Cycle|"Max|"Design|"Current|"Temperature|"Voltage|"Amperage'
```

`Temperature` here is in units of 0.01°C (divide by 100). `Amperage` is in mA (negative = discharging, positive = charging). `Voltage` is in mV.

### Find what is preventing sleep right now

```bash
pmset -g assertions
# Look for "PreventUserIdleSystemSleep" held by a non-obvious PID
```

### Set charge limit via pmset (no third-party tool needed — basic)

Apple's native 80% limit in System Settings → Battery → Battery Health → Optimized Battery Charging is the GUI path. There is no direct `pmset` flag for the charge ceiling on modern macOS; that capability is in the Battery Health UI and (via private API) in tools like AlDente.

### Schedule a wake for a timed operation

```bash
# Wake in 3 hours from now, run a backup, then sleep again
sudo pmset schedule wake "$(date -v +3H '+%m/%d/%Y %H:%M:%S')"
pmset -g sched   # verify
```

---

## Labs

### Lab 1: Battery health audit

**Goal:** Extract complete battery health data programmatically and interpret it.

```bash
echo "=== Battery Health Report ===" 
echo "Date: $(date)"
echo ""
system_profiler SPPowerDataType | grep -E "Cycle Count|Maximum Capacity|Condition|Full Charge Capacity|Design Capacity|Manufacturer|Serial Number"
echo ""
echo "=== IORegistry Raw Values ==="
ioreg -rn AppleSmartBattery | grep -E '"CycleCount|"MaxCapacity|"DesignCapacity|"Temperature|"Voltage|"Amperage|"IsCharging|"ExternalConnected' | sed 's/.*= //'
```

Questions to answer:
1. What is your current maximum capacity %?
2. How many cycles have you accumulated vs. the ~1000 design rating?
3. What is the battery temperature in °C right now? (divide raw value by 100)
4. Is the Amperage negative (discharging) or positive (charging)?

---

### Lab 2: Assertion hunting — find the sleep blocker

**Goal:** Identify every active power assertion and its owner.

```bash
# Step 1: See raw assertions
pmset -g assertions

# Step 2: Extract PIDs holding sleep-relevant assertions
pmset -g assertions | grep -E "PreventUserIdle|PreventSystem|DeclareSystem" | grep "pid"

# Step 3: Resolve PIDs to process names and commands
pmset -g assertions | grep -oE "pid [0-9]+" | awk '{print $2}' | sort -u | \
  xargs -I{} sh -c 'echo "PID {}: $(ps -p {} -o comm= 2>/dev/null)"'

# Step 4: For each suspicious PID, check what it's doing
# Replace 1234 with actual PID from above
ps -p 1234 -o pid,ppid,user,comm,args
```

Try generating an assertion yourself and finding it:
```bash
# Start caffeinate in background
caffeinate -i -t 120 &
CAFF_PID=$!

# Now find it in assertions
pmset -g assertions | grep $CAFF_PID

# Release it
kill $CAFF_PID
pmset -g assertions | grep $CAFF_PID  # should be gone
```

---

### Lab 3: `caffeinate` wrapping a long task

> ⚠️ **Note:** This lab prevents sleep — ensure you run it when you actually want the Mac to stay awake. The `sleep 30` below is a stand-in for a real long operation.

```bash
# Template: run a long task without the Mac sleeping
caffeinate -i bash -c '
  echo "Task started at $(date)"
  echo "Assertion held. Mac will not idle-sleep."
  sleep 30   # Replace with: sudo dd if=/dev/diskX of=image.dmg bs=1m
  echo "Task complete at $(date)"
'
# When the script exits, caffeinate releases the assertion automatically
```

Verify the assertion is active while it runs (in another terminal):
```bash
pmset -g assertions | grep caffeinate
```

---

### Lab 4: Thermal and power profiling with `powermetrics`

> ⚠️ **Note:** `powermetrics` requires `sudo`. On Apple Silicon, the `smc` sampler will produce no output — use `thermal` and `cpu_power` instead.

```bash
# 10-second thermal + CPU power snapshot
sudo powermetrics --samplers cpu_power,gpu_power,thermal -n 2 -i 5000 2>/dev/null | \
  grep -E "thermal pressure|P-Cluster|E-Cluster|GPU Power|Combined Power"
```

Now stress the CPU briefly (in another terminal) and watch the thermal pressure level change:
```bash
# Stress all P-cores for 15 seconds
python3 -c "
import multiprocessing, time
def burn(t): 
    end = time.time() + t
    while time.time() < end: pass
procs = [multiprocessing.Process(target=burn, args=(15,)) for _ in range(multiprocessing.cpu_count())]
[p.start() for p in procs]
[p.join() for p in procs]
print('Done')
"
```

Meanwhile, in the first terminal, check if thermal pressure elevated. Record:
- Baseline thermal pressure level
- Peak level during stress
- Time to return to nominal after stress ends

---

### Lab 5: Set and verify the 80% charge limit

**GUI path (native, no third-party):**
1. System Settings → Battery → Battery Health button → toggle "Optimized Battery Charging" on
2. OR enable the explicit limit: same pane → "Limit to 80%" (macOS 14.4+)

**With AlDente (third-party, more control):**
```bash
# Verify AlDente is installed
ls /Applications/AlDente.app 2>/dev/null && echo "Installed" || echo "Not installed"

# Check if launchd agent is loaded (AlDente persists via launchd)
launchctl list | grep -i aldente
```

Set the limit to 80% in the AlDente menu bar icon, then confirm the Mac stops charging when it reaches 80%:
```bash
# Watch the charging amperage in real time
while true; do
  ioreg -rn AppleSmartBattery | grep '"Amperage"'
  sleep 5
done
```

When AlDente's limit kicks in, Amperage should drop to 0 or go slightly negative (trickle discharge).

---

## Pitfalls & gotchas

1. **`pmset -a` vs. `-b`/`-c` scope confusion.** Using `-a` sets the same value for both battery and AC. If you want different policies (e.g., shorter sleep on battery, longer on AC), you must set each separately with `-b` and `-c`. Many guides omit this and people wonder why their laptop sleeps aggressively when plugged in.

2. **`sudo pmset` vs. energy saver UI.** The System Settings Energy/Battery pane and `pmset` write to the same underlying settings store, but GUI changes can overwrite `pmset` settings after the fact. If you set something via `pmset` and it keeps reverting, the GUI preference or an MDM policy is stomping it. Check `pmset -g custom` (shows what each power source uses independently).

3. **The `smc` sampler is Intel-only.** Scripts and tutorials written before 2021 that use `sudo powermetrics --samplers smc` to get CPU temperature will produce no useful output on Apple Silicon. The sampler name is recognized but returns nothing. Use `--samplers thermal` for pressure levels, or iStatMenus/TG Pro for actual temps.

4. **`sleepimage` size.** On a 96 GB unified memory Mac, `/var/vm/sleepimage` is 96 GB. Ensure you have sufficient free space before changing `hibernatemode` — a failed sleepimage write will cause wake failures. macOS will warn but the error is not always obvious.

5. **`caffeinate` and system sleep vs. user-idle sleep.** `-i` prevents **user-idle** sleep — the Mac going to sleep because of inactivity. `-s` prevents **system sleep** but only works on AC power. On battery, `-s` is silently ignored (the OS won't let a script override power conservation while unplugged). If your caffeinate-wrapped job stops because the Mac slept on battery, that is why.

6. **Power Nap and `tcpkeepalive` in secure environments.** In an air-gapped or forensics lab environment, `powernap 0` and `tcpkeepalive 0` prevent the Mac from reaching out during sleep. Useful for evidence preservation: `sudo pmset -a powernap 0 tcpkeepalive 0`.

7. **`pmset repeat` scheduling does not survive major macOS upgrades well.** After upgrading, verify your scheduled events still exist with `pmset -g sched`. Automation via launchd (`WakeOrPowerOn` key in a launchd plist) is more reliable for production use.

8. **AlDente and official Optimized Battery Charging conflict.** If you run both, they can fight over the charge ceiling. Apple's native limit writes through the battery management IC. AlDente also writes through the same IC. The last writer wins. Pick one approach and stick to it — in practice, AlDente's limit takes precedence when active, and you should disable Apple's native limit if you use AlDente.

9. **Ambient heat in field forensics.** The thermal protection system on Apple Silicon is aggressive: a MacBook Air left in a parked car on a warm day (>35°C ambient) can throttle to a fraction of its normal performance within minutes. For time-sensitive field acquisitions, keep the device cool. An ice pack under the Mac (indirect — no condensation) can extend full-performance window substantially.

---

## Key takeaways

- **Battery health** is read accurately via `system_profiler SPPowerDataType` or `ioreg -rn AppleSmartBattery`. Cycle count relative to ~1000 cycles and Maximum Capacity % are the two numbers that matter.
- **Optimized Battery Charging** (native) and **AlDente** (third-party) are both legitimate approaches to charge limiting; choose one. For always-docked machines, an explicit 80% limit meaningfully extends long-term capacity.
- **`pmset`** is the single CLI for reading and writing all power policy. `-g` reads current settings; `sudo pmset -a/-b/-c` writes them. `-g assertions` is the sleep-blocker diagnostic.
- **`caffeinate`** is the right way to prevent sleep around a long job. Use `-i` for most cases; wrap a command for automatic release.
- **`powermetrics`** is the authoritative thermal/power profiler; use `--samplers cpu_power,thermal` on Apple Silicon (the `smc` sampler only works on Intel).
- **Apple Silicon eliminated the discrete SMC chip.** Power and thermal management now live in the SoC firmware. The behavioral result is extremely low sleep power draw and fast wake — less reason to tune aggressively than on Intel.
- **Power assertions** are the mechanism behind any process preventing sleep. `pmset -g assertions` always tells you who is holding the Mac awake and why.
- For forensics: power assertion logs (`log show --predicate 'subsystem == "com.apple.powerd"'`) and `ioreg -rn AppleSmartBattery` provide timeline and usage artifacts not available on Windows without third-party tools.

---

## Terms introduced

| Term | Definition |
|---|---|
| **Cycle count** | Cumulative full-discharge-equivalent cycles; ~1000 is Apple's design rating |
| **Maximum Capacity %** | Current full-charge energy as % of original design capacity |
| **Optimized Battery Charging** | ML-based charge scheduling to minimize time at 100% SoC |
| **`pmset`** | CLI to the `powerd` daemon; reads/writes all macOS power policy |
| **`powerd`** | User-space power management daemon coordinating IOKit's IOPMrootDomain |
| **Power assertion** | A kernel lock held by a process to prevent a specific sleep mode |
| **`caffeinate`** | CLI tool that creates power assertions for the lifetime of a command |
| **`hibernatemode`** | Controls whether/how RAM contents are written to disk during sleep |
| **sleepimage** | RAM snapshot written to `/var/vm/sleepimage` in hibernatemode 3 or 25 |
| **Power Nap** | macOS feature allowing background activity on E-cores during sleep |
| **`powermetrics`** | Root-required tool exposing per-core CPU/GPU frequency, power draw, and thermal pressure |
| **Thermal pressure level** | macOS categorical throttle state: `nominal → moderate → heavy → tripping` |
| **AOP coprocessor** | Always-On Processor in Apple Silicon SoC; handles sleep management and wake triggers |
| **AlDente** | Third-party macOS menu-bar tool implementing charge limiting via private IOKit API |
| **`system_profiler SPPowerDataType`** | CLI query for battery and power supply information |

---

## Further reading

- **Apple Platform Security Guide** (developer.apple.com/security) — covers the Secure Enclave and AOP coprocessor roles in power/security state management
- **Howard Oakley, The Eclectic Light Company** — [Power Modes and Apple Silicon CPUs](https://eclecticlight.co/2025/01/08/power-modes-and-apple-silicon-cpus/) and [Power Management in detail: using pmset](https://eclecticlight.co/2017/01/20/power-management-in-detail-using-pmset/) — the best third-party technical coverage of macOS power management
- `man pmset` — canonical reference for all flags; more accurate than most blog posts
- `man powermetrics` — sampler list with descriptions; essential if you want to extend the thermal profiling lab
- **Apple Support HT210557** — MacBook battery cycle count specifications per model
- **Apple Support 102888** — "Determine battery cycle count for Mac laptops"
- [[01-apple-silicon-architecture]] — SoC architecture context for understanding why SMC behavior changed
- [[03-storage-and-filesystems]] — sleepimage and `/var/vm/` filesystem context
- [[07-processes-and-launchd]] — launchd scheduling alternative to `pmset repeat` for production wake scheduling
