---
title: Continuous improvement & the deployment lifecycle
module: 13 — LLMOps / Productionization & Observability
lesson: 04
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, llmops, ci-cd, prompt-versioning, deployment, rollout]
---

# Continuous improvement & the deployment lifecycle

How do you safely ship a change to a system that **fails silently** — where a
worse prompt or a model upgrade still returns a 200, normal latency, and an
answer that's just *quietly worse*? You can't unit-test your way to confidence.
This lesson is the deployment lifecycle that answers that: versioned prompt
artifacts, eval gates instead of pass/fail tests, gradual rollout, careful model
migration, and the production feedback loop. It's the
[Module 5 eval discipline](../part-05-evaluation/05-evaluation-in-production.md)
and [Module 10 CI verification](../part-10-coding-agents/04-evaluating-and-trusting-coding-agents.md)
operationalized for LLM apps.

> ⚠️ **Dated snapshot — June 2026.** The lifecycle is durable; specific tooling
> and provider deprecation schedules are a snapshot — re-verify at the links.

---

## The core problem: silent regressions

A normal software regression announces itself — a test fails, an exception
throws, an error rate spikes. An LLM regression is **silent**: a prompt tweak that
makes responses 20% more sycophantic, or a model upgrade with subtly worse
instruction-following, produces *zero errors, normal latency, and invisible-to-
standard-metrics* degradation. Everything the rest of this lesson does exists to
make silent regressions *visible* before they reach all your users.

---

## Prompt versioning: the artifact is the prompt

[Lesson 00](00-what-is-llmops.md) established that the artifact you ship is the
prompt/context/tool config, not weights. So it needs the same discipline as code:
**version it.**

- **Prompts live in a registry, outside the codebase**, so they can be iterated
  (and rolled back) without a code redeploy — and non-engineers can tune them.
- **Each version is immutable and content-addressed** — a commit hash capturing
  the prompt text, variables, and model config together, so "which prompt ran" is
  always answerable (essential for debugging the traces from
  [lesson 02](02-observability-and-tracing.md)).
- **Labels decouple "which version runs" from code.** Your app pulls
  `my-prompt:production`; you change the live version by *reassigning the label*,
  not deploying. **Rollback = relabel** — instant, no redeploy. Protected labels
  stop non-admins from repointing `production`.
- A **diff view** between versions before promotion is standard practice.

---

## Eval gates in CI — thresholds, not pass/fail

The CI analog for LLM apps: **run an offline eval suite on every change, compare
aggregate scores against a baseline, and block the merge on a regression beyond a
tolerance.** The crucial difference from normal CI is that the gate is
**probabilistic and relative**, not boolean:

- Not "the test passed" but "the aggregate score is above the minimum **and** has
  not regressed more than ~X% versus current production."
- A common convention: a golden set of ≥30 cases, a small tolerance band (a few
  percent), and — if you use an [LLM-as-judge](../part-05-evaluation/03-llm-as-judge.md)
  in the gate — **calibrate the judge to ~85–90% agreement with human labels
  before you trust it to block a merge.**

And the highest-leverage habit, straight from
[Module 5](../part-05-evaluation/01-building-eval-sets.md): **turn every
production failure into a permanent regression test.** A bad output shows up in
prod → you capture it → it goes into the eval dataset → you're guarded against
that failure forever. The eval set compounds with every incident.

---

## Gradual rollout: shadow → canary → A/B

Because regressions are silent, you never flip 100% of traffic to a new
prompt/model at once. The escalating ladder:

1. **Shadow** — mirror real traffic to the new version but **don't serve** its
   responses. You compare outputs offline with zero user risk.
2. **Canary** — route a small slice (~5%) of *real* traffic to the new version,
   gated on quality and ops signals **by cohort** — latency, cost, refusal rate,
   output length, safety, and user feedback.
3. **A/B** — run variants simultaneously across segments to *optimize* (not just
   de-risk), comparing on your target metric.

The failure a *code* canary misses is exactly the silent one: zero errors, normal
latency, subtly worse answers. So the **canary must watch output-quality / eval
signals, not just error rate** — and rollback must be automated when they regress.

> **Pin the full behavioral surface as one unit.** A prompt tested in isolation
> can fail against an untested model version. The durable practice is a
> "deployment manifest" that pins the **prompt version + model + RAG index + tool
> schema together** as a single rollback unit — because the behavior is the
> *combination*, not any one piece. Change one, re-evaluate the whole.

---

## Model-version migration risk

Your hard external dependency ([lesson 00](00-what-is-llmops.md)) includes the
provider's *deprecation schedule*. The durable discipline:

- **Pin dated snapshot IDs, not aliases.** An alias (e.g. `claude-opus-4-1`) is a
  *pointer* that resolves to a dated snapshot (`...-20250805`). Pinning the dated
  ID means the model behavior doesn't silently shift under you when the alias
  moves — reproducibility you control. (See
  [Module 1](../part-01-model-landscape/00-how-to-choose-a-model.md) and the
  authoritative model facts in this repo's `claude-api` skill.)
- **Know the lifecycle.** Providers move models through stages — Active → Legacy →
  **Deprecated** (still works, has a replacement and a retirement date) →
  **Retired** (requests fail, no graceful degradation). Anthropic, for example,
  gives ≥60 days' notice before retirement and even commits to *preserving the
  weights* of released models — but **weight preservation is not continued API
  availability**, so migration is still mandatory.
- **Audit before migrating, and re-evaluate after.** Export usage by model and
  API key to find what's affected, then run your eval suite against the new model
  before switching — a model upgrade is a behavior change and goes through the
  same shadow→canary ladder. (Mind hard API breaks too: on the newest models,
  setting sampling params like `temperature` non-default can return a 400 — a
  migration footgun.)

---

## The feedback loop closes the cycle

The lifecycle is a *loop* ([lesson 00](00-what-is-llmops.md)): production feeds
the next iteration.

- **Instrument production with traces** ([lesson 02](02-observability-and-tracing.md))
  and **capture user feedback linked to each trace** (thumbs, human review) — the
  [Module 11 feedback flywheel](../part-11-product-ux/05-onboarding-and-the-feedback-flywheel.md).
- **Run online evals over real traces** to catch issues the offline set missed,
  and **curate the interesting production traces into eval datasets** for
  systematic testing.
- **Track drift** across prompt versions and model updates — the bridge from
  online monitoring back to the CI eval gate.

The connected workflow — observability + prompt versioning + evals + experiments +
annotation in one place — is what lets a team go prototype → production and *keep
improving on real usage* instead of shipping once and hoping.

`★ Insight ─────────────────────────────────────`
- **Silent regressions are the enemy, and the whole lifecycle is built to surface
  them** — versioned prompts (rollback = relabel), eval gates that are *threshold-
  and-baseline* relative (not pass/fail), and shadow→canary→A/B rollout watching
  *quality* signals, not just error rate.
- **Pin the whole behavioral surface and migrate models deliberately.** Prompt +
  model + RAG index + tool schema move as one rollback unit; pin dated model
  snapshots over aliases; and treat a model upgrade as a behavior change that
  earns a full eval pass. Every prod failure becomes a permanent regression test.
`─────────────────────────────────────────────────`

## Next

→ [Ops at scale](05-ops-at-scale.md) — secrets, cost governance, and the platform
team.
