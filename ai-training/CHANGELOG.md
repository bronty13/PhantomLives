# Changelog — AI Training

All notable changes to this curriculum. Dates are absolute (this content goes
stale, so the date matters).

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
