# Security Review — Molly v1.0.0 → v1.7.3

> Focused security review of every code change shipped between
> `molly-v1.0.0` (commit `45ad014`, the gift release) and
> `molly-v1.7.3` (commit `3e6bed5`, the customer-record-expansion +
> Molly's-Log + test-coverage release).

**Date:** 2026-05-21
**Reviewer:** Conducted via the `/security-review` skill, sub-task
agent identified candidates and each candidate was filtered through a
parallel false-positive sweep. Final findings retained only at
confidence ≥ 8.

**Result: NO_FINDINGS.**

---

## Scope

Diff base: `git diff molly-v1.0.0..molly-v1.7.3 -- Molly/`.

### Rust

- `src-tauri/src/history.rs` (new — rusqlite BLOB I/O for customer history)
- `src-tauri/src/log.rs` (new — rusqlite BLOB I/O for Molly's Log)
- `src-tauri/src/lib.rs` (migrations + handler list + contract tests + migration smoke)
- `src-tauri/src/fsutil.rs` (new test only)
- `src-tauri/migrations/010_kinks.sql` through `015_mollys_log.sql` (six new migrations)
- `src-tauri/Cargo.toml` (added `rusqlite = "0.31"` with bundled SQLite)
- `src-tauri/tauri.conf.json` (`dragDropEnabled: false` on the window; version bumps)
- `src-tauri/capabilities/default.json` (unchanged surface — no new plugin permissions)

### TypeScript — data layer

- `src/data/customerHistory.ts` (new)
- `src/data/customerSales.ts` (new)
- `src/data/mollysLog.ts` (new)
- Modifications: `customers.ts`, `taxonomy.ts`, `income.ts`, `clips.ts`, `occurrences.ts`

### TypeScript — UI

- New: `MollysLog/MollysLogView.tsx`, `Customers/CustomerHistoryCard.tsx`, `Customers/CustomerSaleEditor.tsx`
- New components: `KinkChipPicker.tsx`, `MoneyInput.tsx`
- Modified: `Customers/CustomerEditor.tsx`, `Customers/CustomerListView.tsx`, `Income/AdhocIncomeView.tsx`, `Income/SiteIncomeWizard.tsx`, `Expenses/ExpenseListView.tsx`, `Expenses/RecurringExpensesView.tsx`, `Import/MasterClipperImport.tsx`, `Settings/SettingsView.tsx`, `Settings/TaxonomySettings.tsx`, `Calendar/CalendarView.tsx`, `Calendar/ClipDetail.tsx`, `Clips/ClipsListView.tsx`, `components/Sidebar.tsx`, `App.tsx`

### Static libs

- `src/lib/countries.ts`, `src/lib/usStates.ts`, `src/lib/phone.ts` (new; pure data/string manipulation)
- Tests: `src/lib/*.test.ts` (excluded from review per project policy)

---

## Threat model recap

Molly is a Tauri 2 desktop app distributed to **one user**, used on
**one machine**, with no network server, no auth, and no remote origin
feeding the bundled frontend. The frontend code is shipped inside the
app bundle; the only IPC boundary is the in-process Tauri bridge
between bundled JS and the Rust backend. The threat surface is
therefore:

1. **Malicious files** the user might accidentally open/attach.
2. **Malicious update payloads** — mitigated by minisign signatures on
   the auto-updater (`tauri-plugin-updater` validates against the
   pubkey embedded in `tauri.conf.json`).
3. **Bugs that could escalate** writes/reads outside the app's data
   directory (no in-app-input attacker can reach the Tauri commands
   without already controlling the JS frontend, which would itself
   require local code execution).

This shaped the review: standard "remote attacker" categories
(authentication bypass, SSRF, server-side injection) don't apply.
Local-attacker categories (path traversal beyond the dialog flow,
deserialization, etc.) were examined carefully.

---

## Findings by category

### SQL injection — none

Every query in the changed code uses positional parameters:

- All `tauri-plugin-sql` calls use `$1, $2, ...` placeholders. No
  template-string interpolation of user input into SQL anywhere in the
  diff (verified across `customerHistory.ts`, `customerSales.ts`,
  `mollysLog.ts`, and the extended `customers.ts` / `taxonomy.ts` /
  `income.ts`).
- `rusqlite` calls in `history.rs` / `log.rs` use `params![...]` with
  positional `?1, ?2, ...` placeholders. BLOBs are bound as `Vec<u8>`
  / `&[u8]` directly — no string-form embedding.
- The one apparent string-interpolated identifier is `${table}` in
  `taxonomy.ts::list/create/update/remove`. `table` is typed
  `'products' | 'interests' | 'kinks'` (literal union); the only
  callers are the three exported namespaces (`products`, `interests`,
  `kinks`), each passing its own hardcoded string. Not user-reachable.

### Command injection — none

No new `Command::new(...)`, `exec`, `spawn`, or shell invocation in
the diff. `fsutil.rs::reveal_in_file_browser` already existed at v1.0.0
and was untouched.

### Path traversal — none

`add_history_entry_with_attachment(src_path)`,
`download_history_attachment(target_path)`,
`add_log_entry_with_attachment(src_path)`, and
`download_log_attachment(target_path)` accept absolute paths from the
frontend without sandboxing — but the only call sites use
`@tauri-apps/plugin-dialog`'s `open()` / `save()`, which present an
OS-native file picker. Paths originate from the user's explicit
selection in a Finder/Explorer dialog, not from any external input.
Per the project's threat-model precedent, OS-dialog-mediated paths
are trusted.

A self-contained Tauri capability (`capabilities/default.json`) was
not modified by this release; the existing ACL keeps these custom
commands invokable only from the main window.

### XSS — none

No new use of `dangerouslySetInnerHTML`, `innerHTML =`, `outerHTML =`,
`eval`, `new Function`, or `setAttribute('on...')` in the diff. All
user-rendered values flow through standard JSX braces (auto-escape).
The pre-existing `RichTextNotes.tsx` (Tiptap) is unchanged in this
window. The Caveat-font journal-entry render in `MollysLogView.tsx`
displays `e.body` inside `<div className="whitespace-pre-wrap">
{e.body}</div>` — same auto-escape path; no HTML injection vector.

### Hardcoded secrets / weak crypto — none

The only key material in the diff is the minisign updater public key
in `tauri.conf.json::plugins.updater.pubkey`, which is public by
design. No private keys, API tokens, or session secrets introduced.
No new crypto primitives — auto-updater signing remains unchanged
(minisign Ed25519, validated by `tauri-plugin-updater`).

### RCE via deserialization — none

- BLOB reads in `read_history_blob` / `read_log_blob` return
  `Vec<u8>` and are written straight to disk via `fs::write`. No
  deserialization step in either direction.
- The frontend's `serde_json` use is limited to camelCase boundary
  structs (`HistoryEntryRef`, `LogEntryRef`, the unchanged
  `BackupRow`, `VerifyResult`, `Settings`, `ExportResult`,
  `AttachmentInfo`). All are simple POD; no untagged unions, no
  `serde(deserialize_with = ...)` hooks, no custom `Deserialize`
  impls.

### AuthN / AuthZ — N/A

Single-user desktop app, no auth surface introduced or modified.

### Sensitive data exposure — none

- Error messages in the new Tauri commands include the offending
  filesystem path (`format!("read {src_path}: {e}")`,
  `format!("write {target_path}: {e}")`). These reach the user as
  status text in the UI — not external logs, not third parties.
- No new logging of secrets, tokens, or PII to stdout/stderr beyond
  what v1.0.0 already did (`eprintln!` on backup failure).

---

## What was NOT reviewed (out of scope)

Per the `/security-review` policy:

- DoS / ReDoS / resource-exhaustion concerns.
- "Secrets stored on disk" (the SQLite DB itself contains user data,
  but Molly's at-rest encryption story is handled separately by the
  filesystem permissions of `~/Library/Application Support/`).
- Memory safety in Rust (impossible by language design).
- Findings in `*.test.ts` / `#[cfg(test)] mod tests` blocks.
- Markdown documentation files.
- Outdated third-party libraries (managed by separate process).

---

## Verdict

The 1.7.x release surface added a substantial amount of code —
~3,000 LoC across Rust + TypeScript — but introduced **no new
high- or medium-confidence exploitable vulnerabilities**. The patterns
established at v1.0.0 (parameterized SQL throughout, OS-dialog-mediated
file paths, no `dangerouslySetInnerHTML`, signed auto-updates) were
followed consistently in the new code.

This review is point-in-time and does not constitute a guarantee for
future commits. Re-run `/security-review` against the diff for any
future release before tagging.
