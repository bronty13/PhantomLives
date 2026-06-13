---
title: "Shell fundamentals: pipes, redirection, jobs"
part: P03 CLI
est_time: 60 min read + 45 min labs
prerequisites: [part-01-architecture/05-launchd-and-the-launch-system, part-01-architecture/06-processes-mach-and-xpc]
tags: [macos, zsh, shell, cli, pipes, redirection, jobs, signals, environment]
---

# Shell fundamentals: pipes, redirection, jobs

> **In one sentence:** Everything Unix text tooling does flows through three file descriptors, a handful of redirection operators, and a job-control model that zsh inherited from POSIX — understanding the plumbing lets you compose arbitrarily powerful one-liners and write scripts that behave correctly under failure.

## Why this matters

A forensics professional who knows how data flows through a shell can build investigation pipelines that would take hours in a GUI in seconds at the prompt. You can capture every byte written to stderr by a misbehaving process, background a 12-hour evidence acquisition and safely close the terminal, kill a runaway daemon without touching the GUI, and chain twenty tools together with zero temp files. You can also reason about what an attacker's shell script actually did by reading the redirections and signal traps. None of that is possible if you treat pipes as magic.

macOS ships **zsh** as the default interactive shell since Catalina and through macOS 26 Tahoe. Zsh is a strict superset of POSIX sh and overlaps heavily with bash in scripting; this lesson notes zsh-specific extensions where they differ meaningfully from bash.

## Concepts

### File descriptors: the real plumbing

Every Unix process inherits a table of open file descriptors (FDs). Three are wired by convention at process start:

| FD | Name   | Default destination        | C constant  |
|----|--------|---------------------------|-------------|
| 0  | stdin  | keyboard (terminal)       | `STDIN_FILENO`  |
| 1  | stdout | terminal display          | `STDOUT_FILENO` |
| 2  | stderr | terminal display          | `STDERR_FILENO` |

FDs are just integers into the kernel's per-process open-file table (see `proc_fdlist` in the XNU source, or observe them with `lsof -p $$`). When you run `ls > out.txt`, the shell calls `open("out.txt", O_WRONLY|O_CREAT|O_TRUNC)`, gets back some FD number, then `dup2(fd, 1)` to replace stdout before `execve(ls)`. The binary never "knows" it's writing to a file — it just writes to FD 1.

> 🔬 **Forensics note:** `lsof -p <pid>` shows every file descriptor of a running process, including pipes (`type=PIPE`), sockets, and deleted-but-held-open files (`(deleted)` suffix). A process holding a deleted log file open is a common anti-forensics pattern — the file is gone from the directory but the data is still accessible via `/proc/<pid>/fd/<n>` on Linux (macOS equivalent: `lsof` + read from `/dev/fd/<n>` in the process's namespace, or use `dtrace` to intercept writes).

### Redirection operators

```
cmd > file          # truncate file, write stdout
cmd >> file         # append stdout
cmd 2> file         # redirect stderr only
cmd 2>> file        # append stderr
cmd &> file         # stdout + stderr → file  (zsh/bash; NOT POSIX sh)
cmd > file 2>&1     # POSIX-portable equivalent of &>
cmd < file          # feed file as stdin
cmd 2>&1 1>/dev/null  # stdout to /dev/null, stderr to where stdout WAS  ← ordering matters
```

**Operator ordering is left-to-right and matters enormously.** The common mistake is writing `cmd 2>&1 > file` when you mean `cmd > file 2>&1`. At parse time: `2>&1` means "make FD 2 point to the same place FD 1 currently points" — if FD 1 is still the terminal at that moment, stderr goes to the terminal, not the file.

```zsh
# WRONG — stderr still goes to terminal
cmd 2>&1 > file

# RIGHT — stderr follows stdout into the file
cmd > file 2>&1

# Zsh shorthand (equivalent, less portable)
cmd &> file
```

**Discard output:**
```zsh
cmd > /dev/null 2>&1   # silence everything
cmd 2>/dev/null        # silence only errors
```

**Here-documents** (`<<EOF`) feed a multi-line string as stdin without a file:
```zsh
sqlite3 ~/evidence.db <<SQL
  SELECT path, mtime FROM files
  WHERE mtime > strftime('%s','now','-7 days');
SQL
```
The delimiter (`EOF`, `SQL`, anything) ends the here-doc. Quote the delimiter to suppress variable substitution: `<<'EOF'` treats the body as literal text.

**Here-strings** (`<<<`) feed a single string as stdin — a zsh/bash extension:
```zsh
base64 -d <<< "SGVsbG8gd29ybGQ="
# Hello world

# Handy for feeding a variable into a command expecting stdin
wc -w <<< "$long_variable"
```

**Noclobber** — zsh's `setopt noclobber` prevents accidental overwrites with `>`. Use `>|` to force-overwrite when noclobber is set. Interactive zsh on macOS 26 often has noclobber active in curated `.zshrc` setups; be aware.

### Pipes: the kernel buffer between processes

```
cmd_a | cmd_b | cmd_c
```

The shell creates an anonymous pipe (kernel ring buffer, typically 64 KB on macOS) between each pair. `cmd_a`'s stdout FD is the write end; `cmd_b`'s stdin FD is the read end. All three processes run **concurrently** — `cmd_b` starts consuming output before `cmd_a` finishes. The pipeline exits with the status of the **last** command by default; `set -o pipefail` (zsh: `setopt pipefail`) changes this to the status of the first failing command — essential for reliable scripts.

```zsh
# Without pipefail — hides grep failure
cat nonexistent_file | grep pattern
echo $?  # 0  (grep's exit code, not cat's)

# With pipefail — correct error propagation
setopt pipefail
cat nonexistent_file | grep pattern
echo $?  # non-zero
```

> 🪟 **Windows contrast:** PowerShell pipes **objects**, not byte streams. `Get-Process | Where-Object CPU -gt 10` passes `[Process]` .NET objects with typed properties. There's no equivalent of `grep` because you filter on object properties, not text. This is genuinely more powerful for structured data, but it means PowerShell scripts can't directly interoperate with Unix tools that expect text. macOS `|` is always bytes; structure is imposed by convention (fields separated by whitespace or delimiters), not the pipe itself.

**Named pipes (FIFOs)** are on-disk rendezvous points that behave like anonymous pipes:
```zsh
mkfifo /tmp/evidence.fifo
sha256sum /tmp/evidence.fifo &   # reader waits
dd if=/dev/rdisk4 > /tmp/evidence.fifo  # writer feeds it
```

### Command substitution and process substitution

**Command substitution** `$(...)` runs a command and substitutes its stdout inline:
```zsh
today=$(date +%Y%m%d)
echo "Report: $today"

# Nested
echo "Lines in biggest log: $(wc -l < $(ls -S /var/log/*.log | head -1))"
```

The old backtick form `` `cmd` `` is equivalent but doesn't nest cleanly; prefer `$(...)`.

**Process substitution** `<(cmd)` (zsh and bash) makes a command's stdout appear as a file-like path — the shell creates a pipe or `/dev/fd/N` and substitutes the path. This lets commands that demand file arguments consume streaming output:

```zsh
# diff two live outputs without temp files
diff <(ls /Applications) <(ssh remotehost ls /Applications)

# comm requires sorted input; sort on-the-fly
comm -23 <(sort file_a) <(sort file_b)

# Feed a process's stdout into another that expects a filename
shasum -a 256 <(curl -s https://example.com/archive.tar.gz)
```

Output process substitution `>(cmd)` routes stdout into a process:
```zsh
# Tee to gzip without a temp file
cat huge_log | tee >(gzip > huge_log.gz) | grep ERROR
```

> 🔬 **Forensics note:** Process substitution is implemented via `/dev/fd/N` (a FD-backed pseudo-file) on macOS. If you see `/dev/fd/63` as a filename in a process's argument list in `ps` or a `dtrace` trace, a parent shell is using process substitution. This is useful when reading attacker scripts — `<(cmd)` means the attacker is consuming streaming data without writing temp files, making artifact recovery harder.

### Exit codes and sequencing

Every command produces an integer **exit code** (0–255). `0` = success; non-zero = failure. The last exit code is `$?`.

```zsh
grep -q "root" /etc/passwd && echo "found"   # run right side only on success
rm /tmp/stale.lock || echo "lock already gone"  # run right side only on failure
cmd1 ; cmd2    # run sequentially regardless of exit codes
```

**Grouping:**
```zsh
# Curly braces: same shell, no subshell, must have semicolons/newlines
{ cmd1; cmd2; cmd3; } > combined.log

# Parens: subshell — directory changes, variables, setopt don't leak out
(cd /tmp && tar xf archive.tar)
pwd  # still in original directory
```

A subshell `( )` is literally a `fork()` — a copy of the current shell. Changes inside don't affect the parent. Braces `{ }` are just syntactic grouping within the current process; they share the parent's environment.

`$?` traps:
```zsh
cmd
if [[ $? -ne 0 ]]; then echo "failed"; fi

# Idiomatic — check directly
if ! cmd; then echo "failed"; fi
```

### Job control

When you append `&`, the shell forks the command, prints `[1] 12345` (job number + PID), and returns the prompt immediately. The child runs in the background — same session, same terminal, but not the foreground process group.

```zsh
sleep 600 &      # [1] 78234
jobs             # [1]  + running   sleep 600
fg %1            # bring job 1 to foreground
Ctrl-Z           # suspend foreground job → SIGTSTP
bg %1            # resume it in background
kill %1          # send SIGTERM to job 1
```

`jobs -l` shows PIDs alongside job numbers. The `%` prefix addresses jobs; `%1` = job 1, `%%` = current job, `%+` = most recent, `%-` = second-most-recent.

**`disown`** — removes a job from the shell's job table without killing it. The process lives on; the shell won't send it `SIGHUP` when the session ends:
```zsh
long_process &
disown %1
# or: disown -h %1  (keep in table but suppress SIGHUP)
```

**`nohup`** — wraps a command to ignore `SIGHUP` before exec'ing it; also redirects stdin to `/dev/null` and stdout/stderr to `nohup.out` if not already redirected:
```zsh
nohup ./long_acquisition.sh > /tmp/acq.log 2>&1 &
```

> 🔬 **Forensics note:** `disown` and `nohup` are common in attacker post-exploitation scripts to daemonize a callback without writing a launchd plist. The process has no controlling terminal (`/dev/null` or absent TTY, visible in `ps -o tty`), `ppid` = 1 (reparented to launchd after shell exits), and no job-table entry. Look for suspicious processes with `ppid=1`, no TTY, and unusual binary paths in `ps aux` or `sudo eslogger exec`.

**launchd vs nohup/disown — the fundamental difference:**

| Mechanism | Persistence across reboot | Auto-restart on crash | Managed by OS | Logging integration |
|---|---|---|---|---|
| `nohup` / `disown` | No (process dies on reboot) | No | No | Manual |
| launchd plist | Yes (loaded at login/boot) | Configurable (`KeepAlive`) | Yes | Unified Log |

`nohup`/`disown` is session-level persistence (survives terminal close, dies on reboot). launchd is OS-level persistence. For anything that must survive a reboot, you need a plist in `~/Library/LaunchAgents/` or `/Library/LaunchDaemons/`. See [[05-launchd-and-the-launch-system]] for the full picture.

### Signals

Signals are asynchronous notifications delivered to a process by the kernel, another process, or the user via a terminal driver.

| Signal | Number | Default action | Common trigger |
|---|---|---|---|
| `SIGHUP`  | 1  | Terminate | Controlling terminal closed; also used to "reload config" by convention |
| `SIGINT`  | 2  | Terminate | Ctrl-C at terminal |
| `SIGQUIT` | 3  | Core dump  | Ctrl-\ at terminal |
| `SIGKILL` | 9  | Terminate (unblockable) | `kill -9`; cannot be caught or ignored |
| `SIGTERM` | 15 | Terminate | Default `kill`; catchable — process can clean up |
| `SIGTSTP` | 18 | Stop (suspend) | Ctrl-Z |
| `SIGCONT` | 19 | Resume | `bg` / `fg` |
| `SIGUSR1` | 30 | Terminate (default) | Application-defined; e.g. rotate log |

```zsh
kill PID          # SIGTERM (15) — polite, catchable
kill -9 PID       # SIGKILL — immediate, no cleanup, cannot be ignored
kill -HUP PID     # SIGHUP — common "reload" convention (nginx, sshd, etc.)
kill -l           # list all signal names

killall -TERM Safari   # signal by process name
pkill -f "my_script"   # signal by regex on full command line
```

> ⚠️ **ADVANCED / DESTRUCTIVE:** `kill -9` does not allow the process to flush buffers, close database connections, or remove lock files. On a running SQLite database, `-9` can leave the WAL in an inconsistent state. Always try `SIGTERM` first; wait a few seconds; only escalate to `-9`.

**Trapping signals in scripts:**
```zsh
#!/bin/zsh
cleanup() {
    echo "Cleaning up temp files..."
    rm -f /tmp/my_workdir.*
}
trap cleanup EXIT          # runs on any exit
trap "echo interrupted" INT  # Ctrl-C handler
```

### Environment vs shell variables

**Shell variables** exist only in the current shell process:
```zsh
my_var="hello"
bash -c 'echo $my_var'   # empty — not in bash's environment
```

**Environment variables** are passed to child processes via `execve`'s `envp[]` array:
```zsh
export my_var="hello"
bash -c 'echo $my_var'   # hello

# export and assign in one step
export EDITOR="nvim"

# Inline for a single command (doesn't modify current environment)
LANG=C grep -r pattern /logs/   # grep sees LANG=C; your shell's LANG unchanged
```

`env` — print the full environment (or prefix a command with a modified one):
```zsh
env                           # print all exported variables
env -i PATH=/usr/bin cmd      # run cmd with a clean environment
env | grep -i proxy           # inspect proxy settings
```

`printenv VAR` — print a single variable. `set` (no args in zsh) — print all shell variables including unexported ones.

### PATH and `path_helper`

`PATH` is a colon-delimited list of directories searched left-to-right when you type a command name without a path. First match wins.

On macOS, the system populates the initial `PATH` via `/usr/libexec/path_helper`, which is invoked from `/etc/zprofile` (sourced for every login shell):

1. Reads `/etc/paths` (Apple's base paths: `/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`)
2. Reads one-path-per-line files in `/etc/paths.d/` (Homebrew, TeX, Xcode tools, etc. drop files here)
3. Appends any existing `PATH` entries that weren't already listed

**The reorder trap:** `path_helper` runs from `/etc/zprofile`, which is sourced *after* `~/.zshenv` but *before* `~/.zshrc`. If you prepend custom paths in `.zshenv`, `path_helper` will reorder them to the tail. Correct practice: build your custom `PATH` in `~/.zshrc`, which runs *after* `path_helper`.

```zsh
# ~/.zshrc — correct placement
export PATH="$HOME/.local/bin:$HOME/go/bin:$PATH"

# Inspect the resolution chain
which python3
type python3        # shows function/alias/builtin vs external binary
whence -v python3   # zsh-specific; more detail than type
```

Add third-party tools system-wide:
```zsh
echo '/opt/forensic-tools/bin' | sudo tee /etc/paths.d/forensic-tools
# Takes effect in new shells
```

> 🔬 **Forensics note:** Attackers who compromise a user account often prepend a malicious directory to `PATH` in `.zshrc`, `.zshenv`, or `.bash_profile` — or drop a file in `/etc/paths.d/` if they have root. Auditing these files and comparing `which` output to expected binary hashes is a standard persistence check. See [[part-01-architecture/08-security-architecture]] for the SIP protections on system paths.

### Quoting rules

macOS zsh (and bash) undergo **word splitting** and **glob expansion** on unquoted variables. This causes silent bugs.

```zsh
files="a.log b.log c.log"
wc -l $files      # word splits → three arguments ✓ here
wc -l "$files"    # one argument: the string "a.log b.log c.log" ✗ probably wrong

path="My Documents/file.txt"
cat $path         # word splits → tries to cat "My" then "Documents/file.txt" ✗
cat "$path"       # correct ✓
```

**Quoting reference:**

| Form | Substitution | Glob | Word split | Use case |
|---|---|---|---|---|
| `'literal'` | None | No | No | Pass exact string; protect special chars |
| `"$var"` | Yes (`$`, `` ` ``, `\`) | No | No | Normal variable expansion without splitting |
| `$'...'` | C escape sequences (`\n`, `\t`, `\x41`) | No | No | Embed control characters, ANSI escapes |
| `` `cmd` `` / `$(cmd)` | Command sub | After | After | Capture command output |
| Unquoted `$var` | Yes | Yes | Yes | Intentional glob or split (rare; be explicit) |

```zsh
# $'...' — embed a literal newline in a variable
IFS=$'\n' read -ra lines <<< "$multiline"

# Protect a tilde
echo '$HOME'        # literal $HOME
echo "$HOME"        # expands to /Users/you
```

**Glob expansion order** in zsh: brace expansion `{a,b}` → tilde expansion `~` → parameter/command/arithmetic expansion → word splitting → filename generation (globbing `* ? [...]`) → quote removal. This order is fixed; you can't reorder it by placement.

### `tee`: broadcast a stream

```zsh
# Write to file AND pass through to stdout (for further piping)
./acquisition.sh | tee /tmp/acq.log | grep -i "error"

# Append mode
cmd | tee -a existing.log | next_cmd

# Fan out to multiple destinations
cmd | tee file1 file2 >(gzip > file3.gz)
```

> 🔬 **Forensics note:** `tee` is the standard way to capture tool output while watching it live during an investigation. `| tee evidence.log | tail -f` or simply `| tee evidence.log` (and watch the terminal) guarantees the log is written atomically alongside live output.

### `xargs`: feed arguments at scale

`xargs` reads newline-delimited tokens from stdin and constructs command invocations, working around ARG_MAX (the OS limit on total argument list size — ~2 MB on macOS, exposed as `getconf ARG_MAX`).

```zsh
# Basic: find large files, delete them
find /tmp -size +100M | xargs rm

# -0 and -print0: null-delimited — required for filenames with spaces/newlines
find . -name "*.log" -print0 | xargs -0 gzip

# -I{}: placeholder substitution
find . -name "*.jpg" -print0 | xargs -0 -I{} convert {} {}.png

# -n N: max N arguments per invocation
echo {1..20} | xargs -n 5 echo

# -P N: parallel workers — N simultaneous processes
find /evidence -name "*.E01" -print0 | xargs -0 -P 4 -I{} sha256sum {}

# Combine -P with a shell function (requires -I and bash/zsh -c)
find . -name "*.pcap" -print0 | xargs -0 -P 8 -I{} zsh -c 'tshark -r {} -T fields -e frame.number | wc -l; echo {}'
```

**`-P` parallelism note:** `-P 0` means "as many as possible" on GNU xargs (Linux `findutils`); on macOS's BSD `xargs`, `-P 0` is an error — use `-P $(sysctl -n hw.logicalcpu)` for a portable "use all cores" pattern.

```zsh
# Portable core count for -P on macOS
CORES=$(sysctl -n hw.logicalcpu)
find /big_dataset -name "*.log" -print0 | xargs -0 -P "$CORES" -I{} process_log {}
```

> 🪟 **Windows contrast:** PowerShell's `ForEach-Object -Parallel` (PS 7+) achieves similar parallelism but operates on objects in a runspace pool, not forked OS processes. On macOS, `xargs -P` forks real processes — shared memory, real file descriptors, and actual OS-level parallelism on Apple Silicon's performance cores. GNU `parallel` (installable via `brew install parallel`) is a drop-in replacement with more control over throttling, retries, and progress display.

---

## Hands-on (CLI & GUI)

### Map every redirection form to its mechanism

```zsh
# Inspect FDs of a shell with lsof
lsof -p $$ | head -20
# You'll see FDs 0/1/2 pointing to /dev/ttys00N (your terminal)

# Confirm redirection changes the FD target
exec 3> /tmp/fd3_test.txt   # open FD 3 for writing
echo "hello FD 3" >&3
exec 3>&-                    # close FD 3
cat /tmp/fd3_test.txt
```

### Capture stderr separately and both together

```zsh
# Run a command that writes to both streams
{ echo "stdout line"; echo "stderr line" >&2; } > /tmp/out.txt 2> /tmp/err.txt
cat /tmp/out.txt  # stdout line
cat /tmp/err.txt  # stderr line

# Combine (order matters):
{ echo "stdout"; echo "stderr" >&2; } > /tmp/both.txt 2>&1
cat /tmp/both.txt  # both, interleaved in arrival order
```

### Explore the PATH construction chain

```zsh
cat /etc/paths
ls /etc/paths.d/
cat /etc/zprofile   # shows path_helper invocation

# See what path_helper emits for the current environment
/usr/libexec/path_helper -s   # -s = sh syntax; -c = csh syntax

# Find duplicate entries in PATH (common after .zshrc re-sources)
echo "$PATH" | tr ':' '\n' | sort | uniq -d
```

### Signal a process and observe state transitions

```zsh
# Start a background loop
(while true; do sleep 1; done) &
bgpid=$!
echo "PID: $bgpid"

ps -o pid,state,comm -p $bgpid   # state: S (sleeping)

kill -TSTP $bgpid                 # suspend
ps -o pid,state,comm -p $bgpid   # state: T (stopped)

kill -CONT $bgpid                 # resume
ps -o pid,state,comm -p $bgpid   # state: S again

kill -TERM $bgpid
wait $bgpid 2>/dev/null           # reap zombie
echo "Gone"
```

### Parallel checksum with xargs -P

```zsh
# Create test files
mkdir /tmp/xargs_test && cd /tmp/xargs_test
for i in {1..16}; do dd if=/dev/urandom bs=1m count=10 of=file_$i.bin 2>/dev/null; done

# Sequential
time find . -name "*.bin" -print0 | xargs -0 shasum -a 256 > /tmp/seq_hashes.txt

# Parallel — 8 workers (adjust to hw.logicalcpu)
time find . -name "*.bin" -print0 | xargs -0 -P 8 shasum -a 256 > /tmp/par_hashes.txt

# Verify results are equivalent
sort /tmp/seq_hashes.txt > /tmp/seq_sorted.txt
sort /tmp/par_hashes.txt > /tmp/par_sorted.txt
diff /tmp/seq_sorted.txt /tmp/par_sorted.txt && echo "Results match"
```

---

## 🧪 Labs

### Lab 1: Multi-stage forensic pipeline

Build a pipeline that finds recently modified files, checksums them, and produces a timestamped report — all without temp files.

```zsh
# Goal: find files modified in the last 24h under /private/var/log,
# compute SHA256, sort by hash, capture stdout+stderr to a dated log,
# and display a live count as it runs.

REPORT=~/Downloads/shell-lab/$(date +%Y%m%d_%H%M%S)_file_hashes.txt
mkdir -p ~/Downloads/shell-lab

{
  echo "# File hash report generated $(date)"
  echo "# Host: $(hostname)"
  find /private/var/log -type f -newer /private/var/log -mtime -1 -print0 2>/dev/null \
    | xargs -0 -P 4 shasum -a 256 2>/dev/null \
    | sort
} 2>&1 | tee "$REPORT" | wc -l | xargs echo "Lines written:"

echo "Report saved to $REPORT"
```

What each piece does:
- `{ ... } 2>&1` — captures stderr from the brace group alongside stdout
- `tee "$REPORT"` — writes to file AND passes through
- `| wc -l | xargs echo` — counts lines and prints them
- `find ... -print0 | xargs -0 -P 4` — null-safe, 4-parallel checksums

### Lab 2: Background a long job, safely detach, and prove it survived terminal close

> ⚠️ **Lab setup:** This lab starts a background process and closes the terminal. Before starting, ensure you're working in a test directory. The `sleep` process is harmless and will self-terminate.

```zsh
# Step 1: start a job that logs its heartbeat
mkdir -p /tmp/bglab
(
  for i in {1..300}; do
    echo "$(date +%T) tick $i" >> /tmp/bglab/heartbeat.log
    sleep 2
  done
) &
bgpid=$!
echo "Started PID $bgpid"

# Step 2: disown it so the shell won't SIGHUP it on exit
disown $bgpid

# Step 3: verify it's running and disowned
jobs          # should show nothing (removed from table)
ps -p $bgpid  # process still exists

# Step 4: open a NEW terminal window/tab and confirm it's still running
# In the new terminal:
ps -p <bgpid>          # still there
tail -f /tmp/bglab/heartbeat.log   # Ctrl-C to stop watching

# Step 5: clean up
kill <bgpid>
rm -rf /tmp/bglab
```

**What to observe:** After the original shell exits, the process is reparented to launchd (PID 1). Its PPID changes from your shell's PID to 1. This is visible in `ps -o pid,ppid,comm`.

### Lab 3: Capture and triage stderr from a noisy tool

Scenario: a tool writes mixed stdout/stderr; you need stdout for downstream processing but want stderr in a separate audit log.

```zsh
mkdir -p /tmp/stderrlab

# Simulate a tool that mixes outputs
simulate_tool() {
  for i in {1..20}; do
    if (( i % 3 == 0 )); then
      echo "ERROR: item $i failed" >&2
    else
      echo "item_$i,$(( RANDOM % 1000 ))"
    fi
  done
}

# Capture: stdout → data file, stderr → error log, view errors live
simulate_tool > /tmp/stderrlab/data.csv 2> >(tee /tmp/stderrlab/errors.log >&2)

echo "--- Data rows: $(wc -l < /tmp/stderrlab/data.csv)"
echo "--- Error count: $(wc -l < /tmp/stderrlab/errors.log)"
cat /tmp/stderrlab/errors.log

# Cleanup
rm -rf /tmp/stderrlab
```

The `2> >(tee /tmp/stderrlab/errors.log >&2)` pattern: redirect stderr into a process substitution that tees it to a log file and also writes it to stderr (FD 2 of the outer shell) so you still see errors in your terminal.

---

## Pitfalls & gotchas

**`2>&1` order.** Already covered above, but it bears repeating because it causes subtle bugs even for experienced users. Always read redirections left-to-right; each one takes effect at the point it appears.

**Unquoted `$variable` near a glob.** `rm $dir/*` where `dir="/tmp/my dir"` expands to `rm /tmp/my dir/*` — two arguments, wrong result, possibly dangerous. Always quote: `rm "$dir/"*` (note: the glob itself must be outside the quotes).

**`xargs` on macOS is BSD, not GNU.** `-P 0` is invalid (use a number). `-i` (lowercase) is deprecated; use `-I{}`. Some GNU-specific flags (`--max-procs`, `--null`) have different syntax. If you rely on GNU extensions, `brew install findutils` gives you `gxargs`.

**`find -print0 | xargs` vs `find -exec`.** For very large file counts, `xargs -0` batches many files per `xargs` invocation (efficient). `find -exec cmd {} +` (note the `+` not `;`) is also batched and avoids the pipe entirely. `find -exec cmd {} \;` (semicolon) spawns one process per file — avoid for large trees.

**Jobs are session-local.** `jobs` only shows jobs of the *current shell*. A background job started in a different terminal tab is invisible to `jobs` in yours. Use `ps`, `pgrep`, or `lsof` to find processes across the session.

**`nohup` creates `nohup.out`.** If you don't redirect stdout, `nohup` writes to `nohup.out` in the current directory. This silently fills disks during long acquisitions. Always: `nohup cmd > /path/to/explicit.log 2>&1 &`.

**`kill %1` sends to the process group, not just the leader.** `kill -9 %1` kills the entire pipeline if the job is a pipeline. This is usually what you want, but be aware.

**`set -e` and pipelines.** In scripts, `set -e` (exit on error) does *not* catch failures in the middle of a pipeline without `set -o pipefail`. Use both together: `set -eo pipefail` at the top of every script.

**`path_helper` reordering.** Put `PATH` customizations in `.zshrc`, not `.zshenv`. See the PATH section above.

**Here-doc indentation.** `<<EOF` requires the closing delimiter at the start of the line with no leading whitespace. Use `<<-EOF` to allow leading tabs (not spaces) in the delimiter.

---

## Key takeaways

- File descriptors 0/1/2 are just integers in a table; redirection is `dup2()` before `execve()`.
- Redirection operators are left-to-right; `> file 2>&1` and `2>&1 > file` do different things.
- Pipes connect processes via kernel ring buffers; all stages run concurrently.
- `$(...)` substitutes output; `<(...)` makes output look like a file path.
- Exit codes propagate through `&&`/`||`; `set -o pipefail` makes them propagate through pipes.
- `&` backgrounds; `Ctrl-Z` suspends; `fg`/`bg`/`jobs` manage jobs; `disown` detaches from SIGHUP.
- `SIGTERM` is catchable (graceful); `SIGKILL` is not (immediate, no cleanup).
- Environment variables are inherited by child processes; shell variables are not.
- `path_helper` runs from `/etc/zprofile`; customize PATH in `.zshrc` to win the ordering battle.
- Quote variables with `"$var"` always unless you specifically want word splitting or glob expansion.
- `xargs -0 -P N` pairs with `find -print0` for null-safe, parallel bulk operations.

---

## Terms introduced

| Term | Definition |
|---|---|
| **File descriptor (FD)** | Integer index into a process's open-file table; 0=stdin, 1=stdout, 2=stderr |
| **Pipe** | Anonymous kernel buffer connecting one process's stdout to another's stdin |
| **Named pipe / FIFO** | On-disk rendezvous point for two processes (`mkfifo`) |
| **Here-document** | Inline multi-line stdin via `<<DELIM ... DELIM` |
| **Here-string** | Single-string stdin via `<<< "string"` (zsh/bash) |
| **Command substitution** | `$(cmd)` — substitutes command's stdout |
| **Process substitution** | `<(cmd)` / `>(cmd)` — exposes command I/O as a pseudo-file path |
| **Exit code** | Integer (0–255) returned by a process; 0 = success |
| **Job** | A process or pipeline managed by the shell's job-control system |
| **`disown`** | Remove a job from the shell's table, suppressing SIGHUP on shell exit |
| **`nohup`** | Run a command immune to SIGHUP; writes `nohup.out` if stdout unredirected |
| **SIGHUP** | Signal sent when controlling terminal closes; also used as "reload" convention |
| **SIGKILL** | Unblockable termination signal; no cleanup possible |
| **SIGTERM** | Default kill signal; catchable; allows graceful shutdown |
| **Environment variable** | Variable exported into child process's `envp[]` at exec |
| **`path_helper`** | `/usr/libexec/path_helper` — macOS utility that assembles PATH from `/etc/paths` + `/etc/paths.d/` |
| **Word splitting** | Shell splitting of unquoted expansions on IFS characters (default: space/tab/newline) |
| **Glob expansion** | Shell pattern matching: `*`, `?`, `[...]`, zsh extended globs `**` |
| **`tee`** | Write stdin to both stdout and a file simultaneously |
| **`xargs`** | Build and execute command lines from stdin tokens; `-0` for null-delimited, `-P` for parallel |
| **Subshell** | `( )` — fork of current shell; changes don't propagate to parent |
| **Process group** | Set of processes sharing a PGID; `kill %job` signals the whole group |

---

## Further reading

- `man zshmisc` — Zsh redirection and expansion operators (authoritative; `man zshbuiltins` for `jobs`/`disown`/`trap`)
- `man zshexpn` — the complete expansion reference including process substitution
- [Apple Platform Security Guide](https://support.apple.com/guide/security/welcome/web) — signal and process model in the security context
- Howard Oakley's Eclectic Light Company — search "shell" for macOS-specific investigations into process behavior and launchd interaction
- [[part-01-architecture/05-launchd-and-the-launch-system]] — launchd plists, the right way to achieve process persistence
- [[part-01-architecture/06-processes-mach-and-xpc]] — Mach ports, XPC, how processes actually communicate beyond pipes
- [[part-01-architecture/10-unified-logging-and-diagnostics]] — where shell-launched tools write their output in the Unified Log
- [Properly setting $PATH for zsh on macOS](https://gist.github.com/Linerre/f11ad4a6a934dcf01ee8415c9457e7b2) — community deep dive on the path_helper reorder problem
- `man xargs` (BSD) vs `gxargs --help` (GNU via `brew install findutils`) — note the flag differences
