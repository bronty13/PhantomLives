# Molly — Roadmap & Ideas

> A living brainstorm of where Molly could go next, captured at 2026-05-22 right after v1.8.1 shipped. Nothing on this page is a commitment — it's a curated menu so future-Robert (or future-Claude) has somewhere to start when Sallie says "what's next?"
>
> Things deliberately **not** pitched are documented in [`OUT_OF_SCOPE.md`](OUT_OF_SCOPE.md) (multi-user, cloud sync, web/mobile companion, code-signing certs, hardware integration, shareable accountant logins). Respect those defaults; only re-open if real evidence emerges.

## How to read this doc

Each idea carries two quick tags:

- **Effort** — `S` (< 1 day), `M` (1–3 days), `L` (~1 week), `XL` (2+ weeks). Rough; the actual scope conversation happens when we plan.
- **Flavor** — 🟢 direct business utility · 🟡 nice-to-have · 🔵 soft delight.

If an idea graduates from this doc, it earns a proper `PHASE_N_*.md` plan (see `PHASE_8_PARSERS.md` as the model). If an idea is killed, it moves to `OUT_OF_SCOPE.md` with a one-line rationale so we don't relitigate it.

---

## 📣 Phase 9 candidate: Promo Scheduler (the explicit ask)

The Promos tab today is a **tracker** — Sallie posts to Reddit/X/IG/TikTok manually, then comes back to Molly to log it. The natural next step is the inverse: **compose in Molly first, post out from Molly**. Closest reference apps in the niche are Postpone (Reddit), TweetDeck, Buffer, Hootsuite, Later — most refuse adult content via TOS, so there's room.

Three honest paths:

### A. Reminder-pattern scheduler  *(low risk, fastest to ship)*
Sallie composes a promo, picks a date+time, hits **Schedule**. Molly creates an occurrence in the existing reminder engine. When the time fires, the reminder card has a **🚀 Post now** button — copies the body to her clipboard, opens the platform in the browser, then waits for her to tap **✓ Posted** to mark it complete.

- **Effort:** S–M
- **What changes:** Promos schema gains `state: draft | scheduled | posted | archived` + `scheduled_for: timestamp`. Reuses the cadence engine, Reminders view, ConfirmButton. New calendar grid view of scheduled promos.
- **Tradeoff:** posting stays manual — Molly nudges, but Sallie clicks "Post" on the actual platform.

### B. Composer + library scheduler  *(recommended sweet spot)*
Everything in A, plus:

- **Platform-aware composer** — live character counter for X (280), title-length for Reddit, hashtag density warning for IG, etc.
- **Hashtag library** per platform, with click-to-insert. Builds itself over time from successful past promos.
- **Templates** — reusable shells with placeholders auto-filled from a chosen clip: `{clip_title}` `{price}` `{clip_url}`. E.g. *"every Monday — CoC clip drop template."*
- **Thumbnail attachment** — pick an image, store inline as a SQLite BLOB. Same pattern as Molly's Log and Customer history attachments.
- **Variants** — for casual A/B testing: 2–3 body variations per promo; Molly rotates which one is suggested at fire time.
- **Re-promote helper** — a successful post can be cloned forward 30 / 60 / 90 days with a small variation in body.
- **Performance tracking** — extend the Promos record with a `notes_after_post` field for "what worked / what didn't," eventually graphing per-platform hashtag/time success rates.

- **Effort:** M–L
- **Why this one:** matches Molly's local-only / single-user / no-credentials philosophy and covers ~90% of what Postpone gives you, *without* the API-token security surface. Sallie still hits the platform's own Post button — but everything before that point happens inside Molly.

### C. Full API scheduler
Reddit OAuth + actual auto-publish via API. (X API is restrictive + paid; IG / TikTok / OnlyFans don't expose this for adult content at all.)

- **Effort:** XL — credential storage, refresh tokens, rate limits, banned-subreddit handling, "what if my post auto-publishes while I'm asleep and Reddit removes it?" pain.
- **Verdict:** **probably not worth it.** Diminishing returns vs B. Single user, no team need. Re-open if Reddit specifically starts paying back the integration cost.

### Recommendation
Ship **B** as **Phase 9**. The data model is a small evolution of the current Promos schema; the new screens are a composer + a calendar; the execution flow piggybacks on the existing reminder engine. This is the largest single-feature uplift on the roadmap.

---

## 💖 Customer Intelligence

Surface the customer data Molly already has — it's been sitting in `customer_sales` waiting to be aggregated.

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **LTV column + sort** on the Customer list | S | 🟢 | `SUM(total_cents)` already exists per customer (the 💖 pill in the editor); just promote it to the list view + add as sort key. |
| **Whales dashboard card** on Home | S | 🟢 | Top-N customers by lifetime spend, with a tap-through to the customer card. |
| **Cooling-customer alerts** | S | 🟢 | "These 12 customers haven't bought in 60 days." One-click "add follow-up reminder" → drops into Reminders bound to that customer. |
| **Birthday / anniversary reminders** | S | 🔵 | New optional date fields on the customer card. Schedule engine + reminder UI already does the rest. |
| **Customer cohorts** | M | 🟡 | "Customers acquired in January are now worth $X on average" — spots where good customers come from. |
| **Subscription / membership tracker** | M | 🟢 | Recurring-revenue customers as a distinct flavor of sale, with renewal-due dates surfaced in Reminders. |

---

## 🎬 Clip / Content Workflow

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **Per-clip ROI** | M | 🟡 | Add `production_cost_cents` + `production_minutes` to the Clip model. Reports show ROI = sales / cost per clip. |
| **Multi-platform sync status** | M | 🟡 | Per-clip checklist of "live on C4S ✓, IWC ✗, OF ✓" with date-posted. Surfaces gaps. |
| **Production planner** | L | 🟡 | Pipeline view (idea → scripted → shot → edited → uploaded). Drag clips through stages. |
| **Outfit / prop inventory** | M | 🔵 | What was worn in each clip; linked to clips. *"I haven't done a video in the red lingerie in 3 months."* |
| **Series tracker** | S | 🔵 | Clips grouped by series with a numbered sequence + "next episode due" reminder. |

---

## 💰 Money / Business Intelligence

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **Tax-time dashboard** | M | 🟢 | Quarterly estimated-tax calculator, categorized expense rollup, accountant-friendly export. Builds on the existing Reports CSV export. |
| **Monthly revenue goal** | S | 🟢 | Set a target in Settings → see a progress bar on Home; soft 🎉 when crossed. |
| **Forecast** | S | 🟡 | 90-day trailing trend → projected end-of-month. |
| **Bank-statement reconciliation** | M | 🟡 | Import a bank CSV, auto-match against recorded income; flag missing entries. |
| **Per-platform commission rates** | S | 🟡 | Record what each site takes (C4S 40%, OF 20%, etc.); Reports show net vs gross by platform. |

---

## 🛡 Content Protection

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **DMCA notice generator** | M | 🟢 | Standard template with Sallie's address, clip details, infringing URL auto-filled. Copy-to-clipboard. |
| **Piracy tracker** | S–M | 🟢 | Log pirate sites where stuff is found; track DMCA-notice status (sent / removed / ignored). New tab or a sub-view under Reports. |
| **Reverse image search workflow** | S | 🔵 | One-click "search Google Images for this thumbnail" per clip. |
| **Watermark consistency reminder** | S | 🔵 | Settings option to gently remind on every upload that the watermark belongs. |

---

## 🌷 Wellbeing (extending Molly's Log)

Molly's Log is already the journal surface. These add light structure without making it feel like work.

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **Mood tracker** | S | 🔵 | Soft 5-emoji scale on each log entry. Show a mood trend chart on Home. |
| **Hours worked** | S | 🔵 | Quick timer per persona. Sunday rollup ("you worked 22 CoC hours + 18 PoA hours this week 🌷"). |
| **Burnout warning** | S | 🔵 | *"You've worked 7 days in a row — maybe take a soft day? 🌸"* Gentle, dismissible. |
| **Boundary log** | S | 🟢 | Private log of clients who pushed boundaries + what was said. Linked from the customer card. |

---

## 📥 More Imports (already scoped in PHASE_8_PARSERS.md)

Surfaced here so they don't get forgotten. The plan is in [`PHASE_8_PARSERS.md`](PHASE_8_PARSERS.md); a sample CSV from each site is the blocker.

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **OnlyFans CSV importer** | M | 🟢 | Sibling of the new C4S Store flow. |
| **IWantClips CSV importer** | M | 🟢 | Same shape. |
| **ManyVids CSV importer** | M | 🟢 | Same shape. |
| **LoyalFans CSV importer** | M | 🟢 | Same shape. |

Unlocks per-clip ROI + per-platform commission tracking with real data.

---

## ✨ Personalization / Delight

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **Seasonal saying packs** | S | 🔵 | Autumn / spring / holiday / Sallie's-birthday saying sets that swap automatically based on the calendar. |
| **Sound on check-off** | S | 🔵 | Soft chime when a reminder is completed. Toggleable in Settings. |
| **Custom persona emoji** | S | 🔵 | Pick the icon shown next to CoC / PoA / Sa chips. |
| **Achievement badges in Molly's Log** | M | 🔵 | Tiny keepsakes — *"first $100 day," "first VIP," "1,000 clips imported."* Shown as little stickered entries. |

---

## 🛍️ Suggested slates

Three opinionated bundles to choose between. Treat as starting points, not boxes — mix and match.

### 🌸 Q2 sweet spot — *high value, low risk* (~3 weeks)
1. **Promo Scheduler flavor B** — biggest single-feature uplift in this whole doc.
2. **Customer Intelligence** — LTV column + Whales dashboard + Cooling alerts (the data already exists in `customer_sales`).
3. **Tax-time dashboard** — quarterly estimate, categorized export.

### 🌷 Ambitious next phase — *bigger build* (~6 weeks)
1. Promo Scheduler + production planner together — *whole content pipeline from idea → promo*.
2. **OnlyFans + IWC CSV importers** — close out Phase 8.
3. **Per-clip ROI** using imports + production-cost field.
4. **Per-platform commission rate tracking**.

### 🦋 Soft / personal touches — *scattered cute work* (~1 week)
1. **Mood tracker + burnout warning** in Molly's Log.
2. **Birthday / anniversary reminders** on customers.
3. **Seasonal saying packs**.
4. **Sound on check-off** + **custom persona emoji**.
5. **Achievement badges**.

---

## Process notes

- **A new feature lands here first**, then earns a proper `PHASE_N_*.md` plan if it graduates. The plan doc is what we hand to Claude (or future-Robert) when work begins.
- **A killed feature moves to `OUT_OF_SCOPE.md`** with one line of rationale. Keeps this doc focused on live possibilities.
- **A shipped feature moves to `CHANGELOG.md`** under its version heading. Keeps the roadmap aspirational, not historical.
- **When in doubt, ask Sallie.** This whole doc is one opinionated curator's view; the only signal that matters is what would make Sallie's actual day better.
