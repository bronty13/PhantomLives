---
title: Files, permissions, ACLs & flags
part: P03 CLI
est_time: 50 min read + 40 min labs
prerequisites: [03-essential-unix-commands, 04-filesystem-layout-and-domains, 08-security-architecture]
tags: [macos, permissions, acl, chflags, posix, security, forensics, sip, tcc]
---

# Files, permissions, ACLs & flags

> **In one sentence:** macOS enforces file access through three stacked layers — POSIX mode bits, NFSv4-style ACLs, and BSD file flags — each evaluated in order, with SIP and TCC sitting above all of them and producing a categorically different error when they fire.

## Why this matters

Windows forensic examiners know NTFS ACLs intimately — every file has a security descriptor with DACLs, SACLs, owner SID, and inheritance flags. macOS presents a different architecture that looks simpler on the surface (just POSIX `rwxrwxrwx`) but is actually a three-layer stack, plus two additional enforcement mechanisms (SIP and TCC) that operate outside the filesystem entirely. Misidentifying which layer is refusing access costs hours in investigations and development alike.

For forensics: immutable flags, quarantine extended attributes, and ACL entries all survive copy operations in ways that matter for evidence integrity. Knowing how to read, set, and preserve them is as foundational as knowing how to read NTFS ACLs.

> 🪟 **Windows contrast:** NTFS uses a single security descriptor per file containing owner SID, DACL (what's allowed/denied), and SACL (what's audited). macOS separates these concerns: POSIX handles the basic owner/group/other model, ACLs layer NFSv4-style entries on top, BSD flags add a separate immutability/visibility axis, and SIP/TCC operate at kernel/daemon level above the VFS. You need to understand all four to diagnose a blocked operation.

---

## Concepts

### Layer 0: How the VFS evaluates access

Before diving into each layer, understand the evaluation order. When a process attempts any file operation, the kernel's VFS (Virtual File System) layer in XNU works through checks in this order:

```
1. Is the process running as root?
   → If yes, skip POSIX ownership checks (but NOT ACL deny entries, flags, or SIP)
2. BSD file flags (chflags) — uchg/schg block writes even to root
3. ACL entries — evaluated top-to-bottom; first matching allow or deny wins
4. POSIX mode bits — owner/group/other rwx
5. SIP (rootless) — enforced by the Sandbox kernel extension; vetos even root
6. TCC — enforced by tccd; vetos at the process level, not the file level
```

This ordering matters: a file can have POSIX `rwxrwxrwx` and still be completely unwritable because of an `schg` flag or a SIP `restricted` bit.

---

### Layer 1: POSIX permissions

#### The nine mode bits

Every file and directory has three permission triplets encoded as a 12-bit value:

```
  S  S  T   |  r  w  x  |  r  w  x  |  r  w  x
 uid gid sty | owner     | group     | other
  4  2  1   |  4  2  1  |  4  2  1  |  4  2  1
```

`ls -l` displays these as the first ten characters:

```
-rwxr-xr--   1  bronty13  staff  8432  Jun  8 14:22  myscript.sh
drwxrwxrwx+  3  bronty13  staff   128  Jun 10 09:01  shared/
```

The leading `-` or `d` is the file type. The `+` at the end signals an ACL is present (see Layer 2). The `@` signals extended attributes are present.

```
-rw-r--r--@  1  bronty13  staff  1024  Jun 12 10:00  document.pdf
```

Both can appear together: `-rwxr-xr--@+` means execute + xattrs + ACL.

#### chmod: setting mode bits

```bash
# Symbolic
chmod u+x script.sh          # add execute for owner
chmod go-w sensitive.txt     # remove write from group and other
chmod a=r readonly.txt       # set all to read-only
chmod ug=rwx,o=r dir/        # owner+group rwx, other r only

# Octal (faster once memorized)
chmod 755 script.sh          # rwxr-xr-x — typical executable
chmod 644 config.txt         # rw-r--r--  — typical data file
chmod 700 private/           # rwx------  — owner-only directory
chmod 600 ~/.ssh/id_ed25519  # rw------- — private key (SSH enforces this)
```

#### chown and chgrp

```bash
chown bronty13 file.txt               # change owner
chown bronty13:staff file.txt         # change owner and group
chown -R bronty13:staff ./project/    # recursive
chgrp wheel /usr/local/bin/mytool     # change group only
```

On macOS, a non-root user can only `chown` files they own to themselves — they cannot gift files to other users. Root or `sudo` is required to transfer ownership.

#### umask: the permission mask for new files

`umask` is the octal complement applied to new file/directory creation. The kernel starts new files at `0666` and directories at `0777`, then masks off the umask bits:

```bash
umask           # → 0022 (default on macOS)
# New file:  0666 & ~0022 = 0644 (rw-r--r--)
# New dir:   0777 & ~0022 = 0755 (rwxr-xr-x)

umask 0077      # private-by-default: new files 0600, dirs 0700
umask 0002      # group-writable: new files 0664, dirs 0775
```

Set `umask` in `~/.zshrc` to persist it across shell sessions. The macOS default of `0022` is appropriate for shared servers; `0077` is the right default for single-user developer machines handling sensitive data.

> 🔬 **Forensics note:** umask is a process-inherited attribute. When a forensic tool creates output files, its effective umask determines who can read that output. Verify umask in your acquisition environment — running under `sudo` in a shell that inherited `0022` will leave evidence files group/world-readable.

#### setuid, setgid, and sticky bit

These occupy bits 11–9 (the `S/s/T/t` positions):

| Bit | Octal | On file | On directory |
|-----|-------|---------|--------------|
| setuid | 4000 | Execute as file's owner (e.g., `passwd` runs as root) | (ignored on macOS) |
| setgid | 2000 | Execute as file's group | New files inherit directory's group |
| sticky | 1000 | (legacy; ignored on files) | Only owner can delete entries (e.g., `/tmp`) |

```bash
chmod 4755 /usr/local/bin/mytool   # setuid + rwxr-xr-x
chmod 1777 /tmp                     # sticky + rwxrwxrwx (the classic /tmp)

ls -l /usr/bin/passwd
# -rwsr-xr-x  1  root  wheel  ...  /usr/bin/passwd
#   ^-- lowercase 's' = setuid AND execute bit set
#   uppercase 'S' = setuid set but execute bit NOT set (probably a mistake)
```

> ⚠️ **ADVANCED:** setuid on macOS is heavily restricted. The kernel silently strips setuid/setgid bits from scripts (anything with a `#!` shebang). Hardened runtime and library validation (`CS_HARD`, `CS_KILL`) further constrain what setuid binaries can do. SIP prevents setting setuid on files in protected directories even as root.

> 🔬 **Forensics note:** Unexpected setuid files are a classic persistence and privilege-escalation indicator. On a forensic image, enumerate them with:
> ```bash
> find / -perm -4000 -type f 2>/dev/null    # setuid files
> find / -perm -2000 -type f 2>/dev/null    # setgid files
> ```
> Compare against a known-good baseline. Any setuid binary outside `/usr/bin`, `/usr/sbin`, `/bin`, `/sbin` warrants investigation.

#### Directory traversal: the execute bit

The `x` bit on a **directory** means something categorically different from `x` on a file. It controls **traversal** — the right to `cd` into, or reference files within, the directory. Without it:

```bash
chmod 644 secret_dir/
ls secret_dir/someFile.txt    # → ls: secret_dir/someFile.txt: Permission denied
# Even though someFile.txt has 0644, you can't address it through a directory you can't traverse
```

A directory with `r--` (read, no execute) lets you `ls` the names but not access the files or subdirectories. A directory with `--x` (execute, no read) lets you access files if you know their names, but `ls` shows nothing. This distinction is often misunderstood and occasionally exploited.

---

### Layer 2: ACLs (Access Control Lists)

#### What macOS ACLs actually are

macOS uses **NFSv4-style ACLs**, not the POSIX.1e draft ACLs found on Linux (where `getfacl`/`setfacl` are the tools). The distinction matters: POSIX.1e ACLs support a fixed schema (owner, named user, owning group, named group, mask, other); NFSv4 ACLs are an ordered list of Access Control Entries (ACEs) that each specify:

- **Principal**: a user or group by name, or the special `everyone` built-in
- **Direction**: `allow` or `deny`
- **Rights**: a comma-separated list of permission verbs
- **Inheritance flags**: how the ACE propagates to new children (on directories)

The `+` indicator you see in `ls -l` output signals at least one ACE is present. ACLs on macOS are stored as the `com.apple.acl` extended attribute (visible with `ls -l@`).

#### Viewing ACLs

```bash
ls -le file.txt          # -l plus ACL display
ls -le@                  # -l plus ACL plus extended attributes (the full picture)
ls -led ~/               # -l -e -d: directory itself, not its contents

# Example output:
drwx------+  50  bronty13  staff  1600  Jun 13 09:00  /Users/bronty13
 0: group:everyone deny delete
 1: user:bronty13 allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,writesecurity,chown
```

Each ACE is prefixed with its zero-indexed position in the list. That position is the evaluation order.

#### Setting ACLs with chmod

Apple repurposed `chmod` for ACL manipulation — the `+a` and `-a` flags:

```bash
# Add an allow ACE
chmod +a "user:alice allow read,write" project.txt

# Add a deny ACE (deny takes precedence if it appears first)
chmod +a "group:everyone deny delete" important/

# Add at a specific position (position 0 = top of list, evaluated first)
chmod +a# 0 "user:bob deny execute" script.sh

# Remove an ACE (must match exactly)
chmod -a "user:alice allow read,write" project.txt

# Remove ACE by position
chmod -a# 1 project.txt

# Remove ALL ACLs from a file
chmod -N project.txt
```

The rights vocabulary for macOS NFSv4 ACLs includes:

| Right | Meaning |
|-------|---------|
| `read` | Read file data |
| `write` | Write file data |
| `execute` | Execute (files) / traverse (directories) |
| `delete` | Delete this item |
| `delete_child` | Delete items within directory |
| `append` | Append to file (without read/write) |
| `list` | List directory contents |
| `add_file` | Create files in directory |
| `add_subdirectory` | Create subdirectories |
| `search` | Look up names in directory (`cd` equivalent) |
| `readattr` | Read POSIX attributes (owner, mode) |
| `writeattr` | Change POSIX attributes |
| `readextattr` | Read extended attributes (xattrs) |
| `writeextattr` | Write extended attributes |
| `readsecurity` | Read ACL |
| `writesecurity` | Change ACL and ownership |
| `chown` | Change file ownership |

#### ACL evaluation order: the critical detail

ACEs are evaluated **top-to-bottom**. The **first matching entry wins** — no further evaluation occurs. This is unlike POSIX where deny is always checked before allow; in macOS ACLs, order is everything.

```
0: user:bob deny read         ← if this matches, read is DENIED; stop
1: group:staff allow read     ← never reached for bob
2: group:everyone deny read   ← never reached if matched above
```

Practical implication: to deny a specific user while allowing a group they belong to, the user `deny` ACE must precede the group `allow` ACE.

#### ACL inheritance on directories

Inheritance flags extend the ACE syntax:

```bash
# file_inherit: new files created in this directory get this ACE
# directory_inherit: new subdirectories get this ACE
# limit_inherit: inherited ACE doesn't further propagate (stops at one level)
# only_inherit: this ACE applies only to new children, not to the directory itself

chmod +a "group:devteam allow read,write,delete file_inherit,directory_inherit" ./project/
```

When the kernel creates a new file inside `project/`, it walks the parent's ACL and copies any ACE marked `file_inherit` to the new file's ACL. Same for `directory_inherit` on new subdirectories. This is how Finder propagates the ACLs it sets on home directories to their standard subfolders.

#### How Finder uses ACLs

Finder's Get Info → Sharing & Permissions pane writes ACLs. The padlock icon in Get Info is locking POSIX permissions + any Finder-managed ACLs together. The "Locked" checkbox (separate from Sharing & Permissions) sets the `uchg` BSD flag — see Layer 3.

The default home directory ACL (`group:everyone deny delete` on `~`) is set by `sysadminctl` during account creation and prevents deletion of the home folder even by admin users without authentication — a simple but effective anti-tampering measure.

> 🪟 **Windows contrast:** NTFS DACLs have explicit Deny and Allow ACEs and follow the same "deny wins when at the same level" ordering that confuses Windows admins. macOS ACLs use strict positional ordering instead: a Deny at position 5 does NOT override an Allow at position 2. If you're coming from NTFS, mentally model macOS ACLs as a sequential rule chain, not a priority system.

> 🔬 **Forensics note:** ACLs on macOS are stored as the `com.apple.acl` extended attribute and round-trip through most copy operations that preserve xattrs (e.g., `cp -p`, `rsync -X`, `ditto`). However, copying via a FAT32/exFAT volume strips them — a common evidence-contamination vector. When imaging macOS volumes for forensic purposes, confirm your tool preserves ACLs. Autopsy and `dd` at the block level preserve them; `cp` without `-p` does not.

---

### Layer 3: BSD file flags

BSD file flags are a separate, orthogonal access control mechanism. They are **not** Unix permissions; they live in the inode's `st_flags` field and are manipulated with `chflags`. View them with `ls -lO` (capital O):

```bash
ls -lO sensitive.txt
-rw-r--r-- uchg bronty13  staff  1024  Jun 12 10:00  sensitive.txt
#           ^^^^--- flags appear between mode+links+owner
```

Multiple flags appear comma-separated: `uchg,hidden`.

#### The flag vocabulary

| Flag | Set by | Meaning |
|------|--------|---------|
| `uchg` / `uimmutable` | Any owner | **User immutable**: file cannot be modified, renamed, or deleted — even by the owner. Only the owner (or root) can unset it. |
| `schg` / `simmutable` | root only | **System immutable**: like `uchg` but requires root to clear. Survives normal `sudo` access — needs single-user mode or SIP-off to defeat. |
| `uappnd` / `uappend` | Any owner | User append-only: only appending allowed; existing content can't be modified. |
| `sappnd` / `sappend` | root only | System append-only: same but requires root to clear. Used on log files. |
| `hidden` | Any owner | Hides the item from Finder and `ls` (without `-a`). Does NOT hide from `ls -a` or forensic tools. |
| `nodump` | Any owner | Excludes from `dump(8)` backups. Mostly historical but still honoured. |
| `restricted` | System | **SIP flag**: set by the OS on SIP-protected paths. Cannot be cleared while SIP is active. See below. |
| `sunlnk` | System | Prevents the directory itself from being unlinked (deleted), but allows creation/modification/deletion of contents. Set on SIP-protected directories. |

#### Setting and clearing flags

```bash
# Lock a file (user immutable)
chflags uchg important.txt

# Unlock
chflags nouchg important.txt

# System immutable (requires sudo)
sudo chflags schg /etc/hosts

# Unlock system immutable
sudo chflags noschg /etc/hosts

# Multiple flags at once
chflags uchg,hidden sensitive/

# Recursive
sudo chflags -R uchg ./evidence/    # preserve a whole tree as immutable

# Clear all flags
chflags 0 file.txt
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `chflags -R schg /` on a running system will make the entire filesystem immutable. Even root cannot write to it afterward without clearing flags on every file. This requires booting to recoveryOS or single-user mode to fix. Never run recursive `schg` on system directories.

#### The "Locked" checkbox in Finder

Finder's Get Info → Locked checkbox sets `uchg` on the file. Under the hood it calls `chflags uchg`. This is frequently confused with POSIX mode bits by both users and developers — a file can be POSIX `0777` (world-writable) and yet reject all writes because `uchg` is set.

```bash
# Simulate what Finder "Lock" does:
chflags uchg ~/Documents/contract.pdf

# Confirm:
ls -lO ~/Documents/contract.pdf
# -rw-r--r-- uchg  bronty13  staff  ...
```

#### The `restricted` flag and SIP

System Integrity Protection (SIP) marks its protected paths — `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, and a few others — with the `restricted` flag in the filesystem. This flag is surfaced by `ls -lO`:

```bash
ls -lOd /System/Library/
# drwxr-xr-x  restricted  root  wheel  ...  /System/Library/
```

The `restricted` flag is set during OS installation and is re-applied by software update. You cannot set or clear it manually while SIP is active — the kernel's Sandbox extension (the `com.apple.security.sandbox` KEXT ancestor, now in-process with the kernel) intercepts the `chflags` syscall and returns `EPERM`.

SIP coverage goes beyond the flag: the protected paths are also hardcoded in the kernel (`__DATA_CONST` segment of `/System/Library/Kernels/kernel.release.t8103` on M-series, for example), so even if you cleared the flag on individual files, SIP protection would remain.

> 🔬 **Forensics note:** On a forensic image of a macOS volume, the presence or absence of `restricted` flags on expected system paths is a SIP integrity indicator. If `/usr/bin/python3` lacks the `restricted` flag on a live system, SIP was disabled at some point. This is a potential indicator of compromise or jailbreak-style tampering. Tool: `ls -lO /System /usr/bin /sbin` and compare file-by-file against a clean reference image.

---

### Extended attributes and quarantine (cross-reference)

Extended attributes (xattrs) are a separate mechanism from flags — they're key-value stores on inodes, visible with `ls -@` or `xattr`. The most forensically important:

- `com.apple.quarantine` — set by browsers, Mail, and any app using `LSQuarantineEventMessage`. Records where and when a file was downloaded. See [[09-spotlight-metadata-and-xattrs]] for full detail.
- `com.apple.acl` — where ACL data is actually stored (reading `ls -le` decodes this xattr for display)
- `com.apple.macl` — TCC sandbox extension (which apps are allowed to access this document without prompting)
- `com.apple.rootless` — appears on some SIP-protected files as a belt-and-suspenders marker

```bash
xattr -l suspicious_download.dmg        # list all xattrs with values
xattr -d com.apple.quarantine file.app  # strip quarantine (caution: this is what attackers do)
```

---

### sudo, the admin group, and privilege escalation

#### The admin group as sudoers

On macOS, membership in the `admin` group grants `sudo` access via `/etc/sudoers`, which contains:

```
%admin  ALL = (ALL) ALL
```

That line gives every member of the `admin` group the ability to run any command as any user with password authentication. You can verify your group memberships:

```bash
id                          # shows uid, gid, and all supplementary groups
groups                      # just the group names
dscl . -read /Groups/admin  # who is in the admin group (Directory Services)
```

`/etc/sudoers` itself is immutable to non-root: `sudo visudo` is the safe editor (it validates syntax before saving). The actual sudoers file is at `/private/etc/sudoers`; `/etc/sudoers` is a symlink. Additional rules can be dropped in `/etc/sudoers.d/`.

> 🔬 **Forensics note:** On a compromised system, look for unauthorized entries in `/etc/sudoers` and `/etc/sudoers.d/`, unexpected members of the `admin` or `wheel` groups (`dscl . -read /Groups/admin GroupMembership`), and setuid binaries. These are the three primary privilege persistence vectors on macOS.

#### dscl and Directory Services

macOS account management flows through `opendirectoryd` and the Directory Services framework, not `/etc/passwd`. While `/etc/passwd` and `/etc/group` exist for POSIX compatibility, they are not the authoritative source — `dscl .` (the local node) is:

```bash
dscl . -list /Users                         # all local users
dscl . -read /Users/bronty13 NFSHomeDirectory UniqueID PrimaryGroupID
dscl . -list /Groups                        # all local groups
dscl . -read /Groups/admin GroupMembership  # admin group members
```

---

### "Operation not permitted" vs "Permission denied"

This is one of the most important diagnostic distinctions on macOS, and one that trips up nearly every Windows-to-macOS migrant.

| Error | errno | Source | Meaning |
|-------|-------|--------|---------|
| `Permission denied` | `EACCES (13)` | VFS/filesystem | POSIX mode bits or ACL deny entry blocked the operation |
| `Operation not permitted` | `EPERM (1)` | Kernel / SIP / TCC | SIP, BSD flag, or TCC refused the operation |

The critical rule: **`Operation not permitted` appears even with `sudo` when SIP or TCC is the gatekeeper.** This confuses users who expect `sudo` to be omnipotent:

```bash
sudo rm /System/Library/CoreServices/Finder.app
# → rm: /System/Library/CoreServices/Finder.app: Operation not permitted
# SIP blocked it; sudo didn't help.

sudo chown root ~/Documents/file.txt
# → chown: ~/Documents/file.txt: Operation not permitted
# → If this is a TCC issue (Terminal doesn't have Full Disk Access), sudo won't help either.
```

**Diagnostic sequence for a blocked operation:**

```bash
# 1. Check POSIX permissions and flags
ls -lO@ /path/to/file

# 2. Check ACLs
ls -le /path/to/file

# 3. Check if path is SIP-protected
ls -lOd /path/to/  # look for 'restricted' flag

# 4. Check xattrs including com.apple.rootless
xattr -l /path/to/file

# 5. If none of the above: TCC issue
# → System Settings > Privacy & Security > Full Disk Access
# → Verify that Terminal (or your tool) has the relevant TCC permission
# → Check /var/db/tccd/ (requires root) or use `tccutil`
```

> 🪟 **Windows contrast:** On Windows, `Access denied` (error 5) covers what macOS splits into two separate errno values. The equivalent of macOS's `EPERM` from SIP is Windows' `Access denied` when the protected system process (`wdFilter.sys` / Windows Resource Protection) blocks an operation — but Windows surfaces these with the same error code as a POSIX denial. macOS's split makes diagnosis faster once you know the distinction.

---

## Hands-on (CLI & GUI)

### Reading the full permission picture

```bash
# Everything in one pass: mode, flags, ACLs, xattrs
ls -lO@e /path/to/target

# Decode what each element means:
# -rw-r--r--   → POSIX: owner rw, group r, other r
# @            → extended attributes present (check with xattr -l)
# +            → ACL present (already shown by -e)
# uchg         → BSD flag: user immutable
# 0: ...       → ACE index 0 (first in evaluation order)
```

### Finding files with unusual permissions

```bash
# Find world-writable files (potential security issue)
find /usr/local -perm -002 -type f 2>/dev/null

# Find files with ACLs in your home directory
ls -leR ~ 2>/dev/null | grep -A5 "^\-\|^d"   # verbose; use sparingly

# More targeted: find files that have the @ (xattr) or + (ACL) indicator
ls -lR ~ 2>/dev/null | grep "[+@]"

# Find files with any BSD flags set
ls -lRO ~ 2>/dev/null | grep -v "^total\|^d\|^-[a-z-]*  \+[0-9]"  # crude but effective
# Better:
find ~ -flags +uchg,+schg,+hidden 2>/dev/null    # files with immutable or hidden flags
```

### The /etc/sudoers chain

```bash
# View effective sudoers configuration (as root)
sudo visudo -c         # check for syntax errors
sudo cat /etc/sudoers
sudo ls /etc/sudoers.d/

# See what sudo rules apply to you
sudo -l                # lists your effective sudo privileges
```

---

## Labs

### Lab 1: ACL mechanics — set, test, inherit, remove

This lab creates a test directory tree and walks through the ACL lifecycle.

```bash
# Setup
mkdir -p /tmp/acl-lab/{subdir,files}
touch /tmp/acl-lab/files/{alpha.txt,beta.txt}
echo "test content" > /tmp/acl-lab/files/alpha.txt
```

**Step 1 — Add a deny ACE and verify it blocks the owner:**
```bash
chmod +a "user:$(whoami) deny write" /tmp/acl-lab/files/alpha.txt
ls -le /tmp/acl-lab/files/alpha.txt
# Should show: 0: user:bronty13 deny write

echo "new content" >> /tmp/acl-lab/files/alpha.txt
# → zsh: /tmp/acl-lab/files/alpha.txt: operation not permitted
# Even though you are the POSIX owner with rw permissions, the ACL deny fires first.
```

**Step 2 — Add an allow ACE before the deny (position 0) and see who wins:**
```bash
chmod +a# 0 "user:$(whoami) allow write" /tmp/acl-lab/files/alpha.txt
ls -le /tmp/acl-lab/files/alpha.txt
# 0: user:bronty13 allow write   ← evaluated first: ALLOW, stop
# 1: user:bronty13 deny write    ← never reached

echo "new content" >> /tmp/acl-lab/files/alpha.txt    # succeeds now
```

**Step 3 — Inheritance on a directory:**
```bash
chmod +a "group:staff allow read,write file_inherit,directory_inherit" /tmp/acl-lab/subdir/
ls -le /tmp/acl-lab/subdir/

touch /tmp/acl-lab/subdir/newfile.txt
ls -le /tmp/acl-lab/subdir/newfile.txt
# The new file inherits the ACE from its parent directory — confirm 'group:staff allow read,write' appears
mkdir /tmp/acl-lab/subdir/nested
ls -le /tmp/acl-lab/subdir/nested/
# The subdirectory also inherits, and will propagate further (no limit_inherit set)
```

**Step 4 — Remove all ACLs and clean up:**
```bash
chmod -N /tmp/acl-lab/files/alpha.txt    # removes all ACEs
ls -le /tmp/acl-lab/files/alpha.txt      # no ACE lines; no '+' in mode string
rm -rf /tmp/acl-lab/
```

---

### Lab 2: chflags immutability — lock, test, unlock

> ⚠️ **ADVANCED / DESTRUCTIVE:** This lab makes a file immutable. If you accidentally run `chflags uchg` on a file you need to modify, run `chflags nouchg <file>` to unlock it. If you set `schg` (system immutable), you need `sudo chflags noschg` to clear it. Do NOT run these on system directories or with `-R` on broad paths.

```bash
# Create a test file
echo "original content" > /tmp/flagtest.txt
ls -lO /tmp/flagtest.txt
# -rw-r--r--          bronty13  staff  ...  /tmp/flagtest.txt
#             (no flags — empty column)

# Set user immutable
chflags uchg /tmp/flagtest.txt
ls -lO /tmp/flagtest.txt
# -rw-r--r-- uchg  bronty13  staff  ...  /tmp/flagtest.txt

# Try to modify (as yourself — the owner)
echo "modified" >> /tmp/flagtest.txt
# → zsh: /tmp/flagtest.txt: operation not permitted
# Even as the owner, with write permissions, uchg blocks all writes.

# Try to delete
rm /tmp/flagtest.txt
# → rm: /tmp/flagtest.txt: Operation not permitted

# Try with sudo
sudo rm /tmp/flagtest.txt
# → rm: /tmp/flagtest.txt: Operation not permitted
# sudo doesn't bypass uchg! The flag is checked BEFORE the effective-root bypass.

# Now clear the flag and verify write works
chflags nouchg /tmp/flagtest.txt
echo "modified" >> /tmp/flagtest.txt    # succeeds
cat /tmp/flagtest.txt                   # → "original content\nmodified"

# Set schg (system immutable) — requires sudo to set AND to clear
sudo chflags schg /tmp/flagtest.txt
ls -lO /tmp/flagtest.txt
# -rw-r--r-- schg  bronty13  staff  ...

sudo chflags noschg /tmp/flagtest.txt   # clear it before moving on
rm /tmp/flagtest.txt
```

**The Finder "Locked" checkbox:**
```bash
# Re-create and simulate what Finder does
touch /tmp/finder-lock-test.txt
chflags uchg /tmp/finder-lock-test.txt

# Open Finder, navigate to /tmp, Get Info on finder-lock-test.txt
# You'll see the "Locked" checkbox is checked — it reflects the uchg flag.
# Unchecking it in Finder runs chflags nouchg.

chflags nouchg /tmp/finder-lock-test.txt
rm /tmp/finder-lock-test.txt
```

---

### Lab 3: Diagnosing a permission-vs-TCC error

This lab walks you through systematically identifying *why* an operation is blocked.

```bash
# Scenario: you're trying to list ~/Library/Messages/ and getting an error
ls ~/Library/Messages/

# Case A: Permission denied
# → POSIX mode bits are wrong. Check: ls -lOd ~/Library/Messages/
# → Fix: chmod u+rx ~/Library/Messages/ (if appropriate)

# Case B: Operation not permitted (even with sudo)
# → TCC is blocking access to ~/Library/Messages/ (it requires Full Disk Access)
# → Diagnostic:
ls -lOd ~/Library/Messages/    # check for restricted flag (unlikely on user dirs)
xattr -l ~/Library/Messages/   # check for com.apple.macl
# → TCC fix: System Settings > Privacy & Security > Full Disk Access > add Terminal

# Test whether TCC is the issue by checking what tccd says:
sudo /usr/bin/sqlite3 "/private/var/db/tccd/TCC.db" \
  "SELECT client, auth_value, auth_reason FROM access WHERE service='kTCCServiceSystemPolicyAllFiles';"
# Lists apps with Full Disk Access grants (auth_value=2=allowed, 0=denied)
```

**Build a full permission audit of any file:**
```bash
# Comprehensive one-liner for any mystery file:
TARGET="/path/to/mystery/file"
echo "=== POSIX + Flags ==="
ls -lO "$TARGET"
echo "=== ACLs ==="
ls -le "$TARGET"
echo "=== Extended Attributes ==="
xattr -l "$TARGET"
echo "=== Parent directory ==="
ls -leO "$(dirname "$TARGET")"
echo "=== SIP status ==="
csrutil status
```

---

## Pitfalls & gotchas

**1. ACL `deny` does NOT automatically override POSIX `allow` — position matters.**
Placing a deny ACE after an allow ACE for the same principal does nothing — the allow fires first and evaluation stops. Always check ACE positions with `ls -le`.

**2. `chmod -R 755` blows away ACLs if you're not careful.**
`chmod` with `-R` on a tree that has ACLs will change mode bits but ALSO strip ACLs if the tree has any `+a` entries conflicting with the new mode. Use `chmod -R u+rX,go=rX` (symbolic, not octal) to avoid touching ACL inheritance. Better: `find + chmod` per file type to avoid surprises.

**3. `cp` strips ACLs and flags unless you use `-p` or `-a`.**
```bash
cp file.txt backup.txt        # loses ACLs, flags, xattrs
cp -p file.txt backup.txt     # preserves mode, timestamps, xattrs (incl. ACLs)
cp -a file.txt backup.txt     # same as -p but also handles symlinks/special files
ditto --noextattr src/ dst/   # strip xattrs intentionally; note: also strips ACLs
ditto src/ dst/               # preserves xattrs, ACLs, resource forks
```
For forensic copies, `ditto` (without `--noextattr`) or `rsync -aHAX` are the right choices.

**4. `uchg` defeats `sudo rm`.**
This surprises every experienced admin the first time. Root's bypass of POSIX checks does NOT bypass BSD flags. You must first clear the flag (`sudo chflags nouchg file`) before you can delete it.

**5. Home directory ACLs look weird in `ls -le` output.**
The `group:everyone deny delete` entry on `~` is intentional — set by the OS. It is NOT an error. Removing it is safe but leaves your home directory deleteable by any user with write access to `/Users/`.

**6. ACE rights are fine-grained but not composable the way you think.**
`allow read` on a directory means list contents; it does NOT grant traverse. `allow search` grants traverse. Many people set `allow read` expecting to be able to `cd` into the directory — they also need `allow search` (or `execute` works as an alias for search on directories).

**7. The `@` and `+` indicators in `ls -l` are easily missed.**
Train yourself to always run `ls -lO@e` rather than bare `ls -l` when diagnosing access issues. The difference between `-rw-r--r--` and `-rw-r--r--@+` is invisible to most users and explains hours of confusion.

**8. Quarantine xattr persistence through zip/unzip.**
`com.apple.quarantine` survives `zip` compression on macOS but is stripped by `unzip` on many Linux systems. If you're building a tool that cares about quarantine status, test the round-trip — the xattr may not be where you expect it after extraction.

---

## Key takeaways

- macOS has **three distinct layers** of filesystem access control: POSIX mode bits, NFSv4 ACLs, and BSD file flags. Each evaluates independently, in order. All three can deny an operation that the others would permit.
- **ACL evaluation is positional, not priority-based.** The first matching ACE wins, regardless of whether it allows or denies. Placement is correctness.
- **BSD flags operate below root**. `uchg` and `schg` block even `sudo rm`. They are the closest macOS equivalent to NTFS attribute flags — and the primary mechanism behind the Finder "Locked" checkbox.
- **`restricted` is the SIP flag.** Its presence in `ls -lO` output marks OS-protected paths. It cannot be cleared while SIP is active.
- **`Operation not permitted` ≠ `Permission denied`.** The former signals SIP or TCC; the latter signals POSIX/ACL. Diagnosing the wrong layer wastes time.
- **The admin group = sudo access** via `/etc/sudoers`'s `%admin ALL=(ALL) ALL` entry. Group membership is the primary privilege boundary for interactive macOS users.
- **Forensics:** flags, ACLs, and xattrs survive `cp -p` and `ditto` but NOT bare `cp` or cross-volume FAT copies. Use block-level imaging or `ditto`/`rsync -aHAX` to preserve the full permission picture.

---

## Terms introduced

| Term | Definition |
|------|-----------|
| POSIX mode bits | The 12-bit owner/group/other rwx field on every inode; the foundational filesystem permission layer |
| ACL (Access Control List) | An ordered list of ACEs (Access Control Entries) that augment POSIX permissions on macOS using NFSv4-style semantics |
| ACE (Access Control Entry) | A single rule in an ACL: principal + allow/deny + rights + optional inheritance flags |
| NFSv4 ACL | The ACL style macOS uses — ordered, positional evaluation, rich rights vocabulary — distinct from POSIX.1e draft ACLs used on Linux |
| `chmod +a` | macOS extension to `chmod` for adding ACEs to a file's ACL |
| `ls -le` | `ls` long format with ACL display |
| `ls -lO` | `ls` long format with BSD flag display |
| BSD file flags | inode-level flags set by `chflags`: `uchg`, `schg`, `hidden`, `restricted`, etc. |
| `uchg` (user immutable) | BSD flag making a file unmodifiable by anyone, including the owner; clearable by owner or root |
| `schg` (system immutable) | BSD flag requiring root to clear; survives normal sudo; effectively requires SIP-off or recovery mode |
| `restricted` | BSD flag set by the OS on SIP-protected paths; cannot be cleared while SIP is active |
| `sunlnk` | BSD flag preventing deletion of a directory itself while allowing creation/deletion of its contents |
| `hidden` | BSD flag hiding a file from Finder and `ls` without `-a` |
| umask | Octal complement mask applied at file creation time to strip permission bits |
| setuid | Mode bit causing file to execute as its owner rather than the calling user |
| setgid | Mode bit causing file to execute as its group; on directories, causes new files to inherit the directory's group |
| sticky bit | Mode bit on directories preventing users from deleting files they don't own |
| `EPERM` | errno 1 — "Operation not permitted" — returned by SIP, BSD flags, and some TCC blocks |
| `EACCES` | errno 13 — "Permission denied" — returned by POSIX mode bit or ACL deny |
| TCC | Transparency, Consent & Control — the daemon (`tccd`) enforcing per-app privacy permissions |
| SIP (System Integrity Protection) | macOS kernel feature protecting OS-owned paths from modification, even by root |
| `com.apple.quarantine` | Extended attribute recording download provenance; triggers Gatekeeper on first launch |
| `dscl` | Directory Services command-line utility; the authoritative interface to macOS user/group data |
| `visudo` | Safe `sudoers` editor that validates syntax before committing |
| traversal bit | The execute bit on a **directory**, controlling whether processes can reference items inside it |

---

## Further reading

- `man chmod`, `man chflags`, `man ls`, `man umask`, `man stat`, `man sudo`, `man sudoers` — the definitive local references; all still accurate on macOS 26
- [Apple: File System Details — ACLs and Inheritance](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemDetails/FileSystemDetails.html)
- [Eclectic Light Company: Permissions and ACLs](https://eclecticlight.co/2022/02/16/permissions-and-acls/) — Howard Oakley's practical walkthrough with `ls -le` examples
- [Eclectic Light Company: Tackling problems with permissions, ACLs and other access controls](https://eclecticlight.co/2023/04/11/tackling-problems-with-permissions-acls-and-other-access-controls/) — diagnosis flowchart
- [Eclectic Light Company: Permissions, privacy and security: who's in control?](https://eclecticlight.co/2025/02/20/permissions-privacy-and-security-whos-in-control/) — modern (2025) overview of all layers together
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — authoritative source on SIP, TCC, and the Secure Enclave; updated for each major macOS release
- [HackTricks: macOS SIP](https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-sip.html) — security researcher's angle on SIP internals and bypass history
- Related lessons: [[04-filesystem-layout-and-domains]], [[08-security-architecture]], [[09-spotlight-metadata-and-xattrs]], [[05-launchd-and-the-launch-system]]
