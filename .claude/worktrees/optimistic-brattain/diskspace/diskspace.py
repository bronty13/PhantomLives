#!/usr/bin/env python3
"""
diskspace.py — Mac Disk Space Reporter
Version : 1.0.0
Author  : PhantomLives
Requires: Python 3.6+, macOS (uses the POSIX `df` command)

Shows total, used, and free disk space for every mounted volume,
with an ASCII progress bar and human-readable byte units.
"""

# ---------------------------------------------------------------------------
# Version identifier — bump this using semantic versioning (MAJOR.MINOR.PATCH)
#   MAJOR: breaking change or significant rewrite
#   MINOR: new feature added in a backward-compatible way
#   PATCH: bug fix or minor internal change
# ---------------------------------------------------------------------------
__version__ = "1.0.0"

import shutil       # stdlib: disk_usage() reads a mount point's capacity info
import subprocess   # stdlib: used to shell out to the `df` command
import sys          # stdlib: sys.exit() and sys.stderr for error reporting


# ---------------------------------------------------------------------------
# bytes_to_human(n)
#   Converts a raw byte count into a compact, human-readable string.
#   Iterates through size units in ascending order (B → KB → MB → GB → TB),
#   dividing by 1024 each step until the value fits within a single unit.
#   Falls through to PB (petabytes) for extremely large values.
#
#   Example:  1_073_741_824  →  "  1.00 GB"
# ---------------------------------------------------------------------------
def bytes_to_human(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        # If the value is less than 1024 in the current unit, we've found
        # the best fit — format it with two decimal places and return.
        if abs(n) < 1024.0:
            return f"{n:7.2f} {unit}"
        # Otherwise divide by 1024 to step up to the next unit.
        n /= 1024.0
    # Only reached for values >= 1024 TB (i.e., petabyte-scale disks).
    return f"{n:.2f} PB"


# ---------------------------------------------------------------------------
# bar(used, total, width=30)
#   Renders a fixed-width ASCII progress bar representing disk utilisation.
#   '#' characters fill the proportion of used space; '-' fills the rest.
#   The bar is wrapped in square brackets so it prints like: [####------]
#
#   Guard against division-by-zero when total == 0 (e.g. empty loop device).
#
#   Example: bar(25, 100, width=10)  →  "[##--------]"
# ---------------------------------------------------------------------------
def bar(used, total, width=30):
    # Calculate how many '#' chars represent the used fraction of the bar.
    # Integer truncation is intentional — we never show a bar as "full"
    # unless the volume actually is full.
    filled = int(width * used / total) if total > 0 else 0

    # Construct the bar string: filled portion + empty portion + brackets.
    return "[" + "#" * filled + "-" * (width - filled) + "]"


# ---------------------------------------------------------------------------
# get_volumes()
#   Discovers all mounted disk volumes by parsing the output of `df -Pl`.
#     -P  POSIX output format: guaranteed column layout across macOS versions
#     -l  local filesystems only: skips network mounts (NFS, SMB, etc.)
#
#   For each discovered mount point the function:
#     1. Filters out macOS pseudo/internal volumes that aren't useful to
#        report on (swap, firmware volumes, boot preboot partitions, etc.)
#     2. Calls shutil.disk_usage() to get accurate byte-level capacity data
#        directly from the OS (more reliable than parsing df's block counts).
#     3. Skips any volume we lack read permission for rather than crashing.
#
#   Returns a list of tuples: [(mount_path, device_name, disk_usage), ...]
# ---------------------------------------------------------------------------
def get_volumes():
    # Run `df -Pl` and capture its stdout as a plain text string.
    result = subprocess.run(
        ["df", "-Pl"],
        capture_output=True,  # redirect both stdout and stderr into the result
        text=True             # decode bytes → str using the default locale
    )

    # Split into individual lines; strip leading/trailing whitespace first
    # to avoid a spurious empty string at the end of the list.
    lines = result.stdout.strip().splitlines()

    volumes = []

    # Skip lines[0] — that is the df header row (Filesystem, 512-blocks, …).
    for line in lines[1:]:
        parts = line.split()

        # A well-formed df line has at least 6 fields:
        #   [0] Filesystem  [1] 512-blocks  [2] Used  [3] Available
        #   [4] Capacity%   [5] Mounted on
        # Fewer than 6 means the line is malformed or a continuation — skip it.
        if len(parts) < 6:
            continue

        filesystem = parts[0]   # e.g. /dev/disk3s5
        mount = parts[5]        # e.g. /System/Volumes/Data

        # Filter out macOS-internal volumes that are not meaningful to end users:
        #   /dev              — character/block device entries, not real mounts
        #   /private/var/vm   — macOS swap/virtual-memory backing store
        #   /System/Volumes/VM — APFS container used for swap on Apple Silicon
        if any(mount.startswith(p) for p in ("/dev", "/private/var/vm", "/System/Volumes/VM")):
            continue

        try:
            # shutil.disk_usage() returns a named tuple: (total, used, free)
            # all in bytes.  This is more accurate than df's block counts
            # because it reflects the true available space after reservations.
            usage = shutil.disk_usage(mount)
        except PermissionError:
            # Some system volumes (e.g. /System/Volumes/Hardware) may deny
            # read access to non-root users — skip them silently.
            continue

        volumes.append((mount, filesystem, usage))

    return volumes


# ---------------------------------------------------------------------------
# print_report(volumes)
#   Formats and prints the disk space report to stdout.
#   For each volume it shows:
#     - Mount path  (truncated with "..." prefix if longer than 28 chars)
#     - Device node (e.g. /dev/disk3s5)
#     - ASCII usage bar + percentage
#     - Total / Used / Free in human-readable units
# ---------------------------------------------------------------------------
def print_report(volumes):
    print()
    print(f"  Mac Disk Space Report  (v{__version__})")
    print("  " + "=" * 62)

    for mount, filesystem, usage in volumes:
        # Calculate the percentage of space currently in use.
        # Guard against division-by-zero for theoretical zero-size volumes.
        pct = (usage.used / usage.total * 100) if usage.total > 0 else 0

        # Truncate very long mount paths so they don't break the layout.
        # Keep the last 25 characters prefixed with "..." for recognisability.
        label = mount if len(mount) <= 28 else "..." + mount[-25:]

        print(f"\n  Mount : {label}")
        print(f"  Device: {filesystem}")

        # The bar gives an immediate visual indication of how full the volume is.
        print(f"  {bar(usage.used, usage.total)}  {pct:5.1f}% used")

        # Print raw capacity numbers in human-readable form.
        print(f"  Total : {bytes_to_human(usage.total)}")
        print(f"  Used  : {bytes_to_human(usage.used)}")
        print(f"  Free  : {bytes_to_human(usage.free)}")

    print()
    print("  " + "=" * 62)
    print()


# ---------------------------------------------------------------------------
# main()
#   Entry point — orchestrates volume discovery and report rendering.
#   Exits with a non-zero status code if no volumes could be found so that
#   the script can be safely used in shell pipelines or cron jobs.
# ---------------------------------------------------------------------------
def main():
    volumes = get_volumes()

    # If get_volumes() returned an empty list, something is wrong with the
    # environment (e.g. df not found, or all volumes were filtered/denied).
    if not volumes:
        print("No volumes found.", file=sys.stderr)
        sys.exit(1)  # non-zero exit signals failure to calling processes

    print_report(volumes)


# ---------------------------------------------------------------------------
# Standard Python entry-point guard.
# Ensures main() only runs when this file is executed directly, NOT when it
# is imported as a module by another script.
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    main()
