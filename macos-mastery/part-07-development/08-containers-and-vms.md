---
title: Containers & VMs on the Mac
part: P07 Development
est_time: 60 min read + 60 min labs
prerequisites: [01-boot-process, 06-security-privacy]
tags: [macos, virtualization, containers, docker, vm, apple-silicon, arm64, orbstack, colima, utm, parallels]
---

# Containers & VMs on the Mac

> **In one sentence:** Apple Silicon changed everything about running foreign workloads on a Mac — every tool in the ecosystem now has to explicitly confront the arm64/x86 split, and the fastest option depends on whether you want container isolation, full-VM fidelity, or Apple's new per-container-VM model.

## Why this matters

Running a Windows VM for malware triage, spinning up a fresh Linux environment to reproduce a server bug, or wiring twelve containers together for a microservices stack — these are daily operations for a forensic practitioner or software builder. On Windows you reach for WSL2 or Hyper-V and the plumbing is first-party. On Mac the story is more fragmented: there is no native Linux kernel, containers require an intermediary VM, and the ISA split introduced by Apple Silicon means x86 images that "just worked" on an Intel Mac now carry an emulation tax. Knowing which layer of the stack each tool lives in — and why — lets you pick the right tool without cargo-culting Docker Desktop.

> 🪟 **Windows contrast:** WSL2 runs a real Linux kernel inside a lightweight Hyper-V VM managed by Windows itself; `docker` on Windows routes through that same WSL2 VM (or its own Hyper-V VM in the older HCS path). On macOS there is no equivalent first-party Linux layer — every container runtime ships its own Linux VM. Apple finally shipped one in 2025/2026 via the open-source `container` CLI, but it is pre-1.0 and Apple Silicon only.

---

## Concepts

### The arm64 Elephant

Apple Silicon (M1–M4 and beyond) is `arm64` / AArch64. macOS itself, Homebrew packages, Python wheels, Rust binaries — all arm64 on a new Mac. The complication arises because most production server infrastructure is still x86-64 (`amd64`): the CI/CD pipeline that built your container almost certainly targeted `linux/amd64` unless you or your build system explicitly opted into multi-arch.

Running a mismatched container requires **binary translation** (QEMU user-mode emulation or Rosetta 2). The performance penalty for pure QEMU translation is roughly 3–8× for CPU-bound workloads. Rosetta 2 for Linux (available inside `podman machine` and `colima` when configured) narrows that to 1.1–1.5× for most code, because it JIT-compiles the x86 binary to native arm64 once and caches the result — the same technology that ran Intel macOS apps on day-one M1.

**Multi-arch OCI images** solve the problem at the source. When you `docker pull postgres`, the registry returns whichever architecture matches your platform. The `--platform` flag overrides this:

```bash
# Pull the native arm64 variant (default on Apple Silicon)
docker pull postgres:16

# Explicitly request amd64 — triggers emulation inside the Linux VM
docker pull --platform linux/amd64 postgres:16

# List manifests to verify multi-arch availability
docker buildx imagetools inspect postgres:16 | grep -E "Platform|Digest"
```

**Build multi-arch images** with `buildx`:

```bash
docker buildx create --name multiarch --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag yourrepo/myapp:1.0 \
  --push .
```

This cross-compiles inside QEMU (slow) or via an ssh-remote builder (fast). For forensic tool distribution, shipping a fat manifest means analysts on Intel servers and M-series laptops both get native binaries.

> 🔬 **Forensics note:** An arm64-only container artifact in a registry is a strong signal the image was built on Apple Silicon without `--platform` specification. It may refuse to run correctly on typical x86-64 analysis infrastructure. Check with `docker manifest inspect <image>` before pulling into a lab environment.

---

### Layer Map: Where Each Tool Lives

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        macOS userspace                                  │
│  ┌───────────┐  ┌────────────┐  ┌───────────┐  ┌───────────────────┐  │
│  │ OrbStack  │  │   Colima   │  │  Podman   │  │  Docker Desktop   │  │
│  │ (VZF VM)  │  │  (lima VM) │  │ machine   │  │  (LinuxKit VM)    │  │
│  └─────┬─────┘  └─────┬──────┘  └─────┬─────┘  └────────┬──────────┘  │
│        └──────────────┴──────────────┴──────────────────┘              │
│                        Linux VM (arm64 kernel)                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │   container daemon (dockerd / podman / containerd)               │  │
│  │   container namespaces, cgroups, overlayfs — standard Linux      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
├──────────────────── Apple Virtualization.framework ─────────────────────┤
│                    (hypercall interface to xhyve/VZ)                    │
├──────────────────── XNU Hypervisor.framework (hv_*) ────────────────────┤
│                     ARM hardware virtualization (EL2)                   │
└─────────────────────────────────────────────────────────────────────────┘
```

The key insight: there is no `CLONE_NEWNS` on XNU. macOS does not expose Linux container primitives. Every container runtime ships its own Linux VM; the containers run inside that VM using ordinary Linux kernel features. This means:

- **File I/O crosses a VM boundary** — the notorious cause of `node_modules` being slow in Docker for Mac. Different runtimes use different virtiofs / gRPC-fuse / SSHFS solutions with very different performance profiles.
- **Networking crosses the VM boundary too** — port mappings are implemented via iptables inside the Linux VM plus host-side proxies.
- **Startup includes VM boot time** — unless the runtime keeps the VM warm (OrbStack, Docker Desktop) or pre-boots it (Colima's `colima start`).

---

### Docker Desktop

The original and still the most-installed. Under the hood on Apple Silicon, Docker Desktop boots a custom **LinuxKit** VM (a minimal, purpose-built immutable Linux distribution) over the Virtualization.framework. `dockerd` runs inside that VM; the Docker socket is forwarded to `~/.docker/run/docker.sock` on the host via a proxy.

**Licensing reality:** Docker Desktop is free for personal use, small companies (< 250 employees AND < $10M revenue), education, and OSS. Commercial teams beyond those thresholds need a paid subscription (Pro/Team/Business). This is why many shops switched to alternatives in 2022–2023.

**File sharing:** Docker Desktop uses `virtiofs` on modern versions, which is significantly faster than the old gRPC-fuse path. You can verify:

```bash
docker info | grep "Storage Driver"
# Should show: overlay2 (inside VM), not fuse-overlayfs
```

**When to use it:** Teams that need the GUI dashboard, Dev Environments feature, Docker Scout, or Extensions marketplace. The licensing cost for commercial use is real but the UI is genuinely the best in class.

---

### OrbStack — the current power-user favorite

OrbStack replaces both Docker Desktop and any separate Linux VM manager. It runs a single Linux VM via Virtualization.framework, hosts `dockerd` and `containerd` inside, and exposes a fully Docker-compatible socket at `/var/run/docker.sock`. It also runs **named Linux machines** (full distro VMs) accessible via `orb` or plain `ssh`.

**Why it's fast:**

- Uses `virtiofs` with macOS kernel extensions for file sharing — benchmarks show < 5× penalty vs. native, versus Docker Desktop's historical 30–100× on large trees.
- Idle footprint: ~200–300 MB RAM (vs. Docker Desktop's 2 GB+).
- VM cold-start: ~3 seconds.
- Networking: each container gets a real IP on the host network via a tun interface — no port-mapping dance for `localhost:3000` style debugging.

**Pricing:** Free trial, $8/month (or ~$96/year) for commercial use. Personal projects are free.

```bash
# Install
brew install orbstack

# After launch, Docker CLI works immediately — OrbStack sets the socket
docker ps
docker run --rm hello-world

# Create a named Linux machine (full shell, systemd, apt)
orb create ubuntu mybox
orb shell mybox
# or: ssh mybox@orb

# List machines
orb list
```

> 🔬 **Forensics note:** OrbStack's Linux machines show up as processes under `/Applications/OrbStack.app`. The VM disk image lives at `~/Library/Containers/dev.orbstack.desktop/Data/Library/Application Support/OrbStack/data/`. If you're imaging a developer's Mac, this directory holds container layer storage (overlayfs layers) and named-machine disk images — potentially containing evidence of software builds, cloned repos, or staging environments never pushed to a remote.

---

### Colima — the free CLI-first alternative

Colima is a thin wrapper around **Lima** (Linux Machines), which manages Linux VMs using the Virtualization.framework (or QEMU for non-ARM guests). Colima starts a Lima VM with Docker or containerd inside and wires the socket.

```bash
brew install colima docker docker-compose

# Start with virtiofs (fast file sharing) and 4 CPUs / 8 GB RAM
colima start --vm-type vz --vz-rosetta --arch aarch64 \
  --cpu 4 --memory 8 --disk 60 --mount-type virtiofs

# Check status
colima status

# x86 machine with Rosetta translation (much faster than pure QEMU)
colima start x86 --vm-type vz --vz-rosetta --arch x86_64 \
  --cpu 2 --memory 4

# Switch Docker context between colima instances
docker context use colima-x86
docker run --rm alpine uname -m   # will show x86_64
```

`--vz-rosetta` injects Apple's Rosetta 2 binary translator into the VM so x86 binaries run via Rosetta instead of QEMU — the difference is dramatic for build-heavy workflows.

**Lima directly** (`brew install lima`) gives you `limactl` to manage VMs without the Colima layer. Useful when you want `nerdctl` (containerd-native CLI) instead of the Docker shim.

---

### Podman + `podman machine`

Podman is Red Hat's daemonless OCI runtime. On Mac it still needs a Linux VM (`podman machine`) because containers need a Linux kernel.

```bash
brew install podman

# Initialize and start a podman machine (VZ backend on Apple Silicon)
podman machine init --cpus 4 --memory 4096 --disk-size 60 \
  --rootful --now

# Rosetta support for x86 images
podman machine init --cpus 2 --memory 4096 \
  --rootful --image-path next-base-image \
  --now podman-x86

# Run a container
podman run --rm -it alpine sh

# Compose
podman compose up -d   # requires podman-compose or docker-compose compat layer
```

Podman's architecture is "each container is a child process of the caller, not a daemon" — but that's only true on Linux. On Mac, `podman machine` still runs a VM with a containerd/podman daemon inside; the "daemonless" property is a Linux-only reality. The socket is compatible with Docker CLI via:

```bash
export DOCKER_HOST=unix://$HOME/.local/share/containers/podman/machine/qemu/podman.sock
docker ps  # works against podman
```

**Forensic angle:** Podman stores images and containers in `~/.local/share/containers/` on the host (layer metadata) and inside the VM's disk for the actual layer data. This split is important to understand when doing artifact recovery.

---

### Rancher Desktop

Rancher Desktop (by SUSE) bundles `containerd` + `nerdctl` (the containerd-native Docker-compatible CLI) + optional `dockerd`, and wraps everything in a native macOS app. It is free, open-source, and aimed at teams who want Kubernetes (`k3s`) built in.

```bash
brew install --cask rancher

# After GUI launch, nerdctl is available
nerdctl run --rm hello-world

# Built-in single-node k3s cluster
kubectl get nodes
```

Rancher is the go-to when you need a local Kubernetes cluster and don't want to run `minikube` or `kind` as a separate layer. Performance is competitive with Colima; file-sharing speed depends on the volume driver configured in the GUI.

---

### Apple's `container` CLI (macOS 26+, Apple Silicon only)

Apple open-sourced a new container CLI in 2025 under `github.com/apple/container`, built on the `apple/containerization` Swift package. The architecture is radically different from everything else:

**Each container runs in its own dedicated lightweight VM.**

Instead of a shared Linux kernel inside one large VM (the Docker/Colima model), Apple's runtime boots a minimal Linux environment per container — similar in spirit to AWS Firecracker or gVisor, but using Virtualization.framework as the hypervisor and Apple's own `vminitd` (a Swift init process) as PID 1 inside each VM.

```bash
# Install (requires macOS 26, Apple Silicon)
brew install container

# Pull and run
container run --rm alpine:latest uname -a

# List running containers
container list

# Build from Dockerfile (OCI-compatible output)
container build -t myapp:latest .

# Push to registry
container push myapp:latest registry.example.com/myapp:latest
```

**What this buys you:**

- Kernel-level isolation per container — a kernel exploit in one container cannot escape to a shared Linux kernel affecting others.
- Sub-second container start time (VM boot is that fast because the VM image is tiny and uses VZ's snapshotting).
- Each container gets its own IP address — no port-mapping ceremony.

**What it lacks (pre-1.0):**

- No `docker compose` equivalents yet.
- No macOS containers (only Linux).
- No GPU/Metal passthrough.
- Image-unpack performance for large images is significantly slower than Docker Desktop (10 minutes vs. seconds for a large base image in early benchmarks).
- `containerd` shim compatibility is incomplete — some Docker plugins won't work.

This is the right tool to watch for the next 12–18 months. It is not ready to replace Docker Desktop for production workflows but is architecturally interesting and Apple-native.

> 🔬 **Forensics note:** Each Apple `container` VM is a transient VZ machine. Between launches there are no persistent VM processes — the isolation boundary means container storage is in OCI layer tarballs rather than overlayfs mounts. Artifact recovery from a system that used `container` looks more like OCI registry forensics than Docker layer archaeology.

---

### Full VMs: UTM, Parallels, VMware Fusion

When you need a full operating system — not a container — you want a proper VM. Three realistic options on Apple Silicon:

#### UTM (free, QEMU-backed)

UTM is a macOS frontend for QEMU. It can:

- **Virtualize** arm64 guests (Linux ARM, macOS, Windows 11 ARM) at near-native speed using Virtualization.framework (no QEMU CPU emulation).
- **Emulate** x86, x86-64, MIPS, RISC-V, and other architectures at software-emulation speed (slow, but workable for legacy analysis).

```
UTM VM types:
  Virtualize  → VZ backend → near-native ARM guests
  Emulate     → QEMU backend → any architecture, slow
```

UTM is the forensic analyst's choice for **x86 malware analysis sandboxes** (run a Windows XP or Windows 7 x86 VM in emulation mode — it's slow but it works and it's free), **Linux distro testing** (grab any arm64 ISO and virtualize it), and **retro OS work**.

GPU support is limited: UTM exposes a software-rendered framebuffer for most emulated guests. For virtualized arm64 guests, VirtIO-GPU is available but there is no Metal passthrough.

Download: `brew install --cask utm`

#### Parallels Desktop

Parallels is the highest-fidelity Windows-on-Mac experience available. It uses its own hypervisor (not the Apple Virtualization.framework) for maximum optimization. Key facts for 2026:

- Runs **Windows 11 ARM** at near-native CPU speed; x86 Windows applications run via **Microsoft's built-in x86 emulation layer** inside Windows 11 ARM — this is Microsoft's own technology, distinct from Rosetta, and works surprisingly well for most commercial software.
- **Coherence mode** lets Windows apps appear as floating windows in macOS — they show up in the Dock and Alt-Tab.
- DirectX 12 / Metal bridge for games and GPU-intensive apps.
- **Windows 11 ARM licensing:** Microsoft's terms allow running Windows 11 ARM in a VM on Apple Silicon Macs under the Parallels subscription — Parallels bundles a compliant copy. You do not need a separate Windows license for personal use on a Mac that would otherwise run Windows.
- Subscription: ~$100/year for the standard tier. No perpetual license for new major versions.

```bash
brew install --cask parallels
```

After GUI setup, the `prlctl` CLI gives programmatic control:

```bash
prlctl list -a                        # all VMs
prlctl start "Windows 11"
prlctl exec "Windows 11" -- ipconfig  # run a command in the guest
prlctl snapshot-create "Windows 11" --name "clean-slate"
prlctl snapshot-switch "Windows 11" --name "clean-slate"
```

> 🔬 **Forensics note:** Parallels VM disk images are `.pvm` bundles at `~/Parallels/`. Each `.pvm` contains `.hdd` disk images. The disk format is Parallels-proprietary but can be converted to VMDK or RAW via `prl_disk_tool` for offline analysis with Autopsy, FTK, or `mount`. Snapshots are stored as delta disks inside the `.pvm` bundle — a forensically interesting timeline of system state.

#### VMware Fusion

VMware Fusion was acquired by Broadcom, then made **free for personal use** (Fusion Pro is free; commercial use requires a Broadcom subscription). On Apple Silicon it uses the Apple Virtualization.framework as its hypervisor backend (as of Fusion 13.x), which means performance and feature parity with other VZ-backed tools rather than VMware's own hypervisor magic.

```bash
brew install --cask vmware-fusion
```

Fusion's strengths: VMware `.vmdk` and `.ova` format support (run VMs you already have from enterprise VMware environments), vSphere remote VM console, and a mature snapshot/clone workflow. The `vmrun` CLI parallels `prlctl`:

```bash
vmrun start ~/Virtual\ Machines.localized/MyVM.vmwarevm/MyVM.vmx nogui
vmrun listSnapshots ~/...vmx
vmrun snapshot ~/...vmx "pre-test"
vmrun revertToSnapshot ~/...vmx "pre-test"
```

> 🪟 **Windows contrast:** Hyper-V on Windows is the built-in hypervisor (free, Type-1). WSL2 runs inside a Hyper-V utility VM. Docker Desktop on Windows can use either the WSL2 backend (shared Linux kernel with WSL) or a Hyper-V backend. There is no Mac equivalent — macOS has no Type-1 hypervisor; VZ and the Hypervisor.framework are Type-2 (run in user space as privileged processes). The performance is still excellent because Apple's hardware virtualization (EL2) handles the heavy lifting.

---

### macOS-on-macOS Virtualization

The Virtualization.framework supports running **macOS as a guest** on a Mac host. There are practical limits:

- **Apple's licensing permits at most 2 simultaneous macOS VMs** on a single physical machine.
- The guest must be the same or earlier macOS version than the host (you can run macOS 14 under macOS 26, not the reverse).
- No nested virtualization — you cannot run a hypervisor inside a macOS VM.
- No DRM playback inside the guest (no Apple TV+, Netflix DRM, FairPlay — the secure enclave for DRM is host-only).
- No GPU Metal passthrough — guest gets a virtualized GPU, not the physical one.

Both UTM and Parallels expose this capability via their GUI. It is primarily useful for:

1. **Automated macOS testing** (XCUITest, xcrun simctl) without needing a second physical Mac.
2. **OS upgrade staging** — test that your app runs on the next macOS before upgrading the host.
3. **Forensic macOS guest** — analyze a suspicious `.app` in a throwaway macOS environment.

---

### GPU/Metal Passthrough Reality

This is where every option falls short compared to native:

| Tool | GPU Access in Guest |
|------|-------------------|
| Apple `container` | None (no GPU passthrough) |
| OrbStack Linux machine | None |
| Colima / Lima | None |
| Docker containers | None (use MPS on host instead) |
| UTM (emulated) | VirtIO-GPU (software renderer) |
| UTM (virtualized arm64) | VirtIO-GPU; limited 3D |
| Parallels | DirectX 12 / Metal bridge for Windows guests |
| VMware Fusion | Limited Metal bridge |
| macOS guest (VZ) | Virtualized GPU, no passthrough |

For ML workloads, the practical answer is: **don't put ML inside a VM**. Run PyTorch/MLX directly on macOS and mount data into a container for preprocessing. Apple's `mlx` framework runs on the host Metal GPU with no VM boundary.

---

### File Sharing & Networking

**Volume mount performance ladder (fastest to slowest):**

1. **OrbStack virtiofs** — patched VZ virtiofs with macOS kernel extensions; near-native for most workloads.
2. **Colima `--mount-type virtiofs` with `--vz-rosetta`** — standard VZ virtiofs; excellent for sequential I/O.
3. **Docker Desktop virtiofs** (current versions) — improved significantly in 2023.
4. **Colima SSHFS** (default without `--mount-type`) — avoid for anything I/O intensive.
5. **QEMU 9P** (legacy) — avoid entirely.

**Networking models:**

- **OrbStack:** Each container gets a routable IP in the `198.19.0.0/16` subnet; host can reach containers directly without `-p` port publishing. The `orb` DNS resolver makes `<name>.orb.local` work from the host.
- **Docker Desktop / Colima:** Bridge networking inside the VM; `-p 8080:80` creates a host-side listener via a proxy process. `host.docker.internal` resolves to the VM's gateway.
- **Apple `container`:** Each container gets its own IP via VZ networking — reachable from the host without port mapping.
- **Parallels/VMware:** Shared NAT (default) or Bridged to a physical interface. Bridged gives the VM a real LAN IP — useful for network forensics simulations.

---

## Hands-on (CLI & GUI)

### Check your container runtime and architecture

```bash
# What is running?
docker info 2>/dev/null | grep -E "Server Version|Operating System|Architecture|Context"

# What context is active?
docker context ls

# Inside a running container: verify architecture
docker run --rm alpine uname -m
# Expected: aarch64 (native arm64)

docker run --rm --platform linux/amd64 alpine uname -m
# Expected: x86_64 (emulated — will be slower)
```

### Switch between runtimes without conflict

Multiple runtimes can coexist. They each expose a Docker socket; Docker contexts let you switch:

```bash
# List contexts
docker context ls

# Use OrbStack
docker context use orbstack

# Use Colima (if running)
docker context use colima

# Use default (Docker Desktop)
docker context use default

# Set via env var (overrides context)
export DOCKER_CONTEXT=orbstack
```

### Inspect a container's kernel from the host

```bash
# What kernel is the Linux VM running?
docker run --rm alpine uname -r
# e.g.: 6.10.14-linuxkit  (Docker Desktop's LinuxKit kernel)
# or:   6.6.x-orbstack     (OrbStack's kernel)
# or:   6.1.x              (Colima's default)

# Check cgroups version
docker run --rm alpine cat /proc/cgroups | head -5
```

---

## 🧪 Labs

### Lab 1: Spin Up a Linux Container with OrbStack or Colima

> ⚠️ **Prerequisites:** Install OrbStack (`brew install orbstack`) or Colima (`brew install colima docker`). For Colima: `colima start --vm-type vz --vz-rosetta --mount-type virtiofs`. No destructive operations.

```bash
# 1. Verify Docker is talking to your runtime
docker info | grep "Server Version"

# 2. Run an interactive arm64 Alpine container
docker run --rm -it alpine sh
# Inside: uname -m → aarch64, cat /etc/os-release, exit

# 3. Mount a host directory (read-only)
docker run --rm -it -v "$HOME/Downloads":/host-data:ro alpine ls /host-data

# 4. Run a web server container and test it
docker run -d --name webtest -p 8080:80 nginx:alpine
curl -s http://localhost:8080 | grep -o "<title>.*</title>"
docker logs webtest
docker stop webtest && docker rm webtest

# 5. Inspect the layers of an image
docker pull ubuntu:24.04
docker history ubuntu:24.04
docker inspect ubuntu:24.04 | python3 -m json.tool | grep -E '"Size"|"Created"' | head -20
```

### Lab 2: Feel the arm64 vs x86 Emulation Difference

> ⚠️ **Note:** The x86 container will run slowly — this is intentional. The lab is to benchmark the difference, not optimize it. No data is modified.

```bash
# A reproducible CPU benchmark: compute fibonacci in Python
FIB_CMD='python3 -c "
import time, sys
def fib(n): return n if n <= 1 else fib(n-1) + fib(n-2)
t = time.time(); print(fib(35)); print(f\"{time.time()-t:.2f}s\")
"'

# Native arm64
echo "=== arm64 (native) ==="
time docker run --rm --platform linux/arm64 python:3.12-alpine sh -c "$FIB_CMD"

# x86_64 (emulated via QEMU or Rosetta)
echo "=== x86_64 (emulated) ==="
time docker run --rm --platform linux/amd64 python:3.12-alpine sh -c "$FIB_CMD"

# Compare the wall times. With pure QEMU you will see 4-8x slower.
# With Rosetta2 emulation (colima --vz-rosetta) you will see 1.2-2x slower.
```

### Lab 3: Create a Linux VM in UTM

> ⚠️ **Disk space required:** The VM will use 8–15 GB. Choose a location with space. To roll back: delete the VM in UTM's UI or remove the `.utm` bundle from `~/Library/Containers/com.utmapp.UTM/Data/Documents/`.

1. Install UTM: `brew install --cask utm`
2. Launch UTM → **+** → **Virtualize** (for arm64 guests) → **Linux**
3. Download an arm64 ISO: Ubuntu 24.04 LTS ARM (`ubuntu-24.04-live-server-arm64.iso` from ubuntu.com/download/server/arm)
4. In UTM: 4 CPU cores, 4 GB RAM, 20 GB disk, attach the ISO.
5. Boot → complete Ubuntu server install → reboot.
6. After first boot, from the host verify network access:

```bash
# Get the VM's IP from UTM UI or inside the VM
# From host:
ping -c 3 <vm-ip>
ssh user@<vm-ip>

# Inside VM: verify arm64
uname -m         # aarch64
cat /proc/cpuinfo | grep "model name" | head -1
# → "CPU implementer: 0x61" (Apple Silicon passthrough)
```

**Bonus:** Add a **second UTM VM** configured as **Emulate** → **x86_64** architecture. Boot a Debian netinst x86_64 ISO. Observe that the framebuffer is slower and CPU-intensive operations take longer — this is software QEMU translation at work.

### Lab 4: OrbStack Linux Machine — Full Distro VM

```bash
# OrbStack must be running
orb create ubuntu:24.04 forensic-box

# Shell into it (systemd running, apt available)
orb shell forensic-box

# Inside: install tools
sudo apt update && sudo apt install -y sleuthkit autopsy
# Autopsy web UI: http://forensic-box.orb.local:9999 (from host browser)

# From host: copy a disk image into the machine
orb push forensic-box ~/Downloads/suspect.img /home/ubuntu/suspect.img

# Snapshot the machine (OrbStack saves state as a VZ snapshot)
orb stop forensic-box
# Machines persist at ~/Library/Containers/dev.orbstack.desktop/...

# Destroy when done
orb delete forensic-box
```

### Lab 5: Multi-arch Build and Manifest Inspection

```bash
# Inspect a popular image's multi-arch manifest
docker buildx imagetools inspect python:3.12-slim 2>/dev/null | \
  grep -A 3 "Platform:"

# Build a two-arch image (requires a builder with QEMU or remote arm64 builder)
cat > /tmp/Dockerfile.test << 'EOF'
FROM alpine:latest
RUN echo "Built for $(uname -m)" > /arch.txt
CMD cat /arch.txt
EOF

docker buildx create --name multiarch --driver docker-container --use 2>/dev/null || true
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --file /tmp/Dockerfile.test \
  --tag localhost/archtest:latest \
  --load \
  /tmp

# Run both variants
docker run --rm --platform linux/arm64 localhost/archtest:latest   # aarch64
docker run --rm --platform linux/amd64 localhost/archtest:latest   # x86_64
```

---

## Pitfalls & gotchas

**"My image works on Linux CI but fails locally"** — Your CI is `linux/amd64`; your Mac pulled `linux/arm64`. The binary or native extension inside the image may not have an arm64 build. Fix: `--platform linux/amd64` or file an upstream issue requesting multi-arch images.

**Slow `node_modules` bind mounts** — This is the most common Docker-on-Mac complaint. The fix is: use named volumes instead of bind mounts for dependency directories (`-v node_modules_vol:/app/node_modules`), or switch to a runtime with better virtiofs (OrbStack). Never use SSHFS mounts for write-heavy directories.

**Port conflicts when switching runtimes** — Docker Desktop, OrbStack, and Colima all want to own `/var/run/docker.sock` and port 2375 (if enabled). Run only one at a time or use Docker contexts rigorously. OrbStack and Docker Desktop will fight if both are in the menu bar.

**`docker.io` vs `ghcr.io` rate limits** — Docker Hub anonymous pull limit is 100 pulls/6h per IP. Behind corporate NAT this burns fast. Use `docker login` or switch to `ghcr.io` / `quay.io` images where available.

**Windows 11 ARM in Parallels: x86-only apps** — Not all x86 Windows apps run flawlessly under Microsoft's emulation layer inside Windows 11 ARM. Game anti-cheat, kernel drivers (especially security tools, USB debugging aids), and some 16-bit installers fail. Test before committing to a workflow.

**UTM emulation and time sync** — QEMU's emulated clock drifts noticeably under load. Inside an emulated x86 VM: `sudo hwclock --hctosys` or `sudo systemctl restart systemd-timesyncd` after any CPU-heavy operation if timestamps matter for forensic work.

**`container` CLI image unpack speed** — Apple's container tool is slow to unpack large base images (reported 10+ minutes for images like `ocaml/opam` that Docker Desktop handles in seconds). This is a known pre-1.0 limitation. Stick with Docker/OrbStack for large images until this is addressed upstream.

**macOS guest VM and iCloud Keychain** — A macOS VM does not have access to your Apple ID or iCloud Keychain. App Store apps inside the VM require a separate Apple ID sign-in. DRM-protected content (Apple TV+, some FairPlay-protected media) will not play in the guest.

---

## Key takeaways

1. **Containers on Mac always go through a Linux VM** — there is no native Linux kernel on macOS. The runtime's quality is mostly determined by how efficiently it crosses that VM boundary for file I/O and networking.
2. **Prefer arm64 images; know the Rosetta option for x86** — native arm64 is full speed, Rosetta-translated x86 is ~1.2–1.5×, pure QEMU x86 is ~4–8× slower. Enable `--vz-rosetta` in Colima/Podman when you need x86 images regularly.
3. **OrbStack is the current high-performance default** for developers willing to pay; Colima with `virtiofs + vz-rosetta` is the free equivalent.
4. **Apple's `container` CLI is architecturally the future** — per-container VM isolation is a meaningful security improvement — but it is pre-1.0 and not a daily-driver replacement yet.
5. **For full VMs:** Parallels for daily Windows use, UTM for free x86 emulation or occasional Linux VMs, VMware Fusion for VMware ecosystem compatibility.
6. **GPU/Metal is not available inside VMs or containers** on Mac. Do ML on the host; put data pipelines in containers.
7. **Docker contexts** are your friend when juggling multiple runtimes — use them instead of hacking socket symlinks.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| **arm64 / AArch64** | The 64-bit ARM instruction set used by Apple Silicon (M-series) |
| **amd64 / x86-64** | The 64-bit x86 instruction set used by Intel/AMD CPUs |
| **OCI** | Open Container Initiative — the standards body for container image and runtime formats |
| **Virtualization.framework (VZ)** | Apple's high-level Swift/Objective-C API for creating and managing VMs on Apple Silicon |
| **Hypervisor.framework** | Apple's low-level API for setting up VMs (hv_* calls); VZ sits on top of this |
| **virtiofs** | A Linux virtio-based filesystem protocol for sharing host directories into a VM with high performance |
| **LinuxKit** | Docker's custom, minimal, immutable Linux distribution used as the Docker Desktop VM |
| **Lima** | Linux VM manager for macOS (CLI); the layer beneath Colima |
| **nerdctl** | A Docker-compatible CLI for containerd (used by Rancher Desktop) |
| **Rosetta 2 for Linux** | Apple's x86→arm64 binary translator injected into Linux VMs; faster than QEMU emulation |
| **vminitd** | Apple's Swift-written PID 1 process inside Apple `container` VMs |
| **Kata Containers** | OCI-compatible container runtime that runs each container in its own VM (conceptual peer to Apple's model) |
| **Coherence mode** | Parallels feature that renders Windows app windows as floating macOS windows |
| **prlctl** | Parallels command-line control tool |
| **vmrun** | VMware Fusion command-line tool |
| **buildx** | Docker CLI plugin for multi-platform builds using QEMU/cross-compilation |
| **Docker context** | A named Docker CLI configuration pointing to a specific daemon socket |

---

## Further reading

- [apple/container on GitHub](https://github.com/apple/container) — source code, architecture notes, macOS 26 requirements
- [apple/containerization on GitHub](https://github.com/apple/containerization) — the underlying Swift package
- Anil Madhavapeddy, "Under the hood with Apple's new Containerization framework" — deep technical teardown of `vminitd`, ext4 in Swift, and the VM-per-container model
- [Lima project](https://github.com/lima-vm/lima) — the VZ/QEMU VM layer beneath Colima and others
- [OrbStack documentation](https://docs.orbstack.dev) — especially the networking and file-sharing architecture pages
- Apple Platform Security Guide — Virtualization.framework and the hypervisor entitlement (`com.apple.security.hypervisor`)
- [Parallels KB: Windows 11 ARM on Mac](https://kb.parallels.com/125375) — licensing details and x86 app compatibility matrix
- [UTM documentation](https://docs.getutm.app) — emulation vs. virtualization mode guide
- Howard Oakley (Eclectic Light Company) — articles on macOS Virtualization.framework internals and the historical evolution from xhyve to VZ
- `man container` (after install) — flag reference for Apple's container CLI
- [[01-boot-process]] — understand the XNU kernel and why it cannot host Linux containers natively
- [[06-security-privacy]] — SIP, Gatekeeper, and how they interact with hypervisor entitlements
