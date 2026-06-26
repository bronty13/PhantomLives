---
title: Designing for probabilistic systems
module: 11 — AI Product & UX Patterns
lesson: 00
est_time: 30 min reading
last_reviewed: 2026-06-26
tags: [ai, product, ux, design, probabilistic]
---

# Designing for probabilistic systems

Modules 1–10 made you capable of *building* AI systems. This module is about
making them *usable* — the product and UX patterns that turn a capable model
into a product people trust and keep using. It is the most **durable** module in
the course: its backbone is design guidance that has held for years (Microsoft's
HAX guidelines, Google's People+AI Guidebook, Nielsen Norman Group's
decade-stable research), so there are few catalogs to rot here.

This first lesson establishes the mindset everything else builds on: **AI UX
inverts the contract of traditional software.**

---

## The contract that broke

Traditional software is **deterministic**: the same input gives the same output,
the system either succeeds or throws a clear error, and the user issues a command
and assesses a predictable result. Decades of UX convention assume that loop.

LLM-powered products break all three assumptions at once. Outputs are:

- **Fallible** — the model is wrong sometimes, *by design*, not as an exceptional
  bug. Failure is part of the normal operating surface.
- **Variable** — the same prompt can produce different results across users,
  sessions, even runs. Consistency becomes impossible; personalization becomes
  inevitable.
- **Latent** — answers arrive after a noticeable, variable wait (seconds to
  minutes for reasoning models), not instantly.

Nielsen Norman Group frames this as the **third UI paradigm in 60+ years**: from
batch processing → command-based turn-taking → **intent-based outcome
specification**, where "the user tells the computer what outcome they want," not
the steps to get there. The classic command loop — issue a command, assess the
result, correct — partly breaks, because *when users don't know how something was
done, it's harder for them to identify or correct what went wrong.*

---

## Design outcomes and constraints, not steps

The practical consequence: you shift from specifying *interfaces and methods* to
specifying *outcomes and constraints*, accepting reduced step-by-step control.
Google PAIR and NN/g both describe the paradox — you "provide rigorous guidance
while relinquishing granular control."

A durable technique that recurs across this module: give the model a
**must-show / should-show / never-show hierarchy** of constraints rather than a
fixed layout. You're not designing the pixels; you're designing the *rules* the
generated output must satisfy. This is the UX-layer version of
[Module 2's structured prompting](../part-02-prompt-engineering/01-core-techniques.md)
and [Module 4's tool design](../part-04-agents-and-tool-use/01-tool-and-function-calling.md):
constrain the space, then let the model fill it.

---

## Failure is part of the design surface

The single most important reframe in AI UX: **design for failure as the default
state, not the exception.** A model "will fail at some point" — so the question
is never "how do we prevent all errors" (you can't) but "how do we make errors
cheap to notice, dismiss, and correct."

PAIR adds a third error class beyond the familiar two:

- **User errors** — the user did something wrong.
- **System errors** — the system malfunctioned.
- **Context errors** — *the system worked exactly as designed but made a wrong
  assumption about the user's intent.* The model confidently did the wrong
  thing. This is new, it's specific to AI, and it does the most damage to trust
  — because nothing "broke," yet the result is still wrong.

And a related distinction: *perceived* failure ≠ *actual* failure. A correct
answer that looks wrong (or a slow one that feels broken) fails in the user's
eyes regardless of the model's accuracy. Much of this module is about closing
that perception gap.

---

## The canonical guidance backbone

You don't have to invent AI UX from scratch — there's a decade of validated
guidance, and the rest of this module hangs off it:

- **Microsoft HAX — 18 Guidelines for Human-AI Interaction** (Amershi et al.,
  CHI 2019). The canonical checklist, grouped by interaction phase:
  *Initially* (G1–G2: make clear what it can do and how well) → *During*
  (G3–G6) → *When wrong* (G7–G11: dismiss, correct, scope, explain) → *Over
  time* (G12–G18: learn, update, give controls). We cite specific guidelines
  throughout.
- **Google PAIR — People + AI Guidebook** — mental models, explainability +
  trust, feedback + control, errors + graceful failure.
- **Nielsen Norman Group** — ongoing empirical AI-UX research.
- **Apple HIG (Generative AI)** — scope generation to limit hallucination blast
  radius, confirm before irreversible actions, disclose AI use.
- **Anthropic / OpenAI agent guidance** — building effective agents, guardrails,
  approvals.

The module map:

| Lesson | The durable question |
|---|---|
| 01 Latency & perceived performance | How do I make a slow, variable system *feel* responsive? |
| 02 Trust, transparency & citations | How do I make trust *calibrated* — not too high, not too low? |
| 03 Human-in-the-loop & control | How much control do I keep, and where? |
| 04 Designing for failure | How do I make being wrong cheap and recoverable? |
| 05 Onboarding & the feedback flywheel | How do I set expectations and turn use into improvement? |

`★ Insight ─────────────────────────────────────`
- **AI UX inverts the deterministic-software contract** — fallible, variable,
  latent — so conventions built on "same input, same output, instant, succeeds-
  or-errors" quietly stop applying. The whole module is patterns for the new
  contract.
- **"Context errors" are the AI-native failure that hurts most** — the system
  works as designed but guesses your intent wrong. You can't engineer them away,
  so you design *around* them: make the wrong guess cheap to catch and correct.
`─────────────────────────────────────────────────`

## Next

→ [Latency & perceived performance](01-latency-and-perceived-performance.md) —
making a slow system feel fast.
