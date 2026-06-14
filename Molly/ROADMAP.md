# Molly — Roadmap & Ideas

> A living brainstorm of where Molly could go next, last freshened 2026-05-23 after v1.17.1 shipped. Nothing on this page is a commitment — it's a curated menu so future-Robert (or future-Claude) has somewhere to start when Sallie says "what's next?"
>
> Things deliberately **not** pitched are documented in [`OUT_OF_SCOPE.md`](OUT_OF_SCOPE.md) (multi-user, cloud sync, web/mobile companion, code-signing certs, hardware integration, shareable accountant logins). Respect those defaults; only re-open if real evidence emerges.

## How to read this doc

Each idea carries two quick tags:

- **Effort** — `S` (< 1 day), `M` (1–3 days), `L` (~1 week), `XL` (2+ weeks). Rough; the actual scope conversation happens when we plan.
- **Flavor** — 🟢 direct business utility · 🟡 nice-to-have · 🔵 soft delight.

If an idea graduates from this doc, it earns a proper `PHASE_N_*.md` plan (see `PHASE_8_PARSERS.md` as the model). If an idea is killed, it moves to `OUT_OF_SCOPE.md` with a one-line rationale so we don't relitigate it.

---

## 🎉 Recently shipped (Phases 14 + 15)

Pulling these off the "what could we do" menu — they're real now. See `CHANGELOG.md` for the full details.

- **v1.15.0 (Phase 14)** — Bundle previews on the Publish wizard · 🎉 Holidays on the Calendar (18 US defaults) · 🏷️ Content tags (global taxonomy) on bundles + clips · per-day FanSite tags · three Calendar overlay toggles (FanSite tags / Clip tags / Reddit posts, per-persona).
- **v1.16.0** — Bundle-publish propagates tags onto the resulting clip row; content tags also flow into `info.md` + `Molly.log` inside the published ZIP.
- **v1.17.0 (Phase 15)** — 🔴 **Reddit** sidebar tab with five sub-sections: ✅ Today (daily to-do, quick-add chips) · 📌 Subreddits (33-sub CoC seed, star + verify + rotation + last-posted, filter+sort) · 📅 Post log (past or future-scheduled, bucketed by day relationship) · 💬 Captions (copy-to-clipboard library) · ⏱ Hours (clock-in/out, today/week/month rollup) + 🎁 Reward milestones in Settings.
- **v1.17.0 also** — 🎨 Dark mode (light / dark / system, OS-subscribed) + 🌼 licensed Paper Daisy font + dropped the unwanted weekly "CoC/PoA content release" default reminders.
- **v1.17.1** — Hotfix for the migration-hash crash introduced in v1.17.0.

That cleared the **🎁 / 🎉 / 🏷️ / 🔴 / 🎨 / ⏱ / 🎁-Rewards / Daily-to-do / Per-day-FanSite-tags / Calendar-overlays / Subreddit-tracker / Caption-bank** asks from the menu. What's left below is genuinely still on the table.

---

## 📣 Promo composer extensions (partially-shipped concept)

The 🔴 Reddit hub (v1.17.0) already gives Sallie subreddit tracking, the post log (with future-scheduled posts), and a caption library. The original Phase-10 Promo-Scheduler menu still has a few items worth doing — they layer on top of what's there now:

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **Platform-aware composer** for Captions | M | 🟢 | Live char counter for X (280), title-length for Reddit, hashtag-density warning for IG. Today Captions is just free text; this adds gentle guardrails when she's writing for a specific platform. |
| **Templates with clip placeholders** | M | 🟢 | Reusable shells: `{clip_title}` `{price}` `{clip_url}`. *"Monday CoC clip drop"* style. Save once, reuse 30+ times. |
| **Thumbnail attachment on a caption / post** | S | 🟡 | Pick an image, store inline. So the post log + caption bank can carry visual context too. |
| **Re-promote helper** | S | 🟡 | "Schedule again in 30 / 60 / 90 days" button on a logged post. Drops a future-scheduled entry into the post log automatically. |
| **Per-post performance notes** | S | 🟡 | A `notes_after_post` field + tiny per-subreddit success rollup (avg upvotes / comments / profile visits). |

API-level auto-publish (Reddit OAuth, etc.) is **deferred** — moved to `OUT_OF_SCOPE.md`. Same TOS / banned-subreddit / sleep-publishing pain as before.

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

## 🌷 Wellbeing (extending Molly's Log + Hours)

Hours tracking shipped in v1.17.0 (Reddit → ⏱ Hours). These layer cute structure on top of the journal + clock.

| Idea | Effort | Flavor | Notes |
|---|---|---|---|
| **Mood tracker** | S | 🔵 | Soft 5-emoji scale on each Molly's Log entry. Show a mood trend chart on Home. |
| **Burnout warning** | S | 🔵 | *"You've worked 7 days in a row — maybe take a soft day? 🌸"* Reads from `clock_sessions`; gentle, dismissible. |
| **Boundary log** | S | 🟢 | Private log of clients who pushed boundaries + what was said. Linked from the customer card. |
| **Sunday wrap card on Home** | S | 🔵 | Per-persona hour totals for the week with a soft 💕 — "you worked 22 CoC hours + 18 PoA hours this week 🌷". Builds on `hours_totals` already returning week_ms. |

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

## 🛍️ Suggested slates (post-v1.17.1 refresh)

### 🌸 Next sweet spot — *high value, low risk* (~2 weeks)
1. **Customer Intelligence** — LTV column + Whales dashboard + Cooling alerts (the data already exists in `customer_sales`).
2. **Tax-time dashboard** — quarterly estimate + categorized export.
3. **Re-promote helper + per-post performance notes** — small adds on the new Post log.

### 🌷 Ambitious next phase — *bigger build* (~5 weeks)
1. **OnlyFans + IWC CSV importers** — finally close out Phase 8 (sample CSVs from Sallie are the blocker).
2. **Per-clip ROI** using those imports + a `production_cost_cents` field.
3. **Per-platform commission tracking**.
4. **Production planner** — pipeline view (idea → scripted → shot → edited → uploaded) tying clips, bundles, and the Post log together.

### 🦋 Soft / personal touches — *scattered cute work* (~1 week)
1. **Mood tracker + burnout warning** (now that Hours data exists, burnout warning is easy).
2. **Birthday / anniversary reminders** on customers.
3. **Seasonal saying packs** (autumn / spring / Sallie's-birthday).
4. **Sound on check-off** + **custom persona emoji**.
5. **Achievement badges** in Molly's Log (first $100 day, first 100h logged, etc.).

---

## Process notes

- **A new feature lands here first**, then earns a proper `PHASE_N_*.md` plan if it graduates. The plan doc is what we hand to Claude (or future-Robert) when work begins.
- **A killed feature moves to `OUT_OF_SCOPE.md`** with one line of rationale. Keeps this doc focused on live possibilities.
- **A shipped feature moves to `CHANGELOG.md`** under its version heading. Keeps the roadmap aspirational, not historical.
- **When in doubt, ask Sallie.** This whole doc is one opinionated curator's view; the only signal that matters is what would make Sallie's actual day better.
