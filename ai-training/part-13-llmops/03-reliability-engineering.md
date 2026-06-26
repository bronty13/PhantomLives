---
title: Reliability engineering
module: 13 — LLMOps / Productionization & Observability
lesson: 03
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, llmops, reliability, retries, fallback, slo]
---

# Reliability engineering

Production LLM apps fail in ways a normal web service doesn't — and the most
important of those ways is that **a 200 OK is not the contract.** This lesson
covers LLM-specific failure modes and the resilience patterns that handle them.
Much of it is classic distributed-systems reliability; the twist is applying it
to a dependency that is *unreliable, probabilistic, and able to fail while
returning success.*

> ⚠️ **Dated snapshot — June 2026.** The patterns are durable; specific provider
> error codes, headers, and rate-limit semantics are a snapshot — re-verify at
> the provider error docs.

---

## The core reframe: 200 OK is not success

In a normal API, the status code is the contract: 200 means it worked. In an LLM
app, **a 200 can still be a failure** — a refusal, a hallucination, a
schema-valid-but-semantically-wrong object, or a quality regression. So reliability
engineering here has two halves:

1. **Standard resilience patterns** for the transport-level failures (timeouts,
   rate limits, outages) — retries with backoff, circuit breakers, fallback,
   hedging, degradation, capacity planning.
2. **Application-level branching on response *content*, not just status codes** —
   because the failure is often *inside* a successful response.

Hold both ideas at once and the rest of the lesson follows.

---

## LLM-specific failure modes

What actually breaks in production:

- **Rate limits (429) are multi-dimensional.** Providers limit you on *several*
  axes at once — requests/min, input-tokens/min, output-tokens/min — and hitting
  *any one* returns a 429. Worse, on some providers a 429 has **two meanings**: a
  transient rate-limit (retry will succeed) vs. a **quota/billing exhaustion**
  (retry never will). You must distinguish them, usually via the response body or
  headers.
- **Overload (529) is not a rate limit.** A fleet-wide "overloaded" error means
  the *provider* is saturated — retrying harder against the same provider won't
  help; this is the case for **fallback to another provider**.
- **Content refusals arrive inside a 200.** A safety refusal is a *successful*
  HTTP response with a `stop_reason`/`finish_reason` indicating refusal — your
  code must check the stop reason before treating the response as an answer.
  (This is the [Module 9](../part-09-multimodal/01-vision-and-documents.md)/
  Module-1 model behavior surfacing as an ops concern.)
- **Streaming errors occur *after* the 200.** When you stream, the 200 header
  goes out first; an error mid-stream can't use an HTTP status code, so you need
  an in-band error convention to catch it.
- **Schema-valid ≠ semantically correct.** Constrained decoding drives *syntactic*
  failures to near zero — but a perfectly-shaped JSON object can still hold the
  wrong value. Structure validation is necessary, not sufficient.
- **Pre-flight-detectable structural errors** — a too-large request or a context
  overflow — are cheap to catch *before* sending, and gateways can route them
  specially (e.g. a context-window fallback to a larger-context model).

---

## The durable resilience patterns

These are classic reliability patterns; what's worth internalizing is *why* each
matters for an LLM dependency.

### Retries with exponential backoff — and jitter

Retry transient failures, backing off exponentially. **The non-obvious part:
jitter is the load-safety mechanism, not a nice-to-have.** Retries are "selfish" —
when failures are caused by *overload*, naive retries add load and make the
outage worse. Capped backoff alone causes retries to *re-synchronize* into waves;
**jitter spreads them randomly in time**, cutting both contention and total work.
And **honor the provider's `Retry-After` header over your computed backoff** —
when the provider tells you when to retry, earlier attempts are guaranteed to
fail. (The AWS Builders' Library article on timeouts/retries/backoff-with-jitter
is the durable reference.)

### Circuit breakers

When a provider is clearly down, **stop hammering it** — a circuit breaker trips
on an error-rate threshold, removes the unhealthy target, and re-adds it after a
cooldown. The caveat worth teaching: circuit breakers add *modal* behavior
(the system acts differently when tripped) that's hard to test, so a gentler
alternative is local rate-limiting / retry budgets that throttle without a hard
mode switch.

### Fallback chains

The LLM-native answer to single-provider outages and 529s: **a chain of
fallbacks** — try model A, on failure try model B (maybe a different provider),
then C. Gateways ([lesson 01](01-the-llm-gateway-pattern.md)) implement this as
config, including *typed* fallbacks (a generic fallback, a context-window fallback
for too-large requests, a content-policy fallback for refusals). This is why the
gateway and reliability are the same conversation — the fallback chain lives there.

### Timeouts and hedging

Set timeouts so a hung request doesn't block forever. For *tail latency* (a slow
straggler, not a failure), **hedging** helps: once the primary request exceeds
~p95, fire a second request and take whichever returns first. The classic result
(Google's "The Tail at Scale") cut p99.9 latency dramatically at a few percent
extra load. For streaming LLMs, key the hedge on **time-to-first-token** — the
[Module 11 latency metric](../part-11-product-ux/01-latency-and-perceived-performance.md).

### Graceful degradation

When all else fails, degrade rather than error: serve a cached response, fall back
to a cheaper/smaller model, or return a safe canned answer. Caching
([Module 7](../part-07-cost-and-latency/02-caching.md)) is the cheapest
degradation tier. This is [Module 11's "always provide a path forward"](../part-11-product-ux/04-designing-for-failure.md)
implemented in the backend.

### Capacity planning

Treat provider quotas (RPM/TPM tiers) as a **capacity budget** you plan against.
For guaranteed headroom on critical workloads, **provisioned throughput** reserves
dedicated capacity (at the cost of paying for it whether used or not — the
[Module 7 utilization math](../part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md)).

---

## SLOs for a probabilistic system: split the SLIs

You can't write a normal SLO ("99.9% of responses correct") for a system whose
output is non-deterministic and whose correctness is a judgment call. The durable
answer: **split your service-level indicators into two kinds.**

- **Deterministic SLIs** — always assertable, cheap, catch regressions fast: JSON
  validity, required-field presence, response within the latency SLA, response
  within the cost budget. These you can monitor like any normal SLO.
- **Quality SLIs** — need *multi-trial* measurement: run the same input N times and
  measure the variance, because a single run tells you little about a stochastic
  system. These come from your [Module 5 eval suite](../part-05-evaluation/05-evaluation-in-production.md)
  run over production traces, not from a single request.

The reason this matters: traditional SLO monitoring alone is *insufficient* for
LLMs precisely because they "fail silently by generating plausible but incorrect
responses." A 200-with-normal-latency dashboard will look perfectly healthy while
quality quietly degrades — which is why the deterministic dashboard and the
quality eval are *both* required.

> **The LLM-native error handler: regenerate.** Because output is
> non-deterministic, a *failed semantic check* can be retried by simply
> **regenerating** — the generate → evaluate → regenerate loop is a recovery
> pattern that has no analog in deterministic systems. And always capture the
> provider's `request-id` on failures: it's how you (and the provider) debug an
> issue you can't reproduce locally.

`★ Insight ─────────────────────────────────────`
- **A 200 OK is not the contract.** The defining LLM reliability skill is
  branching on response *content* (refusal? wrong-but-valid? hallucination?) on
  top of the classic transport patterns — retries-with-jitter, circuit breakers,
  fallback chains, hedging, degradation, capacity planning.
- **Split your SLIs.** Deterministic indicators (JSON valid, within latency/cost)
  monitor like normal SLOs; quality indicators need multi-trial eval over real
  traces — because a silent quality regression looks perfectly healthy on a
  latency dashboard.
`─────────────────────────────────────────────────`

## Next

→ [Continuous improvement & the deployment lifecycle](04-continuous-improvement-and-lifecycle.md)
— shipping changes to a system that fails silently.
