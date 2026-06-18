---
title: Evaluating & operating agents
module: 04 — Agents & Tool Use
lesson: 06
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, agents, evaluation, observability, production]
---

# Evaluating & operating agents

You can't ship what you can't measure, and agents are **harder to measure** than anything
earlier in this course. This lesson closes the module: how to evaluate an agent, and how to
run one in production.

## Why agent eval is hard

- **Multi-step and stateful** — there's no single output to grade; the agent mutates the
  world along the way.
- **Nondeterministic trajectories** — many valid paths to the goal, so rigid "did it take
  *these* exact steps?" checks are brittle (capable agents even find unintended-but-correct
  solutions).
- **Compounding error** — a per-step success rate looks fine but collapses over a long task
  (the [lesson 05](05-safety-security-and-reliability.md) problem, now a measurement
  problem).

[(Anthropic — Demystifying evals for AI agents)](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)

## Two things to measure: outcome vs. trajectory

| | **Outcome / end-state** | **Trajectory / process** |
|---|---|---|
| Grades | The final result / world-state | The *steps*: tool calls, order, reasoning |
| Good for | The default — "did it produce the right thing?" | Debugging, partial credit, policy checks |
| Method | Compare end state to a goal state | Inspect the transcript |

**Default to outcome grading** — grade what the agent produced, not the path it took. Reach
for **trajectory** evaluation when you need to debug *why* it failed, give partial credit,
or enforce a process policy (e.g. "must authenticate *before* charging").

### Trajectory specifics
Separate three different things when you grade the path:
- **Tool-selection accuracy** — did it pick the right tool?
- **Tool-argument accuracy** — did it call it with the right arguments?
- **Ordering** — in a valid order? (match modes range from strict-order to "right tools,
  any order, extras allowed").

### LLM-as-judge for transcripts
Score the agent's transcript with a model + rubric (factual accuracy, tool efficiency,
completeness). The discipline from [Module 2, lesson 04](../part-02-prompt-engineering/04-reliability-security-and-evaluation.md)
applies, plus two agent-specific rules: **give the judge an escape hatch** ("return
*Unknown* if you can't tell") and **calibrate it against human experts** — design tasks
where two experts would independently agree on the verdict.

## Building an agent eval set

- **Start small, from real failures** — ~20–50 tasks drawn from things the agent actually
  got wrong is a great start ("changes tend to have dramatic impacts" at this scale).
- **Every task needs a reference solution** that passes your graders — a 0% pass rate
  usually means a *broken task*, not an incapable agent.
- **Balance it** — include cases where a behavior *should* and *shouldn't* happen.
- **Isolate each trial** in a clean environment (agents mutate state).
- **Retire saturated evals** into a regression suite and keep adding new failures.

## Metrics — and the 2026 shift to `pass^k`

- **pass@k** — succeeds in *at least one* of k attempts. (Capability ceiling.)
- **pass^k** — succeeds in *all* k attempts (≈ pᵏ, decays fast). **This is the metric that
  matters for customer-facing agents** — a 50%-single-run agent can fall below 25% by
  pass^8. Reliability, not best-case capability, is what users feel.
- Also track **tool-call accuracy**, **step efficiency** (vs. the optimal path), and
  **cost + latency per task**.

## Frameworks (June 2026)
**LangSmith** (final-response / single-step / trajectory evals, plus production failure
clustering), **agentevals** (ready-made trajectory evaluators with the match modes above),
**OpenAI Evals** (trace grading → dataset benchmarking), and benchmarks like **τ-bench /
τ²-bench** (tool-agent-user tasks graded on end-state, and the source of `pass^k`). Pick by
fit; the discipline matters more than the tool.

## Observability — trace every step

Agents are nondeterministic and stateful, so you need to see *what they did*, not just the
final answer. **Trace per step:**

- every **LLM call** — model, prompt, tokens, finish reason (a `max_tokens` finish or
  repetition signals a loop/truncation), latency;
- every **tool call** — name, arguments, result, success/error, latency (catches
  hallucinated calls and exfiltration attempts);
- cumulative **tokens/cost**, **iteration count**, and every **guardrail / approval
  decision**.

The emerging standard is **OpenTelemetry's GenAI semantic conventions** (`invoke_agent` →
`chat` + `execute_tool` spans), supported by LangSmith, Langfuse, and the OTel-native APM
tools. *(The exact attribute/span names are still stabilizing — verify against the current
spec.)*

## Operating notes

- Agents are **stateful** — prefer designs that **resume from the failure point** over
  restarting from scratch.
- They're **nondeterministic between runs** — monitor *decision patterns*, not just
  pass/fail.
- Deploy carefully so you don't disrupt **in-flight** agent runs.

## The whole module, in one line

**Build the simplest thing that works → give it well-designed tools → orchestrate with the
least-autonomous pattern that fits → curate its context → standardize connectors with MCP →
wrap it in least-privilege guardrails and human gates → and measure it on outcomes (and
`pass^k`) with full tracing before you trust it.**

---

← [Safety, security & reliability](05-safety-security-and-reliability.md) ·
↑ [Module index](../CURRICULUM.md)
