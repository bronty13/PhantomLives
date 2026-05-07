# Changelog

All notable changes to Timeliner are documented here. The version number is
auto-derived from git's commit count (`1.0.<count>`), so this log groups
changes by feature rather than by exact bundle version.

## 1.0.0 — Phase 1 MVP

Initial public build. Establishes the core domain model, the on-disk
database, the timeline UI, and the auto-backup-on-launch convention.

### Added

- **Cases** — CRUD with status (active / cold / closed) and pinning.
  Status reflected in sidebar icon and case-card badge.
- **Events** — date + optional end-date range, markdown description, source
  URL, four-level importance flag (low / medium / high / critical).
- **Tags** — hex-colored chips, per-event tagging via the editor sheet,
  filter pills in the timeline view, dedicated Tags settings tab.
- **People** — six built-in roles (suspect / victim / witness / attorney
  / detective / other) with customizable chip colors, per-event linking.
- **Vertical chronological timeline** — year/month section headers,
  importance pip indicator, tag and person chips, double-click to edit.
- **Filters** — date-range, tag set, importance set, plain-text query.
  All filters compose; "Clear" resets them in one click.
- **Cross-case search** — ranked across cases, events, people, tags.
- **Themes** — Default / Midnight / Ocean / Forest / Sunset / Rose, with
  a preview swatch in Settings → Themes.
- **Standalone HTML export** — single self-contained file per case (inline
  CSS + JS), drops at `~/Downloads/Timeliner/<Title>-<timestamp>.html`.
  XSS-escaped, no external dependencies.
- **Auto-backup-on-launch** — debounced (skip if last run < 5 min old),
  retention-trimmed, default location `~/Downloads/Timeliner backup/`,
  default 14-day retention. Verify-and-restore UI in Settings → Backup.
- **Custom app icon** — programmatically generated clock-and-pins icon via
  `Scripts/generate-icon.swift` at build time.
- **Settings scene** — seven tabs: General, Appearance, Themes, Tags,
  People Roles, Export, Backup.
- **Tests** — migration round-trips, Codable round-trips, search ranking,
  HTML export self-containment + XSS escaping, BackupService retention
  trim + auto-mkdir + sort order.
