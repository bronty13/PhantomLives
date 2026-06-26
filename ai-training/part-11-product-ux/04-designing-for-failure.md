---
title: Designing for failure
module: 11 — AI Product & UX Patterns
lesson: 04
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, product, ux, failure, errors, hallucination, recovery]
---

# Designing for failure

[Lesson 00](00-designing-for-probabilistic-systems.md) established that an AI
system *will* fail — fallibility is intrinsic, not exceptional. This lesson is
the discipline that follows from accepting that: **design for failure as the
default state.** The measure of an AI product isn't how rarely it's wrong; it's
how cheap being wrong is to notice, dismiss, correct, and recover from.

---

## The "when wrong" guidelines (HAX G8–G11)

Microsoft's HAX puts a whole phase of its 18 guidelines on *being wrong* — which
tells you how central it is. The four:

- **G8 — Support efficient dismissal.** Make it easy to dismiss or ignore
  unwanted AI output. A suggestion the user can wave away costs nothing; one they
  must fight is an irritant.
- **G9 — Support efficient correction.** Edit, refine, undo (covered in
  [lesson 03](03-human-in-the-loop-and-control.md)) — make fixing a wrong answer
  cheap.
- **G10 — Scope services when in doubt.** *The canonical "reduce the cost of an
  error" rule.* When the system is uncertain, **disambiguate** (ask), **gracefully
  degrade** (do less, but reliably), or **fall back** — rather than confidently
  guessing wrong. Better a narrower, correct response than a broad, wrong one.
- **G11 — Make clear why.** Explainability as a *recovery* tool — when the AI is
  wrong, telling the user *why* it did what it did helps them correct it and
  rebuild calibrated trust ([lesson 02](02-trust-transparency-and-citations.md)).

---

## Honest abstention beats confident hallucination

The most important single principle in failure design: **a model that says "I
don't know" is more valuable than one that confidently makes something up.**
[Module 2](../part-02-prompt-engineering/04-reliability-security-and-evaluation.md)
and [Module 3](../part-03-rag/05-evaluation-security-and-production.md) covered
hallucination at the model and pipeline layers; here is the **UI layer**, ordered
by the cost of an error:

1. **Ground and abstain first.** RAG (real sources) plus a *designed* abstention
   path — an explicit, well-styled "I couldn't find that" — is the cheapest, most
   reliable mitigation. The UI must make abstention a *first-class, graceful*
   outcome, not an awkward dead end.
2. **Constrain inputs, scope outputs.** Narrow what you ask the model to generate
   (Apple's "carefully scope what you ask a model to generate"); longer free-form
   generation drifts further from fact. A constrained output (a structured form,
   a bounded choice) has less room to hallucinate.
3. **Verify where wrong answers are expensive.** For high-stakes claims, add a
   verification step or surface the source for the user to check — the
   [Module 5 grading hierarchy](../part-05-evaluation/02-grading-methods.md)
   applied at runtime.

A useful pattern to bake in is **ICE — Instructions + Constraints + Escalation**:
tell the model what to do, constrain how, and give it an explicit *escalation /
refusal path* for when it can't. The escalation path is what turns a
hallucination into an honest "I can't do that, here's what you can try."

---

## Account for the user's bandwidth

A failure that depends on the user catching it only works if the user *can*. PAIR
stresses designing for the user's **mental bandwidth**: many users are
multitasking, time-pressured, or non-expert and *cannot* double-check the AI's
output. So **the guardrails have to do the work** — you can't offload all error
detection onto a "review carefully" disclaimer. The more likely it is that the
user will accept output uncritically (automation bias from
[lesson 02](02-trust-transparency-and-citations.md)), the more the system itself
must prevent or flag the error.

---

## Always provide a path forward

When the AI fails, the user must never be stranded. PAIR's recovery requirements:
restore control to the user, offer a **safe failure state**, give a feedback
channel — and **acknowledge** the feedback when it's given. A durable
three-tier recovery ladder:

```
clarify  →  suggest  →  escalate
(ask a      (offer        (hand off to a
 question)   alternatives) human / safe fallback)
```

- **Clarify** — when intent is ambiguous, ask rather than guess (HAX G10's
  disambiguation).
- **Suggest** — when the AI can't fully answer, offer partial results,
  alternatives, or a reformulation the user can try.
- **Escalate** — when the AI is out of its depth, **the human handoff is a
  feature, not an admission of defeat.** Label the response as machine-generated,
  and route to a person (or a safe non-AI path) cleanly.

Two tone notes from the research that matter more than they look: use a **human,
humble tone** in error messages and **state the next action** ("I couldn't reach
that source — try rephrasing, or here's what I did find"); and **avoid
anthropomorphic refusal phrasing** that makes a system limitation sound like a
personal choice. An error message is a trust moment — a curt or evasive one
spends trust you worked to build.

---

## Avoid fake transparency in failure

A trap worth restating from [lesson 02](02-trust-transparency-and-citations.md):
when the AI is wrong, do **not** paper over it with an unfaithful "explanation" or
a confident-looking reasoning trace. Displaying a plausible rationalization for a
wrong answer makes the failure *worse* — it borrows credibility to defend a
mistake. Honest, partial transparency ("this came from your document; I'm not
sure about the rest") rebuilds calibrated trust; fake completeness erodes it.

`★ Insight ─────────────────────────────────────`
- **The product metric is the cost of being wrong, not the rate.** HAX's whole
  "when wrong" phase — dismiss, correct, scope, explain — exists because you
  can't drive the error rate to zero, so you drive the *cost per error* down
  instead.
- **Honest abstention is a feature; the guardrails must do the work.** Design "I
  don't know" and the human handoff as first-class graceful states, and don't
  offload error-catching onto a user who's multitasking and prone to automation
  bias — if catching the error matters, the system has to help catch it.
`─────────────────────────────────────────────────`

## Next

→ [Onboarding, expectations & the feedback flywheel](05-onboarding-and-the-feedback-flywheel.md)
— setting expectations and turning use into improvement.
