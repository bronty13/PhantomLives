---
title: Prompting in the reasoning era
module: 02 — Prompt Engineering
lesson: 02
est_time: 40 min reading
last_reviewed: 2026-06-18
tags: [ai, prompting, reasoning, effort, thinking, model-specific]
---

# Prompting in the reasoning era

This is the most important lesson in the module — and the one most likely to surprise
anyone who learned prompting in 2023–2024. **Reasoning / "thinking" models inverted much
of the old playbook.** Techniques that were staples (chain-of-thought, heavy few-shot,
step-by-step instructions) are now done *internally* by the model, and prompting them
manually ranges from redundant to actively harmful.

> Recap from [Module 0](../part-00-orientation/00-how-to-use-this-course.md): a reasoning
> model spends hidden computation working through the problem before answering. You don't
> prompt that into existence anymore — it's built in, and you steer its *depth* with a
> parameter, not prose.

## The inversion, in one table

| Old (GPT-4 era, ~2023) | New (reasoning models, 2026) |
|---|---|
| "Let's think step by step" | Redundant or harmful — the model already thinks |
| Hand-write the reasoning steps | **Give the goal; let it plan** |
| Stack few-shot examples | Start **zero-shot**; examples can hurt |
| "CRITICAL: YOU MUST…" to force behavior | Plain instructions — strong language **overtriggers** |
| Coax length/depth with wording | Set **effort** and **verbosity** parameters |
| More context-gathering instructions | Often *less* — models over-explore if pushed |
| Lower temperature for determinism | Frequently leave defaults (some models *require* it) |

The unifying idea: **a good 2026 prompt is a clear brief that points an already-thinking
model at the right problem at the right depth — then gets out of the way.**

## 1. Don't manually prompt chain-of-thought

On reasoning models, "think step by step" / "show your work" **duplicates work the model
already does internally and can degrade the answer.**

- OpenAI: keep prompts simple and direct; instructing the model to reason step by step
  "may actually hinder performance."
  [(reasoning best practices)](https://developers.openai.com/api/docs/guides/reasoning-best-practices)
- Anthropic: *"Prefer general instructions over prescriptive steps. A prompt like 'think
  thoroughly' often produces better reasoning than a hand-written step-by-step plan.
  Claude's reasoning frequently exceeds what a human would prescribe."*
- DAIR.ai's reasoning-model guidance: avoid chain-of-thought; keep instructions simple
  and direct. [(promptingguide reasoning-llms)](https://www.promptingguide.ai/guides/reasoning-llms)

**When manual CoT *still* applies:** non-reasoning models, or a reasoning model with
thinking turned **off**. There, "think step by step" still helps. (Quirk: Claude Opus
with thinking *disabled* is sensitive to the word "think" and may over-reason — use
"consider," "evaluate," or "reason through" instead.)

## 2. Give the goal, not the steps

State the **outcome and success criteria**, then trust the model to find the path.
OpenAI: "be very specific about end goals… encourage the model to keep reasoning and
iterating until it matches your success criteria." Anthropic (Fable 5): "**give the
reason, not only the request**" — supply intent so the model connects the task to the
right approach. Over-prescription now *lowers* quality: Anthropic notes skills/prompts
written for older models are "**often too prescriptive**" for the newest ones and can
degrade output — try removing the scaffolding and re-testing.

## 3. Control depth with effort, not prose

The single biggest mechanical change: **reasoning depth is now an API parameter.** You
don't write "think really hard"; you set a knob. (Full treatment of the levels is in the
`~/Downloads/Thinking and Effort Guide`, and conceptually in
[Module 0](../part-00-orientation/00-how-to-use-this-course.md).)

| Provider | The knob | Notes |
|---|---|---|
| **Anthropic Claude** | `effort: low / medium / high` (+ `xhigh`/`max` on Opus/Sonnet) with **adaptive thinking** | `effort` controls *all* tokens (text, tools, thinking). `budget_tokens` is deprecated/removed on the newest models — use `effort`. Default is `high`. |
| **OpenAI GPT-5.x** | `reasoning_effort` (+ separate `text.verbosity`) | Value set & **default drift by version** (e.g. 5.5 default `medium`, 5.2 default `none`) — pin to your model. |
| **Google Gemini** | `thinkingLevel` (Gemini 3) / `thinkingBudget` (2.5) | Migrate 2.5→3 to `thinkingLevel`; don't send both. |

**Rule of thumb:** start at **medium** (or the model's sensible default), drop to **low**
for simple/latency-sensitive work, raise to **high** only when correctness on a hard
problem justifies the cost. Raising effort is often a cheaper fix than switching to a
bigger model — and on coding/agentic tasks it also produces *more* tool use.

## 4. Be less prescriptive — the capability paradox

The more capable the model, the *more* literally and faithfully it follows your prompt —
which means clumsy prompts that "worked" on weaker models now backfire.

- **Aggressive language overtriggers.** Anthropic, verbatim: prompts written to *overcome*
  older models' reluctance now overtrigger — *"Where you might have said 'CRITICAL: You
  MUST use this tool when…', you can use more normal prompting like 'Use this tool
  when…'."* Delete "If in doubt, use X" and "Default to using X."
- **Literal instruction-following (Opus 4.8).** It won't silently generalize an
  instruction from one item to all items — **state the scope** ("apply this to *every*
  section, not just the first"). This is great for pipelines but bites prompts that
  relied on reading between the lines. (It also explains a code-review surprise: told
  "only report high-severity issues," it faithfully reports fewer — so for coverage, tell
  it to report everything and filter in a separate step;
  see [lesson 04](04-reliability-security-and-evaluation.md).)
- **Ambiguity/contradiction now actively cost you.** GPT-5 follows with "surgical
  precision," so conflicting instructions make it burn reasoning tokens reconciling them.
  Clean, consistent prompts matter more than ever.
- **Verbosity calibration.** Newer models default terser and skip some summaries. If you
  want a summary after tool use, ask for it. To shape length, **positive examples of the
  right concision beat "don't be verbose."**
- **Tone.** Default style trends direct/grounded with sparing emoji; prompt explicitly if
  you need warmth.
- **Tool use & over-engineering.** Newer Claude favors reasoning over tool calls — to get
  *more* tool use, **raise effort before adding prompt pressure**. And capable models
  over-engineer (extra files, abstractions); add an explicit minimalism instruction
  ("only what's requested; no speculative abstractions; no defensive code for impossible
  cases") if you want lean output.

These specifics come straight from the providers' current model-prompting pages and
Anthropic's migration guidance — treat the *exact model names* as dated, but the
*direction* (capable model → dial back the force) is stable.

## 5. Provider cheat-sheet (June 2026)

| | Claude (Opus 4.6–4.8 / Sonnet 4.6 / Fable 5) | OpenAI GPT-5.x | Google Gemini 3.x |
|---|---|---|---|
| App-level role channel | `system` | **`developer`** (outranks user) | system instruction |
| Depth knob | `effort` + adaptive thinking | `reasoning_effort` | `thinkingLevel` |
| Length knob | prompt / effort | **`text.verbosity`** | prompt (terser by default) |
| Few-shot | start zero-shot | start zero-shot | "**always** include" (general use) |
| Manual CoT | not needed (thinking on) | not needed | replace with `thinking_level:high` |
| Temperature | n/a on newest (removed) | tune sparingly | **keep at 1.0** (lowering degrades) |
| Prefill | **removed** (4.6+) | n/a | response-prefix steering OK |
| House quirk | XML tags; literal; LaTeX math default | `developer` role; metaprompting-friendly | media-before-text; concise prompts |

## 6. A caution about reasoning traces

The model's visible "thinking" is **not a faithful audit trail.** Anthropic's own
research shows chains can be plausible-sounding while omitting the real drivers of the
answer. Use thinking output for steering and debugging — **not** as proof of why the
model did something, and don't build logic that depends on its literal content.
[(Tracing the thoughts of an LLM)](https://www.anthropic.com/research/tracing-thoughts-language-model)

## The takeaway

Modern prompting is **subtractive**: write the clearest brief you can, set the effort
dial, and *remove* the scaffolding you would have added in 2023. If a capable model is
misbehaving, your first instinct should be "what can I cut or clarify?" — not "what
forceful rule can I add?"

---

## Next

→ [Advanced patterns](03-advanced-patterns.md) — chaining, ReAct, self-consistency, and
meta-prompting (and which of them reasoning models made obsolete).
