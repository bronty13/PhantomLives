# Changelog — AI Training

All notable changes to this curriculum. Dates are absolute (this content goes
stale, so the date matters).

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
