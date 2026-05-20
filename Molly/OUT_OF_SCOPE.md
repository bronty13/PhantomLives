# Out of Scope (for now)

> Things considered + intentionally not built. Captured so we don't relitigate them every release.

## Code-signing certs (Apple Developer ID + Windows EV)

**Decision:** out of scope.

**Why:** Molly is distributed to exactly one person (Sallie) by exactly one developer (Robert). Apple's Developer ID program is $99/year, Windows EV code-signing certs are $200+/year. On first launch the unsigned `.dmg` / `.exe` triggers a one-time "right-click → Open" (Mac) or "More info → Run anyway" (Windows) prompt — that's a 5-second hassle once per major install, not a daily friction.

Updater signing (via minisign) is already wired and verifies every auto-update — that protects Sallie from any future MITM on the update channel, which is the actually-important safety property.

**Trigger to reconsider:** if Molly ever ships to a third person, or if Windows SmartScreen tightens further and blocks `Run anyway`.

## Multi-user / cloud sync

**Decision:** out of scope, permanently.

**Why:** the entire app is built around a single-user assumption. Persona switching, persona-tinted theming, the gift-tone copy, the export-to-Slack data flow — all of these would need rethinking for multi-user. There's no benefit; Sallie has one machine + one Molly.

If she ever needs to move machines, the `Settings → Data → Export everything` zip + dev-import on the new machine is the migration path.

## Frontend test suite

**Decision:** deferred (not out of scope), but not blocking 1.0.

**Why:** TypeScript catches the majority of type-level mistakes. The Rust unit tests cover the bridge contract (camelCase) and backup safety. The remaining bug surface (React rendering, state transitions) historically gets caught in real use faster than tests would catch it — Sallie's bug-bash on v0.6.0 found the camelCase issue, the loading-state UX, and the missing CHANGELOG entry, all in one afternoon.

If we ever ship to a wider audience, add Playwright e2e tests covering the persona-switch round trip and the import wizard.

## Mobile / web companion

**Decision:** out of scope.

**Why:** Tauri's frontend would technically port to a web app or a Capacitor mobile shell, but the desktop-first interactions (file picks for receipts, large bar charts, the sayings hero card) all degrade on mobile. The export → Slack flow already serves the "I need to see my data away from my desk" use case.

## Hardware integration / camera ingest

**Decision:** out of scope.

**Why:** Molly tracks what the creator already has. Capturing new media → MasterClipper. Tracking new sales → site-side exports. Molly is the dashboard, not the production pipeline.

## "Multi-tenant" features (sharing, accountant access, etc.)

**Decision:** out of scope.

**Why:** The reports CSV export already covers "send my numbers to my accountant once a quarter." Building shareable links or readonly views would explode the surface area for no measurable user gain.

---

**This list isn't a moratorium — it's a checkpoint.** If real evidence emerges that one of these would actually move the needle for Sallie, we revisit. Otherwise, every hour spent here is an hour not spent on something she'd actually notice.
