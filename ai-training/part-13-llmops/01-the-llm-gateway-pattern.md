---
title: The LLM gateway pattern
module: 13 — LLMOps / Productionization & Observability
lesson: 01
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, llmops, gateway, proxy, routing, infrastructure]
---

# The LLM gateway pattern

The single most leverage-dense architectural decision in LLMOps is also one of
the simplest to state: **put one internal endpoint in front of every model call.**
This lesson is about that endpoint — the **LLM gateway** (also called a proxy or
router) — what it centralizes, and why it turns reliability, cost, and governance
from code scattered across your services into *config at one chokepoint*.

> ⚠️ **Dated snapshot — June 2026.** The *pattern* is durable; the specific tools
> and their feature sets and ownership are a snapshot (a couple were mid-
> acquisition at this writing). Re-verify the tooling at the provider links.

---

## The durable principle: one chokepoint for cross-cutting concerns

Without a gateway, every service that calls an LLM independently implements
provider auth, retries, fallback, rate-limit handling, caching, cost logging, and
PII redaction — scattered, inconsistent, and impossible to change centrally. Swap
a provider and you touch a dozen codebases.

With a gateway, your application code talks to **one normalized API** (usually
OpenAI-compatible), and the gateway owns everything cross-cutting:

- **Unified API** across providers — your code is provider-agnostic; swapping
  Claude for GPT for a local model is a config change, not a code change.
- **Centralized key/secret management** — provider keys live in one place, never
  scattered through app config ([lesson 05](05-ops-at-scale.md)).
- **Routing** — pick the model per request by cost, latency, or capability (the
  [Module 7 model-routing](../part-07-cost-and-latency/03-model-selection-and-routing.md)
  decision, implemented at the infrastructure layer).
- **Automatic fallback** — when a provider 529s or times out, transparently retry
  on another ([lesson 03](03-reliability-engineering.md)).
- **Rate limiting** — protect against runaway clients and smooth your own usage
  against provider quotas.
- **Caching** — exact-match and semantic ([Module 7, lesson 02](../part-07-cost-and-latency/02-caching.md)),
  applied once at the chokepoint instead of per-service.
- **Cost tracking & attribution** — every request tagged and metered in one place
  ([lesson 05](05-ops-at-scale.md)).
- **Logging / tracing** — the gateway is the natural place to emit
  observability data ([lesson 02](02-observability-and-tracing.md)).
- **Guardrails** — PII/DLP and policy enforcement applied uniformly.

The decoupling is the point: **product code calls a model; the gateway decides
which one, with what resilience, at what cost, with what controls.** Change any
of those without redeploying the app.

> **Scope note.** This is the ops layer *in front of* the model. Self-hosting the
> model *server* itself (vLLM, etc.) is [Module 8's](../part-08-local-inference/04-serving-at-scale-vllm.md)
> topic — and a self-hosted model sits *behind* a gateway just like a hosted API
> does, because the gateway speaks one API to your app regardless of what's behind
> it. The two compose.

---

## The tool landscape (June 2026 snapshot)

Gateways span open-source self-hosted proxies, SaaS gateways, and cloud-native
offerings. *Re-verify features and ownership at each link — this churns.*

| Tool | OSS / SaaS | Gateway highlights |
|---|---|---|
| **LiteLLM** | OSS core + enterprise | OpenAI-compatible proxy to 100+ models; virtual keys, per-key budgets + rate limits, load-balancing, automatic fallback/retry, Redis caching, spend tracking. The common OSS default. |
| **Portkey** | OSS gateway + SaaS | Routes to many providers; conditional routing, failover, **circuit breakers**, canary, semantic cache, 50+ guardrails, virtual keys, budgets. |
| **Cloudflare AI Gateway** | SaaS (free core) | In front of 20+ providers; exact-match caching, rate limiting, dynamic routing, DLP, analytics, spend limits. |
| **Kong AI Gateway** | OSS + enterprise | AI Proxy plugins; latency/usage/semantic load-balancing, retries+fallback, OpenTelemetry token/latency/cost observability. |
| **OpenRouter** | SaaS aggregator | One endpoint → 400+ models / 60+ providers; provider routing by cost/throughput, model fallback, bring-your-own-key. |
| **Helicone** | OSS + SaaS | Observability + gateway; 1-line routing, caching, rate limiting, cost analytics. *(Reported mid-acquisition at this snapshot — verify maintenance state.)* |
| **Vercel AI Gateway** | SaaS (+ OSS AI SDK) | One endpoint → hundreds of models; budgets, load-balancing, fallbacks, uptime/latency routing. |
| **AWS Bedrock / Google Vertex** | Cloud-managed | Cloud-native catalogs/gateways to ~100–200+ models; built-in intelligent routing within model families. |

The durable selection logic mirrors [Module 7's build-vs-buy](../part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md):
**self-host an OSS gateway** (LiteLLM, Portkey, Kong) when you want control,
on-prem, or no per-request markup; **use a SaaS/cloud gateway** when you want it
managed and are willing to trade some control for less operational burden. Either
way, the *pattern* — one chokepoint — is what matters; the vendor is replaceable
precisely because the gateway makes everything behind it replaceable.

---

## Why the chokepoint compounds

The reason the gateway is the *first* thing to stand up in a serious LLM
deployment: nearly every other lesson in this module plugs into it.

- Reliability ([lesson 03](03-reliability-engineering.md)) — retries, fallback
  chains, and circuit breakers are gateway features.
- Observability ([lesson 02](02-observability-and-tracing.md)) — the gateway logs
  every call centrally.
- Cost governance ([lesson 05](05-ops-at-scale.md)) — attribution and *hard*
  budget caps live at the gateway (because provider budgets are often only soft
  alerts).
- Governance ([Module 12](../part-12-governance/05-operationalizing-governance.md))
  — PII redaction and policy-as-code are enforced at the chokepoint.

This is also the **central-platform-team** pattern ([lesson 05](05-ops-at-scale.md)):
the platform team owns the gateway, and product teams get resilience, logging,
budgets, and redaction "for free" by routing through it. **Governance centralized,
consumption decentralized** — and the gateway is the enforcement point that makes
that split real.

`★ Insight ─────────────────────────────────────`
- **The gateway turns cross-cutting concerns into config at one chokepoint.**
  Provider swaps, fallback, caching, cost tracking, and PII redaction stop being
  per-service code and become gateway settings — which is what makes the provider
  behind it replaceable.
- **Stand up the gateway first.** Almost every other LLMOps capability —
  reliability, observability, cost caps, governance — plugs into it, and it's the
  enforcement point for the "governance centralized, consumption decentralized"
  platform model.
`─────────────────────────────────────────────────`

## Next

→ [Observability & tracing](02-observability-and-tracing.md) — seeing what your
LLM app actually did.
