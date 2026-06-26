---
title: Onboarding, expectations & the feedback flywheel
module: 11 — AI Product & UX Patterns
lesson: 05
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, product, ux, onboarding, expectations, feedback, flywheel]
---

# Onboarding, expectations & the feedback flywheel

This lesson closes the module by closing the *loop* — from a user's first
encounter with the product (setting expectations) to the mechanism that makes the
product compound over time (the feedback flywheel). It also connects Module 11
back to [Module 5 evaluation](../part-05-evaluation/00-the-eval-mindset.md): the
feedback your UX captures *is* production eval signal.

---

## Set expectations before the first interaction

[Lesson 02](02-trust-transparency-and-citations.md) established that trust
calibration starts *before first use*. The vehicle is onboarding, and HAX puts
two guidelines right at the start — the "Initially" phase:

- **G1 — Make clear what the system can do.**
- **G2 — Make clear how well it can do it.**

The cost of getting this wrong is concrete: unclear expectations "can lead to
disappointment, product abandonment, and even harms." A user who expects a
flawless oracle and meets a fallible model churns; a user who was told "this
drafts first passes you'll refine" is delighted by the same output. Match the UI's
*precision* — both the language and any numbers — to the model's *actual*
performance. Over-promising is the most common, most damaging onboarding mistake.

A reusable PAIR onboarding skeleton:

> *"This is {product}, and it'll help you by {benefit}. Right now, it's not able
> to {limitation}. Over time, it'll become more {relevant / accurate / capable}."*

Three moves baked into that one sentence: lead with **benefit**, state a
**limitation** honestly, and signal that it **improves over time** (which both
sets expectations and primes the feedback loop below).

---

## Shape mental models, just-in-time

People reason about a new tool through **existing mental models** — so build on
them rather than fighting them, and *don't over-anthropomorphize*
([lesson 02](02-trust-transparency-and-citations.md)) in a way that implies
human-level reliability. And onboard **in stages, just-in-time**: introduce a
feature when the user first needs it, not in a long upfront tour that's forgotten
before it's relevant.

The highest-leverage onboarding surface is the **empty state**. A blank "How can
I help?" gives the user *no signal* about scope — they don't know what to ask, so
they bounce or ask something the product can't do (and then distrust it). The fix,
straight from NN/g's chatbot guidelines:

- Show **3 named, scoped example prompts** so the user can judge fit in ~5
  seconds — concrete capability is communicated by demonstration, not description.
- Offer them as **clickable buttons**, at first open *and* after answers (so the
  user always has a next move).
- Treat empty states as **teachable moments** — status, learning cues, and a
  direct path into the product.

This is also where [Module 2's prompting](../part-02-prompt-engineering/00-prompting-fundamentals.md)
meets the user: most people can't write a good prompt cold. Suggested prompts are
you doing the prompt engineering *for* them, and teaching them the shape of a good
ask by example.

---

## Capture feedback: granular, frictionless, acknowledged

Every interaction is a chance to learn whether the AI helped. HAX's "over time"
guidelines cover the mechanics (G15 granular feedback during interaction; G16
convey how actions shape future behavior; G17 global controls; G18 notify users
about capability changes). The durable design rules:

- **Frictionless beats granular.** A binary **thumbs up / down** yields better,
  more honest data than a 1–5 scale — users actually use it, and the signal is
  unambiguous. Don't ask for a five-star rating when a thumb will do.
- **Implicit vs. explicit feedback.** *Explicit* = ratings, thumbs, flags.
  *Implicit* = behavioral signals (did they keep the answer? edit it heavily?
  copy it? retry?) — rich, but it requires transparency/permission since you're
  inferring from behavior. The *edit* is gold: when a user fixes the AI's output,
  the diff between what the model produced and what they kept is a precise
  correction signal.
- **Acknowledge the feedback.** Closing the loop visibly ("thanks — this helps us
  improve") builds trust and makes users more willing to keep giving it. Feedback
  that vanishes into a void stops coming.
- Always provide a **manual failsafe / reset** so a user who's stuck can take
  over.

---

## The feedback flywheel: the compounding moat

Here's why all of the above is more than politeness — it's the product's
**compounding advantage.** The virtuous cycle:

```
   better product ──▶ more users ──▶ more usage
        ▲                                  │
        │                                  ▼
   better model ◀── better data ◀── more feedback
        (explicit + implicit signal)
```

More users generate more feedback (thumbs, edits, corrections, behavioral
signal); that feedback improves the system; a better system attracts more users.
The data flywheel is the durable moat of AI products — and the two captured
signals are **dual-purpose assets**:

- As **evaluation signal**, they feed your [Module 5 production eval](../part-05-evaluation/05-evaluation-in-production.md):
  thumbs-down rates, edit-distance distributions, and escalation rates are
  exactly the online metrics that tell you whether a model change helped or hurt.
- As **preference/training data**, the same corrections can fine-tune or steer the
  model ([Module 6](../part-06-fine-tuning/02-data.md)) — a user's edit is a
  ready-made "preferred output" pair.

Two cautions that make the flywheel real rather than aspirational: ensure the
feedback you collect is **actually consumable** (a thumbs-down with no context is
hard to act on — capture the surrounding interaction), and tie the flywheel to
**business outcomes**, not a vanity metric you can game. A rising thumbs-up rate
means nothing if users are churning.

---

## Where Module 11 lands in the course

Product & UX is the layer that decides whether all the prior modules' engineering
*reaches* a user well. It is also deeply woven into the rest of the course:
[latency](01-latency-and-perceived-performance.md) is [Module 7](../part-07-cost-and-latency/04-latency-engineering.md)'s
UX face; [trust/citations](02-trust-transparency-and-citations.md) is
[Module 3 grounding](../part-03-rag/04-generation-and-prompt-assembly.md)
presented well; [human-in-the-loop](03-human-in-the-loop-and-control.md) is
[Module 4](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)/[Module 10](../part-10-coding-agents/01-agentic-coding-workflows.md)
safety as a UI; and this feedback flywheel is
[Module 5 eval](../part-05-evaluation/00-the-eval-mindset.md) sourced from real
users.

`★ Insight ─────────────────────────────────────`
- **Onboarding is trust calibration's front door** — lead with benefit, state a
  limitation honestly, and demonstrate scope with 3 clickable example prompts.
  The empty state is the single highest-leverage onboarding surface, because a
  blank prompt box teaches nothing.
- **Your UX is your eval pipeline.** Frictionless, acknowledged feedback (thumbs,
  and especially edits) is a dual-purpose asset — production-eval signal *and*
  preference data — and the compounding flywheel it powers is the durable moat of
  an AI product.
`─────────────────────────────────────────────────`

## Module complete

This completes **Module 11 — AI Product & UX Patterns**. The durable spine:
design for a probabilistic system; make it *feel* fast with streaming; calibrate
trust rather than maximize it; gate the irreversible and keep the human as editor;
make being wrong cheap; and close the loop from expectations to a compounding
feedback flywheel.

→ Back to the [curriculum index](../CURRICULUM.md), or on to **Module 12 —
Governance, Safety & Compliance** (the next build), which covers the rules,
documentation, and risk practices that keep an AI product on the right side of
the law and of users' trust.
