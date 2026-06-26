# Changelog — AI Training

All notable changes to this curriculum. Dates are absolute (this content goes
stale, so the date matters).

## 2026-06-26 — Module 13 (LLMOps / Productionization & Observability) built — CURRICULUM COMPLETE (0–13, 76 lessons)

The operational synthesis module — how to *run* LLM apps in production, connecting the threads from
M5 (eval), M7 (cost), M8 (serving), M11 (UX), and M12 (governance).

- **Module 13 — LLMOps / Productionization & Observability** (6 lessons), durable-principle-first
  with dated tooling snapshots:
  - `00-what-is-llmops` — the productionization gap; **LLMOps inverts MLOps** (you ship the prompt/
    context/tool config not weights; non-determinism inherent; cost is inference-dominated forever;
    hard external-API dependency; evals replace fixed metrics — but CI/CD/versioning/monitoring carry
    over, LLMOps *extends* not replaces); production-ready pillars; the inner/outer-loop lifecycle.
  - `01-the-llm-gateway-pattern` — **the chokepoint**: one internal endpoint in front of every model
    call centralizing unified API / keys / routing / fallback / rate-limit / caching / cost / logging
    / guardrails; tool roundup (LiteLLM, Portkey, Cloudflare, Kong, OpenRouter, Helicone, Vercel,
    Bedrock/Vertex); ties M7 routing + M8 serving (the gateway sits in front of either).
  - `02-observability-and-tracing` — why APM is blind (semantic payload + tree-not-request); the
    trace/span model; **OpenTelemetry GenAI conventions status = Development/NOT stable** (flagged as
    a re-verify item); content-capture is opt-in by spec; tools; the PII/redaction tension (ties
    M4 trajectory eval, M11 trust, M12 data governance).
  - `03-reliability-engineering` — **"a 200 OK is not the contract"**; LLM failure modes (multi-
    dimensional 429, 529≠rate-limit, refusals-inside-200, streaming-after-200, schema-valid-but-wrong);
    retries-with-**jitter** (jitter = load safety, honor Retry-After), circuit breakers, fallback
    chains, hedging on TTFT, graceful degradation, capacity/provisioned-throughput, and **split SLIs**
    (deterministic vs quality/multi-trial).
  - `04-continuous-improvement-and-lifecycle` — **silent regressions** as the enemy; prompt versioning
    (rollback = relabel); **eval gates = threshold-and-baseline relative, not pass/fail** (calibrate a
    judge to 85–90% before it blocks; prod failures → permanent regression tests); shadow→canary→A/B
    watching *quality* signals; pin the full behavioral surface (prompt+model+RAG+tools) as one rollback
    unit; **pin dated model snapshots not aliases** + deprecation lifecycle (ties M1, M5, M10).
  - `05-ops-at-scale` — **govern-at-center/consume-at-edge**; scoped virtual keys + referenced/rotatable
    secrets; cost attribution + **hard gateway budgets (provider budgets are SOFT alerts)**; PII
    redaction/retention TTL + provider no-train/ZDR/residency posture (re-verify); the central
    AI-platform-team pattern; capstone tying the whole course together.
- Sourcing per HANDOFF pipeline: one live-web research agent (LLMOps tooling + practices). Durable
  engineering principles (backoff/jitter, circuit breakers, hedging, SLOs) anchored on classic
  distributed-systems references; tool names/versions/provider terms flagged as dated June-2026
  snapshots with a re-verify list. **The research agent flagged + excluded two hallucinated "facts"
  (a non-existent arXiv ID, a fictional covered-model rule)** — folded into lesson 00 as a live
  "verify citations" LLMOps lesson. Scratch research file used for synthesis then removed (not a lesson).
- **Bookkeeping:** CURRICULUM adds the Module 13 table + the "complete (0–13, 76 lessons)" banner;
  README adds the module-map row, contents block, and updated banner; PROGRESS lists Module 13. All
  internal links verified.

## 2026-06-26 — Modules 11 & 12 built — CURRICULUM COMPLETE (0–12, 70 lessons)

The final two candidate modules, built together (they cross-reference each other). The course
now spans 13 modules.

- **Module 11 — AI Product & UX Patterns** (6 lessons) — the course's most DURABLE module
  (backbone: Microsoft HAX 18 guidelines, Google PAIR, Nielsen Norman Group; few catalogs to
  rot):
  - `00-designing-for-probabilistic-systems` — how AI UX inverts the deterministic-software
    contract (fallible/variable/latent), the AI-native "context error," failure as the design
    surface, and the guidance backbone.
  - `01-latency-and-perceived-performance` — the 0.1/1/10s response-time limits + Doherty 400ms,
    streaming as the highest-leverage pattern (TTFT vs TPOT), skeleton/optimistic UI, reasoning-
    model wait UX (collapse raw CoT). Cross-links M7.
  - `02-trust-transparency-and-citations` — **calibrated (not maximal) trust**, over/under-trust,
    citations as pointers-not-proof + hallucinatable, post-hoc/unfaithful explanations,
    anthropomorphism, provenance (C2PA/Art.50 → M9/M12).
  - `03-human-in-the-loop-and-control` — **reversibility as the master variable** (gate at the
    tool), edit-don't-accept (HAX G9), mid-generation steering, progressive autonomy, Shneiderman
    2-axis, the rubber-stamp trap. Cross-links M4/M10.
  - `04-designing-for-failure` — failure as default, HAX "when wrong" (G8–G11), honest abstention
    > confident hallucination, ICE pattern, user-bandwidth, clarify→suggest→escalate, no fake
    transparency. Cross-links M2/M3/M5.
  - `05-onboarding-and-the-feedback-flywheel` — expectation-setting (HAX G1/G2), empty-state +
    suggested prompts, frictionless feedback, **the feedback flywheel as dual-purpose eval +
    preference data** (M5/M6).
- **Module 12 — Governance, Safety & Compliance** (6 lessons) — the most FACT-SENSITIVE module;
  durable-frameworks-first, every dated item status-flagged:
  - `00-why-governance` — governance as an engineering concern, **build-it-in-don't-bolt-it-on**,
    risk-based tiering as the durable spine, and the durable-vs-perishable sorting rule.
  - `01-the-regulatory-landscape` — EU AI Act risk tiers + the **mid-2026 "Digital Omnibus"
    timeline DELAY** (used as a live "the trackers lagged → re-verify the primary source" lesson),
    the US deregulatory-federal/state-patchwork, NIST AI RMF (GOVERN/MAP/MEASURE/MANAGE), ISO/IEC
    42001. Heavily dated + a "how to re-verify" cadence.
  - `02-data-privacy-and-governance` — durable privacy principles (lawful basis/purpose-limitation/
    minimization), the "is a model anonymous" + right-to-erasure tensions, machine unlearning as
    risk-reduction-not-deletion, training-data provenance. Cross-links M6/M9.
  - `03-documentation-and-accountability` — datasheet→model card→system card taxonomy (disaggregated
    performance as a fairness control), EU Annex IV/Art.12 logging, **AI inventories** as the system
    of record, audit trails/transparency reports. Cross-links M5/M7.
  - `04-risk-assessment-and-red-teaming` — impact assessments (FRIA/DPIA/ISO 42005), red-teaming as
    sociotechnical governance, **OWASP LLM Top 10 + MITRE ATLAS** as the checklist (consolidates the
    M2/M3/M4/M10 security threads), frontier capability-threshold "if-then" frameworks.
  - `05-operationalizing-governance` — the program (exec owner, three lines of defense), **effective
    human oversight** (Art.14 = intervene/halt capability, not rubber-stamp — ties M10/M11), incident
    response + reporting clocks, lifecycle "build-it-in" governance + continuous monitoring.
- Sourcing per HANDOFF pipeline: two parallel live-web research agents (AI-product/UX design guidance;
  the regulatory/standards landscape). Product/UX treated as durable-design (decade-stable HAX/PAIR/
  NN/g) with example-light confidence; governance treated as perishable with every date/penalty/
  version status-flagged and a re-verify cadence. The governance agent's scratch research file
  (`ai-governance-safety-compliance.md`) was used for synthesis then removed (not a lesson).
- **Bookkeeping:** CURRICULUM adds both module tables + the "curriculum complete (0–12, 70 lessons)"
  banner; README adds two module-map rows, two contents blocks, and the completion banner; PROGRESS
  lists both modules. All internal links across M11+M12 verified (they cross-reference each other,
  hence one combined commit).

## 2026-06-26 — Module 10 (Coding Agents & AI-Assisted Development) built

- **Module 10 — Coding Agents & AI-Assisted Development** (6 lessons), durable-first; takes the
  Module 4 agent foundations into the application most readers use daily:
  - `00-the-coding-agent-landscape.md` — the **autonomy ladder** (autocomplete → IDE chat →
    interactive agent → autonomous background agent) framed as a *leash, not a quality ranking*,
    a June-2026 tool map (Claude Code, Copilot, Cursor, Windsurf/Cognition, Codex, Antigravity/
    Jules, Devin, Kiro, …) with the consolidation caveat, and the "when a plain call beats an
    agent" gate (cross-links M4).
  - `01-agentic-coding-workflows.md` — the plan→act→verify loop, explore-before-implementing /
    plan mode, **spec-driven development** (Kiro, GitHub Spec Kit), test-first loops as the
    deterministic signal, and **diff review as the new bottleneck** (the "review sandwich").
  - `02-context-and-orchestration.md` — steering files and the emerging **AGENTS.md** cross-tool
    standard (+ CLAUDE.md, keep-it-short/context-rot), layered scope + auto-memory, subagents &
    parallel fan-out (context isolation / least privilege / cost), worktree isolation for
    parallel edits, and when multi-agent is/ isn't worth it (cross-links M4, M7).
  - `03-tools-and-mcp-in-the-loop.md` — the built-in tool surface (incl. the language-server
    "symbols not strings" point), MCP for dev (issues/DBs/PRs/observability), tool search for
    scaling, and the defense-in-depth guardrails (permission rules, OS sandbox, checkpoints/VCS,
    hooks) with reversibility as the leash criterion.
  - `04-evaluating-and-trusting-coding-agents.md` — reading **SWE-bench** honestly (Verified
    saturation + memorization evidence, **standardized score ≠ vendor self-report**,
    contamination-free benchmarks tell a humbler story), the verification discipline (tests as
    spec, build/type/run, read the diff), and outcome-vs-trajectory / test-gaming for code
    (cross-links M5, M4).
  - `05-security-and-failure-modes.md` — the highest-stakes lesson (the agent runs code): the
    **lethal trifecta** in a dev context, the recurring **untrusted-content → rewrites-config →
    auto-approve → execution** pattern (grounded in the 2025–26 CVEs), MCP **tool poisoning**,
    **slopsquatting** / hallucinated dependencies, secret leakage, and the lesson-03 defenses
    mapped to "break one leg of the trifecta."
- Sourcing per HANDOFF pipeline: Claude/Claude Code facts via the **`claude-api` skill** +
  the **`claude-code-guide`** agent (authoritative; the agent's stale "Claude 3.5 Sonnet
  default" model claims were corrected to the skill's facts — Opus 4.8 flagship, `xhigh`
  effort default in Claude Code); the broader tool landscape, SWE-bench leaderboard, and
  security incidents via a live-web research agent. **Unverified mid-2026 SWE-bench model
  scores were deliberately NOT asserted** — the lesson teaches the standardized-vs-vendor /
  contamination *literacy* with first-party-confirmed baselines instead.
- **Bookkeeping:** CURRICULUM adds the Module 10 table + revises the completion banner
  (Modules 0–10; remaining candidates = product/UX, governance); README adds the module-map
  row, contents block, and updated banner; PROGRESS lists Module 10. All internal links
  relative and verified.

## 2026-06-26 — Module 9 (Multimodal & Generative Media) built — first post-core extension

- **Module 9 — Multimodal & Generative Media** (6 lessons), durable-first; the module
  where the course's "text in, text out" assumption finally drops, with every prior module
  shown to extend cleanly:
  - `00-multimodal-fundamentals.md` — the modality matrix (which in/out modalities, and that
    no single model fills the grid), native-multimodal vs. pipeline-of-specialists, the
    pixel/second→token cost (ties to M7 token economics), and the "when text-only still wins"
    gate (echoes M4's when-not-to-build discipline).
  - `01-vision-and-documents.md` — the three tiers of "reading" a document (plain OCR /
    layout-aware / LLM reasoning), native PDF vs. rasterize, grounding/bounding-boxes, the
    **authoritative Claude lineup modality + vision-pricing table** (text+image-in only, no
    image/video generation, no audio; high-res 2576px on Opus 4.7+/Fable 5; native PDF +
    citations), a snapshot of other frontier vision models + document-specialist OCR tools,
    and multimodal RAG (cross-links M3).
  - `02-audio-voice-and-realtime.md` — cascade (STT→LLM→TTS) vs. native speech-to-speech, the
    sub-800ms latency budget (cross-links M7 latency), ASR/TTS snapshots, OpenAI Realtime /
    Gemini Live, WebRTC/WebSocket transport, VAD + barge-in, and the audio-token cost trap.
  - `03-image-and-video-generation.md` — the five billing shapes, control features (the
    instruction-editing "Nano Banana/Kontext" paradigm), the four-axis commercial licensing
    checklist, image + video catalogs (flagging the Imagen-deprecated / Sora-EOL / FLUX.2-flagship
    / Midjourney-no-API corrections + the near-term shutdown cluster), and C2PA + SynthID
    provenance with the EU AI Act Art. 50 (2026-08-02) hook.
  - `04-local-and-on-device.md` — Apple-Silicon-weighted: the unified-memory fit table, local
    VLMs (Qwen3-VL, Gemma 3, Moondream, SmolVLM) via llama.cpp/Ollama/LM Studio/MLX-VLM,
    whisper.cpp vs. MLX-Whisper (ties to transcribe/ + M8), local TTS (Kokoro/Piper/CSM), and
    local diffusion (Draw Things/mflux/ComfyUI); cross-links M8's base_url unlock.
  - `05-putting-it-together.md` — a document→cited-answer pipeline capstone, multimodal
    cost/latency at scale (resolution/duration as the master knob, right-sizing, caching,
    batching — all cross-linked to M7), multimodal evaluation (OCR=code-graded, generated
    media=LLM-judge/human, voice=two-layer — cross-links M5), and a recap of how M1–M8 extend.
- Sourcing per HANDOFF pipeline: Anthropic/Claude facts via the **`claude-api` skill**
  (authoritative); everyone else via two parallel live-web research agents (frontier vision +
  image/video gen; audio/voice/realtime + local multimodal). Every model/price flagged as a
  dated June-2026 snapshot; announced-but-unshipped and imminent-shutdown items called out.
- **Bookkeeping:** CURRICULUM adds the Module 9 table and revises the completion banner
  (Modules 0–9, next = Module 10 Coding Agents); README adds the module-map row, the contents
  block, and bumps `last_reviewed`; PROGRESS lists Module 9. All internal links relative.

## 2026-06-18 — Module 8 (Local Inference Deep Dive) built — CORE CURRICULUM COMPLETE

- **Module 8 — Local Inference Deep Dive** (6 lessons), hands-on, Apple-Silicon-weighted;
  cross-linked to Modules 1 (local ecosystem), 3 (offline RAG), 6 (multi-LoRA serving,
  chat-template trap), 7 (caching, throughput↔latency, build-vs-buy economics):
  - `00-why-and-the-local-stack.md` — the engine/front-end/server mental model (llama.cpp is
    the engine; Ollama/LM Studio bundle it; MLX is Apple's engine; vLLM is the prod server),
    hardware reality (unified memory vs VRAM), and the module roadmap.
  - `01-ollama-and-lm-studio.md` — the easy on-ramps: pull/run/ps, quant tags, OpenAI-compat
    server (:11434 / :1234), Modelfiles, the 4096-default-context gotcha; LM Studio's dual
    GGUF/MLX engine.
  - `02-apple-silicon-and-mlx.md` — unified memory, the RAM→model-size fit table, the
    iogpu.wired_limit knob, mlx-lm (generate/chat/server/convert), why MLX beats llama.cpp on
    M-series, and the transcribe/ MLX-Whisper tie-in.
  - `03-llama-cpp-and-gguf.md` — the engine: GGUF, quantization in depth (K-quants S/M/L,
    Q4_K_M sweet spot, bigger=slower, I-quants + imatrix), -ngl offload, context/KV cache,
    GBNF grammars / --json-schema, backends.
  - `04-serving-at-scale-vllm.md` — when to graduate, vllm serve, PagedAttention + continuous
    batching, tensor/pipeline parallel, AWQ/GPTQ/FP8, multi-LoRA, engine contrast (TGI now
    maintenance-mode), VRAM rules; Linux+GPU caveat.
  - `05-integration-and-operations.md` — the OpenAI-compatible base_url unlock (runs all of
    M2–M7 locally), local tool calling + structured output, fully-offline RAG, GUIs,
    benchmarking (tokens/sec + TTFT), OOM/slow/quality troubleshooting, privacy/security; and
    the **course capstone** recap + "where to go from here."
- Sourcing: primary docs cited inline (Ollama, LM Studio, MLX/mlx-lm, ggml-org/llama.cpp,
  vLLM, Open WebUI; quant-eval preprint). Versions/ports/tokens-per-sec flagged as dated.
- **Course-completion bookkeeping:** CURRICULUM marks the core curriculum (Modules 0–8)
  complete with an extend-it pointer; README adds a completion banner + Module 8 contents;
  PROGRESS lists Module 8. All links verified.

## 2026-06-18 — Module 7 (Cost & Latency Engineering) built

- **Module 7 — Cost & Latency Engineering** (6 lessons), durable-first; the operational
  synthesis cross-linking Modules 1 (model tiers), 2/3 (caching), 4 (model-per-step, step
  caps, observability), 5 (eval validates a cheaper model held quality), 6 (distillation):
  - `00-fundamentals-and-the-triangle.md` — LLM economics (output≫input, stateless re-billing,
    hidden reasoning tokens), the cost/latency/quality triangle, the lever map, measure-first.
  - `01-token-economics.md` — input/output asymmetry, context as the master knob (quadratic
    growth), hidden reasoning tokens, long-context premiums, token-cutting levers, batch APIs
    (~50% off async).
  - `02-caching.md` — prompt/prefix caching (prefix-match invariant, ~90% vs OpenAI ~50% reads,
    break-even, invalidators), semantic/response caching (false-hit risk + thresholds),
    embedding caching, KV/CAG; the savings-vs-risk hierarchy.
  - `03-model-selection-and-routing.md` — right-sizing (cheapest model that passes eval),
    cascades (FrugalGPT), routers (RouteLLM), distillation, speculative decoding; the layered
    compounding cost architecture.
  - `04-latency-engineering.md` — TTFT/TPOT + prefill-vs-decode, generation-dominates,
    streaming (perceived) vs output-reduction (real), model/effort, prefix-cache TTFT,
    parallelism, reasoning-model TTFT, and the self-host throughput↔latency batching tension.
  - `05-production-economics-and-build-vs-buy.md` — cost attribution (tags/gateway/OTel),
    budgets & enforcement (gateway blocks; agent caps), the API-vs-self-host decision
    (utilization is make-or-break; break-even varies ~100×; hybrid routing), batch, autoscaling,
    FinOps for AI.
- Sourcing: primary sources cited inline (FrugalGPT, RouteLLM, CAG, GPTCache papers; NVIDIA/
  Anyscale/vLLM latency+serving docs; OpenAI/Anthropic/Google pricing/caching/batch docs; the
  authoritative claude-api prompt-caching reference). Prices/discounts/break-even thresholds
  flagged as dated/utilization-dependent — taught as mechanisms and ratios, not fixed numbers.
  Updated README, CURRICULUM (status ✅), PROGRESS. All links verified.

## 2026-06-18 — Module 6 (Fine-tuning & Adaptation) built

- **Module 6 — Fine-tuning & Adaptation** (5 lessons), durable-first; cross-linked to
  Modules 1 (model choice), 2 (prompting), 3 (RAG = the knowledge alternative), and 5
  (eval, required before/after a fine-tune):
  - `00-fundamentals-and-when-to-fine-tune.md` — the adaptation spectrum
    (prompt→RAG→fine-tune→continued-pretraining), the durable "behavior, not knowledge"
    framing (OpenAI two-axis matrix; open-book-exam vs studying), when fine-tuning helps vs
    when not to, the maintenance burden, and the dated provider-availability reality
    (OpenAI winding down, Claude via Bedrock, Gemini via Vertex, open-weight DIY).
  - `01-methods.md` — full vs PEFT (LoRA/QLoRA + swappable adapters), SFT, preference tuning
    (RLHF/DPO + KTO/ORPO/IPO), RFT/RLVR (verifiable rewards), distillation, continued
    pretraining, and high-level hyperparameters; a method-picker table.
  - `02-data.md` — quality > quantity (LIMA), how-much ranges, the chat-template match (the
    #1 silent failure), curation/decontamination, diversity + general-data mixing, synthetic
    data & distillation (with licensing caveats), preference triples, train/val split.
  - `03-process-tooling-and-serving.md` — the prompt/RAG-first workflow (eval before
    training), hosted vs DIY frameworks (TRL/PEFT, Axolotl, Unsloth, LLaMA-Factory,
    torchtune), QLoRA hardware table, practical hyperparameters, eval (incl. safety), and
    serving (merged weights vs multi-LoRA: vLLM/LoRAX).
  - `04-pitfalls-risks-and-maintenance.md` — catastrophic forgetting, overfitting, **safety/
    alignment degradation even on benign data** (Qi et al.; emergent misalignment — LoRA
    doesn't immunize), privacy/memorization, model staleness & the re-tuning treadmill,
    cost reality, and the prompt→RAG→fine-tune→distill alternatives recap.
- Sourcing: primary sources cited inline (LoRA, QLoRA, DPO, LIMA, Self-Instruct, Qi et al.
  safety-compromise, emergent-misalignment, Carlini extraction; OpenAI/Vertex/Bedrock docs;
  HF PEFT/TRL, Unsloth, Axolotl). Provider offerings + hardware figures flagged as dated.
  Updated README, CURRICULUM (status ✅), PROGRESS. All links verified.

## 2026-06-18 — Module 5 (Evaluation) built

- **Module 5 — Evaluation** (6 lessons), durable-first; the general eval discipline that
  the module-specific evals in Modules 2–4 (prompt, RAG, agent) apply — cross-linked, not
  duplicated:
  - `00-the-eval-mindset.md` — evals as the moat, eval-driven development loop, "look at
    your data"/error analysis, offline vs online, why leaderboards ≠ your task, the grading
    spectrum + SMART criteria.
  - `01-building-eval-sets.md` — SMART success criteria, coverage incl. negative examples &
    class balance, sourcing (production/expert/synthetic + caveats), volume-over-polish
    (bootstrap 20–50 vs shipping hundreds–thousands), labeling (benevolent dictator, binary
    first), train/test split, data contamination (private/fresh sets, never publish),
    maintaining/versioning.
  - `02-grading-methods.md` — the reliability hierarchy: code-based (incl. guardrails vs
    evaluators), statistical/NLP metrics (BLEU/ROUGE/BERTScore + limits), classification
    metrics (precision/recall/F1, macro/micro, imbalance), human eval (binary, rubric,
    IAA/kappa).
  - `03-llm-as-judge.md` — the 80%-human-agreement foundation, three modes (pointwise/
    pairwise/reference-based), writing judge prompts (binary>Likert, reason-then-score,
    decompose, escape hatch), the bias table (position/verbosity/self-preference/sycophancy)
    + mitigations, juries (PoLL), calibrate-vs-human, cost/nondeterminism/versioning.
  - `04-benchmarks-and-the-landscape.md` — what the major benchmarks measure (knowledge/
    math/coding/agentic/multimodal/long-context/IFEval/Arena), the caveats (contamination,
    saturation, overfitting, construct validity, the Leaderboard Illusion) unified by
    Goodhart's law, reading leaderboards critically, and safety/red-team eval (the worst-
    case inversion).
  - `05-evaluation-in-production.md` — statistics ("a number is not a result": CIs/SEM,
    clustered SE, paired deltas, bootstrap, power; why 2pt on 100 is noise), pass@k vs
    pass^k, A/B testing (offline + online business metrics), regression/CI gating, online
    monitoring (sampling, guardrails vs async, user feedback, drift), neutral tooling table.
- Sourcing: primary sources cited inline (Hamel Husain evals; Anthropic Demystifying-evals,
  develop-tests/define-success, Adding Error Bars to Evals; OpenAI eval best practices;
  Zheng et al. MT-Bench; contamination survey; LMArena Leaderboard Illusion; pass^k
  sources). Benchmark SOTA numbers deliberately NOT printed (volatile); tool ownership/
  deprecations flagged as dated. Updated README, CURRICULUM (status ✅), PROGRESS. All links
  verified.

## 2026-06-18 — Module 4 (Agents & Tool Use) built

- **Module 4 — Agents & Tool Use** (7 lessons), durable-first, cross-linked to
  Modules 1–3 (tool prompting, agentic RAG, retrieval-as-memory, prompt injection):
  - `00-agent-fundamentals.md` — agent vs workflow vs single call, the augmented LLM,
    the gather→act→verify→repeat loop, and the durable "when *not* to build an agent"
    gate (complexity/value/viability/cost-of-error).
  - `01-tool-and-function-calling.md` — the call mechanic + loop, tool_choice/parallel/
    streaming, cross-provider field-name gotchas, designing good tools (descriptions,
    consolidation, actionable errors, bash-vs-dedicated), server vs client tools,
    strict-schema structured output.
  - `02-agent-architectures-and-patterns.md` — the Anthropic workflow taxonomy
    (chaining/routing/parallelization/orchestrator-workers/evaluator-optimizer),
    autonomous loops (ReAct/plan-execute/reflection), and multi-agent (orchestrator+
    subagents, 90.2% win vs ~15× token cost, when it hurts).
  - `03-context-engineering-and-memory.md` — context rot/finite attention, compaction,
    context editing, short vs long-term memory, memory tool/files-as-memory,
    retrieval-as-memory (just-in-time), note-taking, subagent context isolation.
  - `04-mcp-and-the-tool-ecosystem.md` — MCP (M×N→M+N, USB-C analogy), host/client/
    server + primitives, transports, AAIF/Linux-Foundation governance + adoption, and
    MCP security (lethal trifecta, tool poisoning, rug pull, confused deputy).
  - `05-safety-security-and-reliability.md` — failure modes, guardrails (input/output/
    tripwire/cheap-gatekeeper), human-in-the-loop (+ approval-fatigue 93% caveat), least
    privilege, OWASP LLM06 excessive agency, the lethal trifecta & Rule of Two, cost/
    latency caps.
  - `06-evaluating-and-operating-agents.md` — why agent eval is hard, outcome vs
    trajectory eval, tool-selection/argument/ordering accuracy, LLM-as-judge for
    transcripts, eval sets, pass@k vs **pass^k**, frameworks (LangSmith/agentevals/
    OpenAI evals/τ-bench), and OTel-GenAI observability.
- Sourcing: primary sources cited inline (Anthropic Building Effective Agents,
  multi-agent system, context engineering, evals, writing-tools; MCP spec + AAIF
  donation; OWASP LLM01/06; Simon Willison's lethal trifecta); Module 1–3 material
  referenced not duplicated. Beta API flags + MCP version + token multipliers flagged
  as dated. Updated README, CURRICULUM (status ✅), PROGRESS. All links verified.

## 2026-06-18 — Module 3 (Retrieval-Augmented Generation) built

- **Module 3 — RAG** (6 lessons), durable-first, cross-linked to Modules 1–2:
  - `00-rag-fundamentals.md` — the index/query pipeline, why RAG, and the durable
    RAG vs. long-context vs. fine-tuning decision (incl. "when RAG is the wrong tool"
    and the adaptive-routing framing).
  - `01-ingestion-and-chunking.md` — parsing/cleaning, chunking strategies, size +
    the now-contested overlap, metadata, contextual/late chunking.
  - `02-embeddings-and-vector-stores.md` — how embeddings work (cosine, dims, MRL),
    a dated embedding-model table, vector DBs, ANN indexes (HNSW/IVF + quantization).
  - `03-retrieval-quality.md` — the heart: top-k (retrieve-wide/rerank-narrow), hybrid
    search + RRF, cross-encoder reranking, query transformation (HyDE/multi-query/
    decomposition/step-back), metadata filtering, and advanced architectures
    (Anthropic Contextual Retrieval, parent-document, GraphRAG, agentic RAG).
  - `04-generation-and-prompt-assembly.md` — grounding, the abstention paradox,
    citations (native vs quote-first; Citations⊗Structured-Outputs 400), chunk
    formatting/placement, "lost in the middle" ordering, how-many-chunks.
  - `05-evaluation-security-and-production.md` — retrieval vs generation metrics,
    RAGAS, the retrieval-vs-generation debugging 2×2; RAG security (OWASP LLM01/04/08
    — indirect injection, poisoning, access control, PII/embedding inversion); and
    production (freshness/reindex, latency, cost, prompt-caching the retrieved
    context, monitoring, tooling).
- Sourcing: primary sources cited inline (Anthropic Contextual Retrieval & Citations,
  "Lost in the Middle" TACL 2023, OWASP LLM Top 10 2025, RAGAS, MTEB); Module-2
  material (grounding, citations, injection, caching, eval) referenced not duplicated.
  Volatile facts (embedding models, prices, benchmarks) flagged as dated snapshots.
  Updated README, CURRICULUM (status ✅), PROGRESS. All links verified.

## 2026-06-18 — Module 2 (Prompt Engineering) built

- **Module 2 — Prompt Engineering** (5 lessons), durable-first per the HANDOFF rule:
  - `00-prompting-fundamentals.md` — what prompting is/isn't, the three prerequisites
    (success criteria, a test, a draft), prompt anatomy, the durable principles, a
    starter scaffold.
  - `01-core-techniques.md` — zero/few-shot, system/role (personas steer voice not
    accuracy), delimiters/XML, native structured output, output/length control,
    long-context layout, and the prefill-removed-on-Claude-4.6+ caveat.
  - `02-prompting-reasoning-models.md` — the centerpiece: the reasoning-era inversion
    (no manual CoT, goal-not-steps, effort over prose, be less prescriptive, ambiguity
    now costly), a provider cheat-sheet (Claude/GPT/Gemini), and the unfaithful-trace
    caution.
  - `03-advanced-patterns.md` — CoT variants, self-consistency, chaining/self-correction,
    ReAct/tool prompting, meta-prompting (APE/OPRO/DSPy), templating + prompt-caching;
    flags which patterns reasoning models made redundant.
  - `04-reliability-security-and-evaluation.md` — hallucination mitigation (grounding,
    "I don't know," cite/quote), prompt injection & jailbreaks (OWASP LLM01, trust-
    boundary defenses, defense-in-depth), and prompt evaluation (golden sets, grading
    hierarchy, LLM-as-judge done right, eval-driven iteration).
- Sourcing: Anthropic prompting facts from official docs + the authoritative `claude-api`
  reasoning-era prompt-tuning guidance; OpenAI/Gemini/academic/security technique via
  live web research (primary sources cited inline). Model-specific knobs flagged as
  dated. Updated README, CURRICULUM (status ✅), PROGRESS. Verified all links resolve.

## 2026-06-18 — Project created; Module 1 (Model Landscape) built

- New self-paced AI/LLM practical curriculum scaffold (`README`, `CURRICULUM`,
  `HANDOFF`, `PROGRESS`), modeled on the repo's `macos-mastery` course.
- **Module 0 — Orientation:** "How to use this course" + a vocabulary primer
  (tokens, context windows, parameters, modalities, reasoning models, MoE,
  quantization).
- **Module 1 — Model Landscape** (the first requested build):
  - `00-how-to-choose-a-model.md` — the durable task × constraint decision
    framework (the spine of the module).
  - `01-frontier-proprietary-models.md` — dated (June 2026) survey of Claude,
    OpenAI GPT, Google Gemini, xAI Grok, Meta Llama, Mistral, Amazon Nova, Cohere
    Command, DeepSeek, Alibaba Qwen, and niche players (Perplexity Sonar, AI21
    Jamba, Reka), with best-use and "when to pick it" guidance + a decision matrix.
  - `02-open-weight-local-ecosystem.md` — quantization formats, hardware sizing
    rules of thumb, runtimes (Ollama/MLX/llama.cpp/vLLM/LM Studio), licensing
    traps, and a hardware × task picker.
  - `03-top-100-local-models.md` — popularity-anchored (Hugging Face Hub download +
    trending data, June 2026) categorized catalog of ~100 locally-runnable models
    with one-line use cases.
- Sourcing: Anthropic facts from the `claude-api` skill (authoritative); all other
  vendors via live web research; local-model popularity grounded in live Hugging
  Face Hub queries. Volatility caveats and "how to re-verify" notes throughout.
