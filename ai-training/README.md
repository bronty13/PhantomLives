---
title: AI Training
type: course-home
audience: builder / power-user learning to choose, run, and apply AI models well
scope: practical working knowledge of the AI model landscape and how to use it
status: living document
last_reviewed: 2026-06-26
---

# AI Training — choosing and using AI models like a pro

A self-paced curriculum for getting **genuinely good at the practical side of AI**:
knowing which model to reach for, when to pay for a frontier API vs. run something
locally, how the pieces fit together, and how to apply them without burning money
or shipping the wrong tool.

This is **not** an ML-theory course (no backprop derivations, no "build a
transformer from scratch"). It's a working practitioner's course — the knowledge
you need to make good decisions and build things that work.

It's built the same way as this repo's [`macos-mastery`](../macos-mastery/) course:
plain Markdown, no build step, mirrored into Obsidian by the repo's
`sync-md-to-obsidian.sh` (so **commit new lessons** or they won't appear in
Obsidian).

---

## ⚠️ Read this first: the landscape moves fast

The model world changes **weekly**. Every catalog in this course is a **dated
snapshot** — by the time you read it, prices will have dropped, versions will have
bumped, and a few "flagship" models will have been deprecated. The research behind
the Module 1 catalogs already caught models that were *announced but not shipped*.

So the course is deliberately structured to put the **durable skill first** and the
**perishable facts second**:

- The **decision frameworks** (how to pick a model, how to size hardware, how to
  reason about cost) age slowly — learn these.
- The **model catalogs** (which exact model, what price) age fast — treat them as a
  starting point and **verify against the provider before you commit**.

Every catalog page carries a `last_reviewed` date and a "how to re-verify" note.

---

## How to use this course

1. **Start with [Module 1 → How to Choose a Model](part-01-model-landscape/00-how-to-choose-a-model.md).** It's the spine: a task-and-constraint decision framework that the catalogs hang off of.
2. **Follow the path in [CURRICULUM.md](CURRICULUM.md).** Modules build on each other, but each lesson is self-contained.
3. **Track progress in [PROGRESS.md](PROGRESS.md).**
4. **When you actually need to pick a model**, jump to the catalog page, then re-verify the specific model's price/limits on the provider's own docs (links are in each page).

---

## Module map

| # | Module | What you'll get |
|---|---|---|
| 0 | [Orientation](part-00-orientation/00-how-to-use-this-course.md) | How the course works; the vocabulary you need before the catalogs make sense. |
| 1 | **Model Landscape** | The decision framework + dated catalogs of frontier/proprietary models and open-weight/local models, including a top-~100 local-model list with use cases. |
| 2 | **Prompt Engineering** | The durable principles, the core techniques, how prompting inverted in the reasoning-model era, advanced patterns, and reliability/security/evaluation. |
| 3 | **Retrieval-Augmented Generation (RAG)** | The pipeline and the RAG-vs-long-context-vs-fine-tuning decision; chunking, embeddings & vector stores, retrieval quality, grounded/cited generation, and evaluation/security/production. |
| 4 | **Agents & Tool Use** | When (and when not) to build an agent; tool/function calling, agent architectures & multi-agent, context engineering & memory, MCP, safety/security, and evaluating/operating agents. |
| 5 | **Evaluation** | The eval-driven-development mindset; building golden sets, the grading hierarchy, LLM-as-a-judge, reading benchmarks critically, and rigorous/continuous production eval (stats, A/B, CI, monitoring). |
| 6 | **Fine-tuning & Adaptation** | When (and when not) to fine-tune; methods (LoRA/QLoRA, SFT, DPO, RFT, distillation), the data discipline, process/tooling/serving, and the pitfalls (forgetting, safety degradation, maintenance). |
| 7 | **Cost & Latency Engineering** | The cost/latency/quality triangle; token economics, caching, model right-sizing & routing, latency engineering (TTFT/streaming/throughput), and production economics / build-vs-buy. |
| 8 | **Local Inference Deep Dive** | Running models on your own hardware end-to-end: the local stack, Ollama/LM Studio, Apple Silicon & MLX, llama.cpp/GGUF, vLLM serving, and offline integration/ops. |
| 9 | **Multimodal & Generative Media** | Beyond text-in/text-out: the modality matrix, vision & document understanding, audio/voice/realtime, image & video generation (+ licensing/provenance), local multimodal on Apple Silicon, and a capstone pipeline. |
| 10 | **Coding Agents & AI-Assisted Development** | The application most readers use daily: the autonomy ladder, plan→act→verify workflows & spec-driven development, context/steering & subagent orchestration, tools & MCP in the loop, reading SWE-bench honestly + the verification discipline, and the security failure modes (the lethal trifecta, since the agent runs code). |
| 11 | **AI Product & UX Patterns** | Making AI products *usable*: designing for probabilistic systems, streaming & perceived performance, calibrated trust & citations, human-in-the-loop & control, designing for failure, and onboarding + the feedback flywheel. The course's most durable module (built on Microsoft HAX, Google PAIR, NN/g). |
| 12 | **Governance, Safety & Compliance** | Keeping AI products on the right side of the law and of users' trust: risk-based thinking, the regulatory landscape (EU AI Act, US patchwork, NIST RMF, ISO 42001), data privacy & training-data provenance, documentation/accountability, risk assessment & red-teaming, and operationalizing a governance program. |
| 13 | **LLMOps / Productionization & Observability** | Running it all in production: how LLMOps inverts MLOps, the LLM gateway pattern, observability & tracing (the trace/span model, OpenTelemetry GenAI), reliability engineering (200-is-not-the-contract), the deploy/improve lifecycle (prompt versioning, eval gates, gradual rollout, model migration), and ops at scale (secrets, cost governance, PII, the platform team). |

> 🎓 **The curriculum is complete — all 14 modules (0–13, 78 lessons).** The full arc from
> choosing a model to running the whole stack locally, then multimodal & generative media,
> AI-assisted software development, product/UX, governance, and operating it all in production.
> See [CURRICULUM.md](CURRICULUM.md) for the lesson index and [HANDOFF.md](HANDOFF.md) to extend
> or refresh it — the perishable content (model catalogs, the coding-tool landscape, the
> regulatory timeline, the LLMOps tooling) should be re-verified against the primary sources on
> the cadence each lesson notes.

---

## Current contents

**Module 1 — Model Landscape**
- [How to Choose a Model](part-01-model-landscape/00-how-to-choose-a-model.md) — the task × constraint decision framework. **Start here.**
- [Frontier & Proprietary Models](part-01-model-landscape/01-frontier-proprietary-models.md) — Claude, GPT, Gemini, Grok, Llama, Mistral, Nova, Command, DeepSeek, Qwen, and the niche players, with best-use guidance.
- [The Open-Weight / Local Ecosystem](part-01-model-landscape/02-open-weight-local-ecosystem.md) — quantization, hardware sizing, runtimes (Ollama/MLX/llama.cpp/vLLM), licensing traps, how to pick by hardware budget.
- [Top ~100 Local Models](part-01-model-landscape/03-top-100-local-models.md) — a categorized, popularity-anchored catalog with one-line use cases.

**Module 2 — Prompt Engineering**
- [Prompting Fundamentals](part-02-prompt-engineering/00-prompting-fundamentals.md) — what prompting is/isn't, the prerequisites, prompt anatomy, and the durable principles. **Start here.**
- [Core Techniques](part-02-prompt-engineering/01-core-techniques.md) — zero/few-shot, roles, delimiters/XML, structured output, long-context layout, and the prefill caveat.
- [Prompting in the Reasoning Era](part-02-prompt-engineering/02-prompting-reasoning-models.md) — how the playbook inverted: goal-not-steps, effort over prose, be less prescriptive.
- [Advanced Patterns](part-02-prompt-engineering/03-advanced-patterns.md) — CoT variants, self-consistency, chaining, ReAct/tool prompting, meta-prompting, templating + caching.
- [Reliability, Security & Evaluation](part-02-prompt-engineering/04-reliability-security-and-evaluation.md) — hallucination mitigation, prompt injection/jailbreak defense, and how to evaluate/iterate prompts.

**Module 3 — Retrieval-Augmented Generation (RAG)**
- [RAG Fundamentals](part-03-rag/00-rag-fundamentals.md) — the pipeline, why RAG, and the RAG vs. long-context vs. fine-tuning decision. **Start here.**
- [Ingestion & Chunking](part-03-rag/01-ingestion-and-chunking.md) — parsing, chunking strategies, size/overlap, metadata, contextual chunking.
- [Embeddings & Vector Stores](part-03-rag/02-embeddings-and-vector-stores.md) — how embeddings work, current models, vector DBs, ANN indexes.
- [Retrieval Quality](part-03-rag/03-retrieval-quality.md) — hybrid search, reranking, query transformation, contextual retrieval, GraphRAG, agentic RAG.
- [Generation & Prompt Assembly](part-03-rag/04-generation-and-prompt-assembly.md) — grounding, citations, chunk ordering ("lost in the middle"), how many chunks.
- [Evaluation, Security & Production](part-03-rag/05-evaluation-security-and-production.md) — RAG metrics & RAGAS, injection/poisoning/access-control, freshness/latency/cost/caching.

**Module 4 — Agents & Tool Use**
- [Agent Fundamentals](part-04-agents-and-tool-use/00-agent-fundamentals.md) — agent vs. workflow vs. single call, the agent loop, and the "when *not* to build one" gate. **Start here.**
- [Tool & Function Calling](part-04-agents-and-tool-use/01-tool-and-function-calling.md) — the call mechanic, tool_choice/parallel/streaming, and designing tools the model uses well.
- [Agent Architectures & Patterns](part-04-agents-and-tool-use/02-agent-architectures-and-patterns.md) — the workflow taxonomy, autonomous loops (ReAct etc.), and when multi-agent wins or hurts.
- [Context Engineering & Memory](part-04-agents-and-tool-use/03-context-engineering-and-memory.md) — context rot, compaction, context editing, memory tools, and subagent context isolation.
- [MCP & the Tool Ecosystem](part-04-agents-and-tool-use/04-mcp-and-the-tool-ecosystem.md) — what MCP is, its architecture, and its security surface.
- [Safety, Security & Reliability](part-04-agents-and-tool-use/05-safety-security-and-reliability.md) — failure modes, guardrails, human-in-the-loop, least privilege, excessive agency, the lethal trifecta.
- [Evaluating & Operating Agents](part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md) — outcome vs. trajectory eval, pass^k, agent eval sets, and observability.
- [Agent Interoperability & the A2A Protocol](part-04-agents-and-tool-use/07-agent-interoperability-and-a2a.md) — the vertical(MCP)/horizontal(A2A) split, Agent Cards & task lifecycle, opaque agents, the governance landscape, and the cross-agent trust boundary.

**Module 5 — Evaluation**
- [The Eval Mindset](part-05-evaluation/00-the-eval-mindset.md) — why eval is the moat, eval-driven development, "look at your data," offline vs. online. **Start here.**
- [Building Eval Sets](part-05-evaluation/01-building-eval-sets.md) — SMART criteria, coverage & negative examples, sourcing, labeling, train/test split, contamination.
- [Grading Methods](part-05-evaluation/02-grading-methods.md) — the reliability hierarchy: code-based, statistical/NLP metrics & their limits, classification metrics, human eval.
- [LLM-as-a-Judge](part-05-evaluation/03-llm-as-judge.md) — the three modes, writing judge prompts, the bias table + mitigations, juries, calibration.
- [Benchmarks & the Landscape](part-05-evaluation/04-benchmarks-and-the-landscape.md) — what benchmarks measure, contamination/saturation/Goodhart, reading leaderboards critically, safety eval.
- [Evaluation in Production](part-05-evaluation/05-evaluation-in-production.md) — statistics (CIs, paired deltas, pass@k vs pass^k), A/B testing, CI gating, online monitoring, tooling.

**Module 6 — Fine-tuning & Adaptation**
- [Fundamentals & When (Not) to Fine-tune](part-06-fine-tuning/00-fundamentals-and-when-to-fine-tune.md) — the adaptation spectrum and the "behavior, not knowledge" decision. **Start here.**
- [Methods](part-06-fine-tuning/01-methods.md) — full vs. PEFT (LoRA/QLoRA), SFT, preference tuning (DPO), RFT/RLVR, distillation, continued pretraining.
- [Data](part-06-fine-tuning/02-data.md) — quality over quantity, the chat-template trap, curation/decontamination, synthetic data, preference pairs.
- [Process, Tooling & Serving](part-06-fine-tuning/03-process-tooling-and-serving.md) — the workflow, hosted vs. DIY, QLoRA hardware, hyperparameters, and multi-LoRA serving.
- [Pitfalls, Risks & Maintenance](part-06-fine-tuning/04-pitfalls-risks-and-maintenance.md) — catastrophic forgetting, overfitting, safety degradation, privacy, and the re-tuning treadmill.

**Module 7 — Cost & Latency Engineering**
- [Fundamentals & the Triangle](part-07-cost-and-latency/00-fundamentals-and-the-triangle.md) — LLM economics, the cost/latency/quality triangle, the levers, and measuring. **Start here.**
- [Token Economics](part-07-cost-and-latency/01-token-economics.md) — input/output asymmetry, context as the master knob, hidden reasoning tokens, batch APIs.
- [Caching](part-07-cost-and-latency/02-caching.md) — prompt/prefix caching (the biggest lever), semantic & embedding caching, KV/CAG, the savings-vs-risk hierarchy.
- [Model Selection & Routing](part-07-cost-and-latency/03-model-selection-and-routing.md) — right-sizing, cascades (FrugalGPT), routers (RouteLLM), distillation, speculative decoding.
- [Latency Engineering](part-07-cost-and-latency/04-latency-engineering.md) — TTFT/TPOT & prefill-vs-decode, streaming, output reduction, prefix cache, and the throughput↔latency tension.
- [Production Economics & Build-vs-Buy](part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md) — cost attribution, budgets/guardrails, the API-vs-self-host math, batch, and FinOps for AI.

**Module 8 — Local Inference Deep Dive**
- [Why Local, and the Local Stack](part-08-local-inference/00-why-and-the-local-stack.md) — the engine/front-end/server mental model and hardware reality. **Start here.**
- [Ollama & LM Studio](part-08-local-inference/01-ollama-and-lm-studio.md) — the easy on-ramps: pull/run, the OpenAI-compatible server, Modelfiles, the context gotcha.
- [Apple Silicon & MLX](part-08-local-inference/02-apple-silicon-and-mlx.md) — unified memory, the fit table, mlx-lm, and why MLX is fastest on a Mac.
- [llama.cpp & GGUF](part-08-local-inference/03-llama-cpp-and-gguf.md) — the engine: quantization in depth, GPU offload, context/KV cache, GBNF grammars.
- [Serving at Scale (vLLM)](part-08-local-inference/04-serving-at-scale-vllm.md) — when to graduate, PagedAttention/continuous batching, multi-GPU, multi-LoRA serving.
- [Integration & Operations](part-08-local-inference/05-integration-and-operations.md) — the OpenAI-compatible base_url unlock, offline RAG, benchmarking, troubleshooting (+ the course capstone).

**Module 9 — Multimodal & Generative Media**
- [Multimodal Fundamentals](part-09-multimodal/00-multimodal-fundamentals.md) — the modality matrix, native-multimodal vs. pipeline-of-specialists, the pixel/second→token cost, and when text-only still wins. **Start here.**
- [Vision & Document Understanding](part-09-multimodal/01-vision-and-documents.md) — the three tiers of "reading" a document, native PDF vs. rasterize, grounding, the Claude modality/vision-pricing picture, and multimodal RAG.
- [Audio, Voice & Realtime](part-09-multimodal/02-audio-voice-and-realtime.md) — cascade vs. native speech-to-speech, the latency budget, ASR/TTS snapshots, realtime APIs, and audio-token billing.
- [Image & Video Generation](part-09-multimodal/03-image-and-video-generation.md) — the five billing shapes, control features, the four-axis licensing checklist, current image/video catalogs, and C2PA/SynthID provenance.
- [Local & On-Device Multimodal](part-09-multimodal/04-local-and-on-device.md) — what fits in unified memory, local VLMs, whisper.cpp/MLX-Whisper, local TTS, and local diffusion on Apple Silicon.
- [Putting It Together](part-09-multimodal/05-putting-it-together.md) — a document→cited-answer pipeline, multimodal cost/latency/eval at scale, and how every prior module extends.

**Module 10 — Coding Agents & AI-Assisted Development**
- [The Coding-Agent Landscape & When to Use One](part-10-coding-agents/00-the-coding-agent-landscape.md) — the autonomy ladder (autocomplete→chat→interactive→autonomous) as a leash, the tool map, and when a plain call beats an agent. **Start here.**
- [Agentic Coding Workflows](part-10-coding-agents/01-agentic-coding-workflows.md) — plan→act→verify, explore-before-implementing, spec-driven development, test-first loops, and diff review as the new bottleneck.
- [Context & Orchestration for Code](part-10-coding-agents/02-context-and-orchestration.md) — steering files (the AGENTS.md/CLAUDE.md convention), subagents & parallel fan-out, worktree isolation, multi-agent.
- [Tools & MCP in the Coding Loop](part-10-coding-agents/03-tools-and-mcp-in-the-loop.md) — the built-in tool surface (incl. language servers), MCP for dev (issues/DBs/PRs), tool search, and guardrails on destructive actions.
- [Evaluating & Trusting Coding Agents](part-10-coding-agents/04-evaluating-and-trusting-coding-agents.md) — reading SWE-bench honestly (standardized vs. vendor, contamination), the verification discipline, and outcome vs. trajectory for code.
- [Security & Failure Modes](part-10-coding-agents/05-security-and-failure-modes.md) — the lethal trifecta in a dev context, the untrusted-content→config→execution pattern, MCP tool poisoning, slopsquatting, secret leakage, and the defenses.

**Module 11 — AI Product & UX Patterns**
- [Designing for Probabilistic Systems](part-11-product-ux/00-designing-for-probabilistic-systems.md) — how AI UX inverts the deterministic-software contract (fallible/variable/latent), context errors, and the HAX/PAIR/NN/g guidance backbone. **Start here.**
- [Latency & Perceived Performance](part-11-product-ux/01-latency-and-perceived-performance.md) — the response-time limits, streaming as the highest-leverage pattern (TTFT/TPOT), skeleton/optimistic UI, and reasoning-model wait UX.
- [Trust, Transparency & Citations](part-11-product-ux/02-trust-transparency-and-citations.md) — calibrated (not maximal) trust, over/under-trust, citations as pointers-not-proof, post-hoc explanations, anthropomorphism, and provenance/disclosure.
- [Human-in-the-Loop & Control](part-11-product-ux/03-human-in-the-loop-and-control.md) — reversibility as the master variable, edit-don't-just-accept, steer mid-generation, progressive autonomy, and the rubber-stamp trap.
- [Designing for Failure](part-11-product-ux/04-designing-for-failure.md) — failure as the default state, HAX's "when wrong" guidelines, honest abstention, the clarify→suggest→escalate recovery ladder.
- [Onboarding, Expectations & the Feedback Flywheel](part-11-product-ux/05-onboarding-and-the-feedback-flywheel.md) — setting capability expectations, empty-state onboarding, and turning feedback into eval signal + a compounding data flywheel.

**Module 12 — Governance, Safety & Compliance**
- [Why Governance, and the Risk-Based Frame](part-12-governance/00-why-governance.md) — why it's an engineering concern, build-it-in-don't-bolt-it-on, risk-based tiering, and durable-vs-perishable. **Start here.**
- [The Regulatory Landscape](part-12-governance/01-the-regulatory-landscape.md) — the EU AI Act (+ its mid-2026 timeline shift), the US deregulatory-federal/state patchwork, NIST AI RMF, and ISO/IEC 42001.
- [Data Privacy & Governance](part-12-governance/02-data-privacy-and-governance.md) — durable privacy principles, the "is a model anonymous / right-to-erasure" tensions, machine unlearning, and training-data provenance.
- [Documentation & Accountability](part-12-governance/03-documentation-and-accountability.md) — the datasheet→model card→system card taxonomy, EU technical-documentation/logging requirements, AI inventories, and audit trails.
- [Risk Assessment & Red-Teaming](part-12-governance/04-risk-assessment-and-red-teaming.md) — impact assessments (FRIA/DPIA), red-teaming as governance, OWASP LLM Top 10 / MITRE ATLAS, and frontier "if-then" safety frameworks.
- [Operationalizing Governance](part-12-governance/05-operationalizing-governance.md) — the program (roles, three lines of defense), effective human oversight, incident response, and lifecycle "build-it-in" governance.

**Module 13 — LLMOps / Productionization & Observability**
- [What is LLMOps, and the Productionization Gap](part-13-llmops/00-what-is-llmops.md) — how LLMOps inverts MLOps (you ship the prompt, not weights; non-determinism; inference cost; external-API dependency), what "production-ready" means, and the inner/outer-loop lifecycle. **Start here.**
- [The LLM Gateway Pattern](part-13-llmops/01-the-llm-gateway-pattern.md) — one chokepoint in front of every model call (unified API, key management, routing, fallback, caching, cost tracking, guardrails) and the tool landscape.
- [Observability & Tracing](part-13-llmops/02-observability-and-tracing.md) — why APM isn't enough, the trace/span model for agents, the OpenTelemetry GenAI conventions (status: not yet stable), the tools, and the content-capture privacy tension.
- [Reliability Engineering](part-13-llmops/03-reliability-engineering.md) — "200 OK is not the contract," LLM-specific failure modes, retries-with-jitter, circuit breakers, fallback chains, hedging, degradation, and split (deterministic vs quality) SLOs.
- [Continuous Improvement & the Deployment Lifecycle](part-13-llmops/04-continuous-improvement-and-lifecycle.md) — silent regressions, prompt versioning (rollback = relabel), threshold-based eval gates in CI, shadow→canary→A/B rollout, model-version migration, and the feedback loop.
- [Ops at Scale](part-13-llmops/05-ops-at-scale.md) — scoped virtual keys, cost attribution + *hard* budgets (provider budgets are soft), PII/retention/ZDR/residency, and the central AI-platform-team pattern.

---

*Built and maintained inside `~/dev/PhantomLives/ai-training/`. To extend it, read [HANDOFF.md](HANDOFF.md).*
