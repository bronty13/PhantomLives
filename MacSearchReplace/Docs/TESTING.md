# Testing MacSearchReplace

## Quick run

```bash
./Tests/smoke.sh
```

Expect 16 tests in ~5 seconds. Output is `[ok]` per test plus a summary.

## What's covered

| # | Test ID                          | What it verifies |
|---|----------------------------------|------------------|
| 1 | `literal-search-multi-file`      | `snr search` finds a literal in multiple files |
| 2 | `regex-search-anchored`          | `-r` flag enables regex (`^delta`) |
| 3 | `case-insensitive-search`        | `-i` flag is case-insensitive |
| 4 | `replace-literal-multi-file`     | `snr replace` mutates files correctly |
| 5 | `backup-session-created`         | A backup session appears under Application Support |
| 6 | `dry-run-no-mutation`            | `--dry-run` does not modify the file (checksummed) |
| 7 | `regex-replace-backref`          | `$1` backreferences expand in replace text |
| 8 | `include-glob-filter`            | `--include '*.txt'` skips other extensions |
| 9 | `exclude-glob-filter`            | `--exclude '*.log'` skips matched extension |
| 10| `snrscript-v1-roundtrip`         | A v1 `.snrscript` runs end-to-end |
| 11| `snrscript-v2-per-step-roots`    | A v2 step's `roots` override scope |
| 12| `touch-updates-mtime`            | `snr touch` advances `mtime` |
| 13| `pdf-search`                     | `snr pdf` finds text in a generated PDF (skipped if `cupsfilter` missing) |
| 14| `restore-from-backup`            | `snr restore <session>` reverts a replace |
| 15| `help-text-renders`              | `snr --help` prints help |
| 16| `unknown-subcommand-exits-nonzero`| Bad subcommand exits with non-zero code |

Each test uses fresh fixtures in `mktemp -d /tmp/snr-smoke.XXXXXX` and the
trap cleans them up on exit.

## Library unit tests (Xcode required)

```bash
swift test
```

These use Apple's [`swift-testing`](https://github.com/apple/swift-testing)
framework, which ships with full Xcode but **not** with the bare Command
Line Tools. On a CLT-only system you'll see:

```
error: no such module 'Testing'
```

That's expected. The unit-test sources serve as executable documentation of
intent until a CI runner with Xcode is in place.

## Adding a new test to the smoke harness

1. Pick a unique `test-id` (kebab-case).
2. Append a section to `Tests/smoke.sh`:

   ```bash
   # NN. <description>
   mkdir -p "$WORK/tNN"
   …setup…
   "$SNR" <subcommand> … >/dev/null 2>&1 || true
   <assertion> && ok "test-id" || bad "test-id" "<reason>"
   ```

3. Re-run `./Tests/smoke.sh` and ensure your new test appears in the summary.

## Manual GUI smoke

After every release-candidate build:

1. `open build/MacSearchReplace.app`
2. Find: type `TODO`; Look in: this repo; press Return → results appear streaming.
3. Press **Stop** mid-stream → Find button reappears.
4. Open **▸ Filters** → toggle `*.swift` only → Find again → fewer hits.
5. Replace `TODO` with `DONE` → confirm `Replace All` → check a file.
6. **Search → Open Backup Folder** → confirm a session was written.
7. Quit. Relaunch. Recent Folder menu lists the project.

## Continuous integration (future)

Recommended GitHub Actions matrix:

| Step          | Runner            |
|---------------|-------------------|
| `swift build` | macos-14, macos-15|
| `Tests/smoke.sh` | same           |
| `swift test`  | macos-14 (full Xcode) — gated |

Not yet wired up. The smoke harness is designed to be the first CI gate
without needing a paid plan or self-hosted runner.
