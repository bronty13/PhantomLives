# Changelog — AI Training

All notable changes to this curriculum. Dates are absolute (this content goes
stale, so the date matters).

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
