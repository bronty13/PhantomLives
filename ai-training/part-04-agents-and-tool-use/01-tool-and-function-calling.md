---
title: Tool & function calling
module: 04 — Agents & Tool Use
lesson: 01
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, agents, tool-use, function-calling]
---

# Tool & function calling

Tools are how a model *acts*. This lesson is the mechanical foundation everything else
sits on: how a tool call actually works, and — more importantly — how to design tools the
model uses well.

## The core mechanic: the model never runs anything

A model can't execute code or hit an API. It emits a **structured request** ("call
`get_weather` with `{city: 'Paris'}`"); **your code** (or the provider's server) runs the
operation and feeds the **result back** into the conversation. The model then decides what
to do next. That round trip is the entire mechanism.

The loop, keyed on the response's stop reason:

1. Send the request with a **`tools`** list + the user message.
2. The model responds wanting a tool → a **tool-use** block (`id`, `name`, `input`).
3. **Your code executes** the tool.
4. Send the result back as a **tool-result** block (carrying the matching `id`).
5. Repeat until the model stops asking for tools (`end_turn`).

The SDK tool runners automate this loop; you can also drive it manually when you need
human-in-the-loop approval or custom logging ([lesson 05](05-safety-security-and-reliability.md)).

### A tool definition has three parts

- **name** — short, namespaced (`github_list_prs`, not `list`).
- **description** — detailed plaintext: what it does, **when to use it (and when not)**,
  what each parameter means, caveats.
- **input_schema / parameters** — a JSON Schema for the arguments.

### Controls
- **tool_choice / mode:** `auto` (model decides — default), `any`/`required` (must call
  *some* tool), force a *specific* tool, or `none`. *(On Claude with extended thinking,
  only `auto`/`none` are supported — forcing a tool errors.)*
- **Parallel tool calls** — modern models call several tools at once by default. Important
  Claude gotcha: return **all** the parallel tool-results in a **single** user message;
  splitting them teaches the model to stop parallelizing.
- **Streaming** — tool inputs stream as partial-JSON string fragments; accumulate them and
  parse when the block closes.

### Cross-provider field-name reality (a real gotcha)

The concept is identical across providers; the field names diverge, and that's the #1
source of bugs:

- **Anthropic** has *no* special tool role — `tool_use` rides in an `assistant` message,
  `tool_result` in a `user` message; `input` is an object.
- **OpenAI** has *two* APIs (Chat Completions vs. the newer Responses) with different field
  names, and its `arguments` is a **JSON-encoded string you must parse**, not an object.
- **Gemini** uses `functionCall`/`functionResponse` parts with an `id` that maps results to
  calls (so order doesn't matter).

Pin to your provider's current tool-use doc; don't assume field names carry over.

## Designing good tools — the real lever

The model's tool *use* is only as good as your tool *design*. This matters more than any
prompt tweak. [(Anthropic — Writing tools for agents)](https://www.anthropic.com/engineering/writing-tools-for-agents)

- **The description is the #1 performance lever.** Say *when to call it and when not*, not
  just what it does. (Capable models under-reach for tools by default — be prescriptive;
  see [Module 2, lesson 02](../part-02-prompt-engineering/02-prompting-reasoning-models.md).)
- **Fewer, consolidated tools beat many narrow ones.** One `schedule_event` beats
  `list_users` + `list_events` + `create_event`. Too many tools confuse the model — and
  bloat context.
- **Return high-signal, token-efficient results.** Paginate/filter/truncate; return stable
  IDs, not megabytes. Tool output lands back in the context window every step
  ([lesson 03](03-context-engineering-and-memory.md)).
- **Return actionable errors**, flagged as errors (e.g. `is_error: true`): *"Rate limit
  exceeded — retry after 60s,"* not *"failed."* The model will adapt and retry.
- **Poka-yoke** (mistake-proof) tools — design parameters so the wrong call is hard to make.

### The bash-vs-dedicated-tool axis

A key design decision: give the model a broad **bash / code-execution** tool, or many
**dedicated** typed tools?

- **Bash** gives maximum reach but hands your harness an opaque command string — hard to
  gate, render, or audit.
- **A dedicated tool** (`send_email`, `edit_file`) gives the harness a typed hook it can
  **gate** (require approval), **validate** (reject stale edits), **render**, and
  **parallelize safely**.
- **Rule of thumb:** start with bash for breadth; **promote an action to a dedicated tool
  when you need to gate, validate, render, or parallelize it** — especially anything
  irreversible.

Two newer (beta, verify status) Anthropic features address tool *scale*: **programmatic
tool calling** (the model orchestrates tools inside a code sandbox, keeping intermediate
results out of context) and **tool search** (load tool definitions on demand instead of
all upfront — preserves the prompt cache).

## Server-side vs client-side tools

- **Client-side tools** — *you* execute them (your `function` tools, plus client tools like
  file edit). You control the loop and the side effects.
- **Server-side / hosted tools** — the provider runs them (web search, code execution,
  computer use). You just declare them; the provider runs the loop and returns results.
  Less control, less plumbing.

## Structured output / strict schemas

When you need *guaranteed* shape (a program parses it), use strict schemas:

- **Anthropic's idiom:** a **forced tool** with the desired schema (`tool_choice: any` +
  `strict: true`) guarantees a tool is called *and* its inputs validate.
- **OpenAI:** `strict: true` on a function, or `response_format: json_schema` for the
  final answer (requires `additionalProperties: false` and all fields `required`).
- See [Module 2, lesson 01](../part-02-prompt-engineering/01-core-techniques.md) for the
  general structured-output guidance — prefer native enforcement over "respond in JSON."

---

## Next

→ [Agent architectures & patterns](02-agent-architectures-and-patterns.md)
