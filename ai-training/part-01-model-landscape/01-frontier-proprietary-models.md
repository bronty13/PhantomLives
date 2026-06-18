---
title: Frontier & proprietary models
module: 01 — Model Landscape
lesson: 01
est_time: 40 min reading
last_reviewed: 2026-06-18
tags: [ai, models, frontier, proprietary, api]
---

# Frontier & proprietary models

> ⚠️ **Dated snapshot — June 2026.** Prices are per **1M tokens (input / output)** and
> approximate; promos and tiers are common. Reasoning/"thinking" models bill hidden
> reasoning tokens, so effective cost runs **above** the sticker. A few headline
> models below were *announced but not shipped* as of this writing — flagged inline.
> **Re-verify on the provider's own pricing page before you commit.** First-party
> pricing links are given per section.

Read [How to Choose a Model](00-how-to-choose-a-model.md) first — this page is the
shortlist source, not the decision-maker. A consolidated decision matrix is at the
bottom.

---

## 1. Anthropic — Claude

*Source: the repo's `claude-api` skill (authoritative current Anthropic model table,
cached 2026-06-04). Verify live with the Models API or
[platform.claude.com](https://platform.claude.com/docs/en/about-claude/models/overview).*

Claude's positioning in 2026 is **long-horizon agentic work, coding, and knowledge
work**, with strong instruction-following and a 1M-token context across the current
lineup. All current models are text + image-in; reasoning depth is controlled by an
`effort` parameter (`low`→`max`) plus adaptive "thinking."

| Model | ID | Context / Max out | Price (in/out) | Positioning |
|---|---|---|---|---|
| **Claude Fable 5** | `claude-fable-5` | 1M / 128K | $10 / $50 | Most capable widely-released model; hardest reasoning + long-horizon agentic. Thinking always on. |
| **Claude Mythos 5** | `claude-mythos-5` | 1M / 128K | $10 / $50 | Same as Fable 5; available only via Project Glasswing. |
| **Claude Opus 4.8** | `claude-opus-4-8` | 1M / 128K | $5 / $25 | Flagship Opus tier — state-of-the-art autonomous/agentic, coding, knowledge work. The default heavy-lifter. |
| **Claude Opus 4.7** | `claude-opus-4-7` | 1M / 128K | $5 / $25 | Previous-gen Opus; still excellent. |
| **Claude Sonnet 4.6** | `claude-sonnet-4-6` | 1M / 64K | $3 / $15 | Best speed/intelligence balance — the production workhorse. |
| **Claude Haiku 4.5** | `claude-haiku-4-5` | 200K / 64K | $1 / $5 | Fastest/cheapest — high-volume, latency-sensitive, simple tasks. |

- **Best uses:** Opus 4.8 — agentic coding, multi-step autonomous tasks, code review,
  deep knowledge work. Sonnet 4.6 — the balanced default for most production
  workloads. Haiku 4.5 — classification, extraction, routing, sub-second responses.
  Fable 5 — only the genuinely hardest reasoning/long-horizon problems where the
  premium pays off.
- **When to pick Claude:** strong agentic + coding behavior, careful instruction
  following, and a 1M window standard across the tier. Pick the tier by
  cost/quality: start at Sonnet, drop to Haiku for volume, climb to Opus/Fable for
  hard problems.
- **API notes (current generation):** adaptive thinking only (no fixed thinking
  budget); sampling params like `temperature` removed on the newest models;
  structured outputs, prompt caching, batches, and Managed Agents supported. See the
  `claude-api` skill for exact syntax.

---

## 2. OpenAI — GPT-5.x & o-series

The lineup moved to a **GPT-5.x** generation; the dedicated **o-series** reasoning
models still exist but are increasingly folded into GPT-5.x reasoning modes.
*Verify: [openai.com/api/pricing](https://openai.com/api/pricing/).*

| Model | Tier | Context / Max out | Price (in/out) |
|---|---|---|---|
| **GPT-5.5** | Flagship general | ~1.05M / 128K | $5 / $30 |
| **GPT-5.5 Pro** | Highest-stakes reasoning | ~1M / 128K | $30 / $180 |
| **GPT-5.4** | Prior balanced workhorse | ~1M | $2.50 / $15 |
| **GPT-5.4 mini** | Cheap/fast | ~1M | $0.75 / $4.50 |
| **GPT-5.4 nano** | Cheapest GPT-5.x | ~1M | $0.20 / $1.25 |
| **GPT-5.x-Codex** | Coding/agentic specialist | large | ~$1.75 / $14 |
| **o3 / o3-pro** | Dedicated reasoning | ~200K | $2/$8 · $20/$80 |
| **o4-mini** | Budget reasoning | ~200K | $1.10 / $4.40 |
| **GPT-4.1 / mini / nano** | Legacy long-context / ultra-cheap | 1M | $2/$8 · $0.40/$1.60 · **$0.10/$0.40** |

- **Best uses:** GPT-5.5 — broad top-tier general + coding + agentic orchestration.
  GPT-5.x-Codex — autonomous coding agents. o4-mini — cheap math/logic at scale.
  GPT-4.1/5.4 nano — among the cheapest credible models for high-volume
  classification/extraction.
- **When to pick:** the broadest ecosystem (tools, structured outputs, Responses API,
  huge third-party support) and strong all-around quality. Pick 5.5 **Pro** only when
  hard-problem accuracy justifies the steep output price.
- **Tiers/discounts:** Batch −50%, Flex (cheaper/variable latency), Priority (~2.5×
  for speed), cached input −90%. GPT-5.5 charges 2×/1.5× over 272K-token prompts.
- *Note: GPT-5.1 retired from ChatGPT Mar 2026; Sora 2 video API sunsets Sep 24,
  2026.*

---

## 3. Google DeepMind — Gemini

Tiered: **Pro** (flagship), **Flash** (workhorse), **Flash-Lite** (cheap), **Nano**
(on-device). Strongest at **huge context (up to 2M)** and **native multimodal**
(image, audio, **video** in). *Verify:
[ai.google.dev/gemini-api/docs/pricing](https://ai.google.dev/gemini-api/docs/pricing).*

| Model | Tier | Context | Modalities | Price (in/out) |
|---|---|---|---|---|
| **Gemini 3.1 Pro** | Flagship | 2M | text, image, audio, video in | $2/$12 (<200K); $4/$18 (>200K) |
| **Gemini 3.5 Flash** | Balanced workhorse | 1M | multimodal | $1.50 / $9 |
| **Gemini 3 Flash** | Fast/cheap | ~1.05M | multimodal | $0.50 / $3 |
| **Gemini 3.1 Flash-Lite** | Cheapest hosted | 1M | multimodal | $0.25 / $1.50 |
| **Gemini Nano** | On-device (Android/Chrome) | small | text + some | free / on-device |
| **Gemini 3.5 Pro** | *announced May 19; NOT yet shipped mid-June* | 2M target | + "Deep Think" | TBD |

- **Best uses:** the go-to for **long-context** (2M is the largest production window)
  and **native video/audio understanding**. Flash 3.5 — high-throughput agentic +
  coding at lower cost. Nano — truly bundled on-device inference.
- **When to pick:** genuinely long-context work, multimodal-heavy (esp. video/audio),
  or you're in Google Cloud/Vertex.
- *Flag: Gemini 3.5 Pro + "Deep Think" were pre-release; don't present as live.*

---

## 4. xAI — Grok

*Verify: [docs.x.ai/developers/models](https://docs.x.ai/developers/models).*

| Model | Tier | Context | Price (in/out) |
|---|---|---|---|
| **Grok 4.3** | Flagship | 1M | $1.25 / $2.50 (cached in $0.20) |
| **Grok 4.20** | Prior flagship | 2M | $2 / $6 |
| **Grok 4.1 Fast** | Budget / long-context | 2M | $0.20 / $0.50 |
| **Aurora / Grok Imagine** | Image/video gen | — | — |

- **Best uses:** strong reasoning at a **notably low flagship price** ($2.50 output
  undercuts most rivals); cost-sensitive agentic/reasoning; real-time X/Twitter-
  grounded queries; a less-filtered assistant.
- **When to pick:** frontier-ish reasoning cheaply, or live X data. Weaknesses:
  less-mature tooling/ecosystem than OpenAI/Google.

---

## 5. Meta — Llama 4 *(open-weight, but API-hosted everywhere)*

Natively multimodal **MoE**; headline is extreme context. **Open-weight under the
Llama Community license** (commercial OK for most; >700M-MAU companies need a special
license). Also runs locally — see [the local pages](03-top-100-local-models.md).
*Source: [ai.meta.com/blog/llama-4-multimodal-intelligence](https://ai.meta.com/blog/llama-4-multimodal-intelligence/).*

| Model | Active params | Context | Notes |
|---|---|---|---|
| **Llama 4 Scout** | 17B active / 16 experts | **10M** | Longest-context open model; text+image |
| **Llama 4 Maverick** | 17B active / 128 experts | ~1M | Balanced flagship-class; text+image |
| **Llama 4 Behemoth** | 288B active | — | **NOT released** (still training) — treat "available" claims skeptically |

- **Best uses:** self-hosting / on-prem / privacy; fine-tuning; cost control at scale;
  Scout's 10M context. Available via API on Bedrock, Groq, Together, Fireworks.
- **When to pick:** you want **open weights** (data residency, customization, no lock-
  in) but also the option to call it as an API.

---

## 6. Mistral AI

French lab; mix of **open-weight** and commercial; strong on efficiency, multilingual,
and code; EU data residency. *Verify:
[mistral.ai/pricing](https://mistral.ai/pricing/).*

| Model | Tier | Price (in/out) | Notes |
|---|---|---|---|
| **Mistral Large 3 (2512)** | Flagship reasoning + multimodal | $0.50 / $1.50 | Aggressively cheap |
| **Magistral Medium** | Transparent reasoning | $2 / $5 | Multilingual reasoning |
| **Mistral Small 3** | Balanced cheap | $0.10 / $0.30 | EU residency workhorse |
| **Codestral** | Code specialist (FIM) | $0.30 / $0.90 | IDE autocomplete |
| **Ministral 8B / 3B** | Edge/on-device | $0.10/$0.10 · $0.04/$0.04 | |
| **Pixtral Large** | Vision | $2 / $6 | |

- **Best uses:** Codestral for IDE fill-in-the-middle; Large 3 for cheap strong
  reasoning; Ministral for edge; Small 3 for EU-resident cheap general work.
- **When to pick:** EU data-sovereignty, open-weight + commercial flexibility, code
  completion specifically, or strong cheap multilingual.

---

## 7. Amazon — Nova (Bedrock)

Four tiers optimized for **price/performance inside AWS**. *Source:
[AWS Nova docs](https://docs.aws.amazon.com/ai/responsible-ai/nova-micro-lite-pro/overview.html).*

| Model | Tier | Context | Price (in/out) |
|---|---|---|---|
| **Nova Premier** | Flagship multimodal | 1M | $2.50 / $12.50 |
| **Nova Pro** | Balanced multimodal (+video in) | 300K | $0.80 / $3.20 |
| **Nova Lite** | Cheap multimodal | ~300K | $0.06 / $0.24 |
| **Nova Micro** | Cheapest, text-only | 128K | **$0.035 / $0.14** |

- **Best uses:** Micro/Lite — extremely cheap high-volume classification, extraction,
  routing. Pro/Premier — multimodal (incl. video) inside AWS pipelines.
- **When to pick:** you're on AWS/Bedrock and want lowest cost-per-token with native
  IAM/VPC. Nova Micro is among the cheapest credible models anywhere.

---

## 8. Cohere — Command (enterprise RAG)

The **Command + Embed + Rerank** stack is built to work together for grounded, cited
retrieval. *Verify: [docs.cohere.com/docs/models](https://docs.cohere.com/docs/models).*

| Model | Tier | Context | Price (in/out) |
|---|---|---|---|
| **Command A+** (May 2026) | Flagship agentic/tool-use/multimodal | large | contact sales |
| **Command A** | Balanced enterprise | ~256K | $2.50 / $10 |
| **Command R+ / R / R7B** | RAG tiers | 128K | lower |

- **Best uses:** **retrieval-augmented generation with inline citations**, enterprise
  tool-use/agents, multilingual, private/on-prem deployment. Pair with Embed v3 +
  Rerank v3.
- **When to pick:** enterprise RAG and grounded Q&A where citations, multilingual
  coverage, and privacy matter more than leaderboard scores.

---

## 9. DeepSeek *(open-weight lineage, hosted API)*

As of Apr 24, 2026, **DeepSeek V4 replaced the entire prior lineup** (old aliases
error after Jul 24, 2026). Famous for **frontier quality at rock-bottom prices**.
*Verify: [api-docs.deepseek.com/quick_start/pricing](https://api-docs.deepseek.com/quick_start/pricing).*

| Model | Params | Context / Max out | Price (in/out) |
|---|---|---|---|
| **DeepSeek V4-Pro** | 1.6T total / 49B active MoE | 1M / 384K | ~$0.44/$0.87 promo (list ~$1.74/$3.48) |
| **DeepSeek V4-Flash** | 284B / 13B active | 1M / 384K | $0.14 / $0.28 |

- **Best uses:** best **cost-per-quality** for reasoning/coding; huge context at
  trivial price; cache-friendly long-context agents. Weights open (MIT) — also
  runnable locally if you have the hardware.
- **When to pick:** budget dominates and a Chinese-hosted API is acceptable (or you
  self-host). Strong math/code. Mind data-governance/compliance. *R2 has NOT shipped
  — treat R2 claims as rumor.*

---

## 10. Alibaba — Qwen

Historically the leading open-weight family, but the **newest flagship is API-only**;
smaller Qwen models remain open-weight. *Verify:
[Alibaba Model Studio pricing](https://www.alibabacloud.com/help/en/model-studio/model-pricing).*

| Model | Tier | Context | Price (in/out) | Weights |
|---|---|---|---|---|
| **Qwen3.7-Max** | Flagship agent/coding | 1M | $1.25/$3.75 promo (list $2.50/$7.50) | Closed |
| **Qwen3-Max** | Prior flagship | 262K | $0.78 / $3.90 | Closed |
| **Qwen-Flash** | Cheap | — | $0.05 / $0.40 | varies |
| **Qwen3 open models** | self-host | varies | self-host | **Open** |

- **Best uses:** Qwen3.7-Max — coding, productivity, long-horizon agents; strong
  multilingual (esp. Chinese). Open Qwen3 weights for self-host/fine-tune.
- **When to pick:** a top open-weight base (smaller Qwen3) OR a cheap strong agentic
  flagship via Alibaba Cloud. Same data-governance caveat as DeepSeek.

---

## 11. Niche / specialist players

- **Perplexity Sonar** — search-grounded models with live web retrieval + inline
  citations: `sonar` (cheap), `sonar-pro`, `sonar-reasoning-pro`,
  `sonar-deep-research`. **Best for:** anything needing fresh web facts with
  citations. *([docs.perplexity.ai](https://docs.perplexity.ai/docs/sonar/models))*
- **AI21 — Jamba (Large 1.7)** — hybrid SSM/Transformer, 256K context, open family.
  **Best for:** efficient long-context, document-heavy enterprise tasks.
- **Reka** — multimodal-first lab; strong audio/video understanding; less consumer-
  visible but capable.

---

## Consolidated decision matrix (June 2026)

| Task | First picks (proprietary) |
|---|---|
| **General / default** | Claude Sonnet 4.6, GPT-5.5, Gemini 3.1 Pro |
| **Coding — agentic** | Claude Opus 4.8, GPT-5.x-Codex, Gemini 3.5 Flash |
| **Coding — IDE autocomplete** | Codestral |
| **Reasoning / math** | Claude (max effort) / Fable 5, GPT-5.5 Pro / o3-pro, DeepSeek V4-Pro |
| **Long-context analysis** | Gemini 3.1 Pro (2M), Claude (1M), DeepSeek V4 (1M) |
| **Cheap high-volume extraction** | Nova Micro/Lite, GPT nano, Gemini Flash-Lite, Claude Haiku 4.5, DeepSeek V4-Flash |
| **Multimodal / vision** | Gemini 3.1 Pro (video/audio), Claude, GPT-5.5, Nova Premier |
| **Real-time / low-latency** | Gemini Flash/Flash-Lite, Claude Haiku, GPT-5.4 mini, Nova Lite |
| **On-device** | Gemini Nano; Ministral 3B/8B (or self-host an open model) |
| **Search-grounded / fresh facts** | Perplexity Sonar, Grok 4.3 |
| **Enterprise RAG with citations** | Cohere Command A+ (+ Embed/Rerank) |
| **Cheapest frontier-ish quality** | Grok 4.3, DeepSeek V4, Mistral Large 3 |
| **EU data residency** | Mistral |
| **Open weights but want an API** | Llama 4, Qwen, DeepSeek (all API-hosted *and* downloadable) |

---

## How to re-verify this page

Model prices/IDs change monthly. To refresh: (1) for **Claude**, re-run the
`claude-api` skill; (2) for everyone else, check the first-party pricing link in each
section; (3) bump `last_reviewed` and log the change in
[../CHANGELOG.md](../CHANGELOG.md). Watch especially for promo prices reverting
to list, deprecations, and the "announced-but-unshipped" models shipping.

## Next

→ [The Open-Weight / Local Ecosystem](02-open-weight-local-ecosystem.md) ·
→ [Top ~100 Local Models](03-top-100-local-models.md)
