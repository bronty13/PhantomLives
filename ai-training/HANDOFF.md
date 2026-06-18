---
title: AI Training — Build Handoff
type: handoff
audience: a future Claude (or human) continuing this curriculum
last_reviewed: 2026-06-18
---

# Handoff — how to continue building this curriculum

Read this before adding or rewriting lessons. It mirrors the conventions of the
repo's [`macos-mastery`](../macos-mastery/HANDOFF.md) course, which is the model
for this one.

## What this is

A self-paced, **practical** AI/LLM curriculum — working knowledge for choosing,
running, and applying models, not ML theory. It lives in
`~/dev/PhantomLives/ai-training/` and is mirrored into Obsidian by the repo's
`sync-md-to-obsidian.sh` (git-tracked `.md` only — **commit new lessons** or they
won't appear in Obsidian).

The first build was **Module 1 — Model Landscape**.

## File / naming conventions

- Modules: `part-NN-theme/` (two-digit, zero-padded).
- Lessons: `part-NN-theme/NN-slug.md`.
- The authoritative lesson list + build status is [CURRICULUM.md](CURRICULUM.md).
  **Update its status column** (⬜→🚧→✅) whenever you touch a lesson.
- Cross-link with relative Markdown links for navigation; `[[wikilinks]]` are fine
  inline since the docs are read in Obsidian too.
- Every catalog/snapshot page carries a `last_reviewed:` date in front-matter and a
  short "how to re-verify" note, because this content goes stale fast.

## Lesson front-matter template

```markdown
---
title: <Lesson title>
module: NN — <theme>
lesson: NN
est_time: <e.g. 30 min reading>
last_reviewed: <YYYY-MM-DD>
tags: [ai, <topic-tags>]
---
```

## The cardinal rule of this course: durable first, perishable second

Model specs and prices rot in weeks. So:

1. **Lead every topic with the framework / mental model** (how to *decide*), which
   ages slowly.
2. **Put the dated catalog second**, clearly marked as a snapshot, with provider
   links so the reader can re-verify.
3. When you revise a catalog, **bump `last_reviewed`** and note what changed in
   [CHANGELOG.md](CHANGELOG.md).

## Sourcing rules (important — there's a TRAP here)

- For **Anthropic / Claude** facts (model IDs, context windows, pricing, API
  behavior), do **not** rely on memory or generic web search. Invoke the
  **`claude-api` skill** — it carries the authoritative, current Anthropic model
  table and is the source of truth this repo expects. (The repo's CLAUDE.md and
  the skill's own trigger both mandate this.)
- For **everyone else** (OpenAI, Google, Meta, etc.) and for the **local/open-weight
  ecosystem**, use live web search + the **Hugging Face Hub** (the
  `mcp__claude_ai_Hugging_Face__*` tools give real download/trending numbers — use
  them to anchor "popular local model" claims in data, not vibes).
- Flag anything announced-but-unshipped explicitly. Don't present a rumored model
  as available.

## How Module 1 was built (reproduce this for refreshes)

1. `claude-api` skill → authoritative Anthropic model facts.
2. Two parallel research agents (frontier/proprietary; open-weight/local) doing
   live web research, each returning a cited markdown report.
3. Direct Hugging Face Hub queries (top-downloaded + top-trending text-generation
   models) to ground the top-100 list.
4. Synthesized into the four Module 1 pages, with volatility caveats throughout.

To refresh: rerun that pipeline, diff against the current pages, bump
`last_reviewed`, log it in the CHANGELOG.

## Repo hygiene that applies here

- Doc-only project: the repo's `build-app.sh` / `~/Downloads/<name>/` / backup
  rules do **not** apply (no app, no user data, no artifacts) — same exemption as
  `macos-mastery`.
- Follow the repo's release-hygiene habit anyway: when you change content, add a
  [CHANGELOG.md](CHANGELOG.md) entry.
- Commit new/changed `.md` so Obsidian sync picks them up.
