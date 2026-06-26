---
title: Observability & tracing
module: 13 — LLMOps / Productionization & Observability
lesson: 02
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, llmops, observability, tracing, opentelemetry, monitoring]
---

# Observability & tracing

When an LLM app misbehaves in production — a wrong answer, a runaway cost, an
agent that looped forever — you need to see *what actually happened*: the exact
prompt, the completion, the tokens, the tool calls, the whole multi-step trace.
Traditional application monitoring won't show you any of that. This lesson is
about **LLM observability** — why it's different, the trace/span model, the
emerging standard, and the privacy tension at its core.

> ⚠️ **Dated snapshot — June 2026.** The *why* and the trace/span model are
> durable; the standards' maturity and the tool list are a snapshot — notably the
> OpenTelemetry GenAI conventions were **not yet stable** at this writing.

---

## Why traditional APM isn't enough

Classic application performance monitoring (APM) was built for *deterministic*
systems. It captures *timing and request/response metadata* — latency, error
rates, throughput. For a normal API that's plenty. For an LLM app it's blind to
everything that matters, for two structural reasons:

1. **The payload is semantic.** The interesting failures are in the *content* —
   a hallucination, a refusal, a subtly-wrong-but-valid object — not in the
   timing. You have to capture the **exact prompt sent, the completion, token
   usage, model and params, tool calls, and retrieval steps**, or you're
   debugging blind. As the saying goes: the mechanics of each call are fine, which
   is exactly why latency and token counts *can't see* the failure.
2. **The structure is a tree, not a request.** An agent is a *loop*, not a
   function — plan → call a tool → read the result → decide → repeat. A single
   user request can fan out into dozens of LLM calls, tool calls, and retrieval
   steps. You need the whole **trace** (the tree), not a flat request/response
   line, to understand where in the loop it went wrong. This is exactly
   [Module 4's trajectory evaluation](../part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md)
   made into a production telemetry requirement.

So LLM observability captures *both* the span tree *and* the semantic payload —
and then layers **evals** on top, because spans show you the structure but only
an eval tells you the content was *wrong*.

---

## The trace/span model

The data model has converged across vendors:

- A **trace** is a tree of **spans** (also called runs or observations) for one
  operation — one user request and everything it triggered.
- Span *kinds* are roughly standard: **LLM-call**, **tool**, **retrieval**,
  **chain/workflow**, **agent**, and **embedding**.

So an agent run might be a top-level `agent` span containing several `chat` (LLM)
spans, each possibly with child `execute_tool` and `retrieval` spans — a literal
tree of what the agent did, with latency, tokens, and cost attached at every
node. That tree is what makes a misbehaving agent debuggable.

---

## The emerging standard: OpenTelemetry GenAI conventions

The open standard for this is the **OpenTelemetry GenAI semantic conventions** —
a vendor-neutral schema for naming GenAI spans and attributes, so observability
data is portable across backends. The durable idea (vendor-neutral telemetry) is
worth adopting; the **status is the dated, must-flag part**:

- **As of June 2026 the GenAI conventions are still in `Development` status — not
  Stable.** No part is finalized; the inference/client spans are the most mature
  in practice but still carry the "Development" badge. *Don't present them as
  settled* — that's a live re-verify item.
- The conventions standardize operation names (`chat`, `embeddings`, `retrieval`,
  `execute_tool`, …) and core attributes (`gen_ai.operation.name`,
  `gen_ai.provider.name`, `gen_ai.request.model`, `gen_ai.usage.input_tokens` /
  `output_tokens`, …), plus agent attributes and a metric for token usage and
  call duration.
- **Prompt/completion content is captured as structured span attributes — and it
  is OPT-IN by spec.** Instrumentations *should not* capture message content by
  default and *should* provide an opt-in flag. **That opt-in default is the
  canonical privacy kill-switch** (see below) — and it's deliberate.

The durable takeaway independent of the version churn: **prefer OpenTelemetry-
native tooling** so your traces aren't locked to one vendor, and treat the exact
attribute names and stability as something to check against the current spec.

---

## The tool landscape (June 2026 snapshot)

Most tools are now OTel-compatible; they differ in whether they're a SaaS, OSS
self-hostable, or a proxy-vs-SDK integration. *Re-verify at the links.*

| Tool | OSS / SaaS | Notes |
|---|---|---|
| **LangSmith** | SaaS (+ self-host) | run-based span model; native OTel incl. distributed tracing |
| **Langfuse** | OSS (self-hostable) + SaaS | traces/sessions/observations; OTel-native; captures prompt/response/tokens/cost; client-side masking |
| **Arize Phoenix** | OSS | built on OpenTelemetry + OpenInference; full span taxonomy; evals + prompt versioning |
| **Helicone** | OSS + SaaS | proxy *or* async-SDK logging (off the request path) |
| **OpenLLMetry / Traceloop** | OSS | OpenTelemetry instrumentations exporting OTLP to any backend |
| **Datadog LLM Observability** | SaaS | full span kinds; native OTel ingest; Sensitive Data Scanner for PII |
| **Braintrust** | SaaS | eval-centric; ties tracing into the eval/CI loop |

A practical integration distinction worth knowing: a **proxy** integration (the
gateway from [lesson 01](01-the-llm-gateway-pattern.md) logs every call) requires
no app changes but only sees what flows through it; an **SDK** integration
instruments your code directly and can capture richer in-app context (the agent's
internal steps), at the cost of code changes. Many teams do both.

---

## What to log, and the privacy tension

Log enough to debug *and* to cost: prompts, completions, tokens, model/params,
tool I/O, and the full span tree. But here's the tension at the heart of LLM
observability: **prompts and completions routinely contain PII** — user messages,
uploaded documents, retrieved records. Logging them verbatim creates a privacy and
compliance liability ([Module 12](../part-12-governance/02-data-privacy-and-governance.md)).

The durable resolution: **content capture must be opt-in, maskable, sampleable,
and redaction-routed.** Concretely:

- **Redact at the source or at a collector gateway *before* storage.** Client-side
  masking (regex/Presidio-style PII detection) scrubs sensitive content before it
  ever leaves your perimeter; a redaction gateway scrubs traces before they reach
  the observability backend.
- **Sample** to control both cost and exposure — you rarely need 100% of content
  logged.
- **Allow opting out of *content* while keeping the *structural* spans** — you can
  keep tokens, latency, cost, and the span tree (which are not sensitive) even
  when you drop the message bodies. This is exactly why OpenTelemetry makes content
  capture opt-in by default: the structure is safe to log; the content needs a
  deliberate decision.

This is the operational face of [Module 12's data governance](../part-12-governance/02-data-privacy-and-governance.md)
and [Module 11's trust](../part-11-product-ux/02-trust-transparency-and-citations.md):
your logs are a data store full of user content, and they need the same lawful-
basis, retention, and minimization discipline as any other.

`★ Insight ─────────────────────────────────────`
- **LLM observability captures the semantic payload and the span *tree*, not just
  timing** — because the failures are in the content and the structure is a loop,
  not a request. APM tells you it was slow; LLM tracing tells you the agent called
  the wrong tool with a hallucinated argument on step 7.
- **Content capture is the privacy fault line** — prompts/completions are full of
  PII, so the durable rule (and the OTel default) is opt-in content, redacted at
  source or a gateway, sampled, with structural spans kept even when bodies are
  dropped. Your trace store is a user-data store; govern it like one.
`─────────────────────────────────────────────────`

## Next

→ [Reliability engineering](03-reliability-engineering.md) — keeping a
probabilistic, externally-dependent system up.
