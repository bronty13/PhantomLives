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

**Decision (1.7.3):** **partially lifted.** Pure-function unit tests are now in via vitest:

- `src/lib/money.test.ts` — `parseMoney`, `fmtMoney`
- `src/lib/phone.test.ts` — `formatUSPhone`, `isValidUSPhone`, `usPhoneDigits`
- `src/lib/cadence.test.ts` — `nextOccurrencesAfter` across all six cadence kinds + date helpers
- `src/lib/uid.test.ts` — `formatDateKey`

44 tests, runs in ~100ms via `pnpm test`. `run-tests.sh` chains cargo + vitest, so `./run-tests.sh` runs everything.

**Still out of scope:**

- **Component / rendering tests** for the React views (`CustomerEditor`, `MollysLogView`, `AdhocIncomeView`, etc.). These have a lot of state-machine surface and would benefit from `@testing-library/react`, but the cost (jsdom env, mock Tauri IPC, mock SQL plugin) is real and the historical bug rate has been bearable without them.
- **E2E**. The original "Playwright if we ever ship to a wider audience" rationale still holds.

The original v0.6.0 rationale (typecheck + Rust contract + real use bug-bash) still does most of the work; we just plugged the cheapest hole.

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
