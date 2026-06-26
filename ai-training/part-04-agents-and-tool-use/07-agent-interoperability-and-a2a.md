---
title: Agent interoperability & the A2A protocol
module: 04 — Agents & Tool Use
lesson: 07
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, agents, interoperability, a2a, mcp, protocols]
---

# Agent interoperability & the A2A protocol

[Lesson 04](04-mcp-and-the-tool-ecosystem.md) connected an agent *downward* to its
tools and data via MCP. This lesson looks *sideways*: how does one agent talk to
**another agent** — especially one built by a different team, vendor, or
framework? That's **agent interoperability**, and it's the emerging frontier of
the agent ecosystem. It comes after the module's synthesis ([lesson 06](06-evaluating-and-operating-agents.md))
deliberately: it's where multi-agent systems are *heading*, and it's moving fast.

> ⚠️ **Dated snapshot — June 2026.** The durable concepts (the vertical/horizontal
> split, the trust problem) are stable; the specific protocol, its version, and
> its governance are a fast-moving snapshot — re-verify at the links.

---

## The durable problem: a society of agents

A single agent talking to its own tools is a solved-enough problem
([lesson 04](04-mcp-and-the-tool-ecosystem.md)). The hard, lasting problem appears
the moment **autonomous agents built by different teams and vendors must work
together** — a "society of agents." To collaborate across those boundaries, agents
need a *common* way to:

- **discover** each other and find out who can do what,
- **describe their capabilities** in a machine-readable, vendor-neutral form,
- **delegate tasks** (including long-running, asynchronous ones),
- **exchange results** (text, files, structured data, streamed progress),

…all **without a shared codebase, framework, or runtime.** Without a standard,
every cross-vendor integration is a bespoke N×N adapter — the same fragmentation
that HTTP, SMTP, and SQL each eventually dissolved in their domains. An
interoperability protocol is the bet that agent-to-agent communication will go
the same way.

---

## The load-bearing distinction: vertical vs. horizontal

This is the single most durable idea in the topic, and it's stated first-party by
the protocols themselves:

| Axis | Protocol | Connects | Analogy |
|---|---|---|---|
| **Vertical** | **MCP** (Model Context Protocol) | an agent ↔ its **tools, data, context** | giving one worker their tools |
| **Horizontal** | **A2A** (Agent2Agent) | an agent ↔ **another agent** | workers collaborating with each other |
| *(agent↔user)* | *AG-UI* | an agent ↔ a **frontend/user** | the last-mile UI bridge |

**MCP and A2A are complementary, not competing.** A production multi-agent system
typically uses *both*: MCP *inside* each agent to reach its tools, A2A *between*
agents to coordinate. ([Lesson 02's multi-agent patterns](02-agent-architectures-and-patterns.md)
are the *why*; A2A is a *how* for when those agents live in different systems.) If
you remember one thing from this lesson, make it this row: **MCP is vertical, A2A
is horizontal.**

---

## How A2A works (the concepts)

A2A — originated by Google (April 2025), now a Linux Foundation project — gives
agents a standard HTTP-based way to find and delegate to each other. The core
concepts (re-verify field-level details against the live spec):

- **Agent Card** — a JSON "business card" an agent publishes for **discovery**,
  served at a well-known URL (`/.well-known/agent-card.json`). It advertises the
  agent's identity, capabilities, **skills**, supported transports, and the auth
  it requires. Cards can be **cryptographically signed** so a caller can verify
  *who* it's talking to.
- **Client and Remote-Agent roles** — a **client** initiates a request on behalf
  of a user/system; a **remote agent** exposes an endpoint, does the work, and
  returns results.
- **Tasks and their lifecycle** — communication is **task-oriented**: a task moves
  `submitted` → `working`, can pause at `input-required` / `auth-required`, and
  ends `completed` / `canceled` / `failed` / `rejected`. This models *long-running,
  asynchronous* delegation, not just a request/response — the right shape for "go
  do this and tell me when it's done."
- **Messages and Artifacts** — a *message* is a turn (role `user` or `agent`) made
  of typed *parts* (text, file, structured data); an *artifact* is the produced
  result.
- **Transport** — everything over HTTPS, with **JSON-RPC over HTTP** as the
  canonical binding (plus gRPC and REST options), **streaming via Server-Sent
  Events**, and async push notifications.
- **Opaque agents** — the key design principle: agents collaborate via *declared
  capabilities and exchanged messages* **without exposing their internal state,
  memory, plans, or tool implementations.** This is what lets *competing* or
  black-box agents interoperate — you expose what you do, not how you do it.
- **Authentication** — A2A defines **no identity system of its own**; it delegates
  to standard web auth (OAuth 2.0, OpenID Connect, mTLS, API keys) declared in the
  Agent Card. (Keep the security caveat below in mind: *declaring* an auth scheme
  is not the same as *verifying* the agent behind it.)

---

## The governance landscape (June 2026 — dated)

Worth knowing because it signals consolidation, not a protocol war — and because
it corrects a widely-mis-reported fact:

- **A2A** was announced by Google (April 2025) and donated to the **Linux
  Foundation** (June 2025), where it's its **own** project. It reached **v1.0 —
  the first "production-ready" release — in early 2026** (with breaking changes;
  a v1.0.1 patch followed). It's at 150+ participating organizations.
- **⚠️ Common error to avoid:** A2A is **not** part of the *Agentic AI Foundation
  (AAIF)*. AAIF (formed late 2025) anchors **MCP, goose, and AGENTS.md** (the
  steering-file standard from [Module 10](../part-10-coding-agents/02-context-and-orchestration.md))
  — *not* A2A. Both sit under the Linux Foundation, but in different sub-
  foundations. (Many secondary write-ups get this wrong; trust the primary
  sources.)
- **Convergence, not fragmentation:** IBM's competing **ACP** protocol **merged
  into A2A** in 2025, leaving A2A as the surviving agent↔agent standard. The
  stable reference stack that emerged: **MCP (agent↔tool) · A2A (agent↔agent) ·
  AG-UI (agent↔user).**

> **Honest maturity read:** governance and spec maturity is **high**; real-world
> deployment is **moderate** and concentrated in the big cloud platforms (Azure,
> AWS, Google). A2A is *emerging-but-maturing*, not battle-hardened — and agent
> *registries* (how you'd actually discover an arbitrary agent) are still
> fragmented, with no single canonical directory. Treat it as a bet worth
> understanding, not yet a default you must adopt.

---

## Security: the trust boundary moves outside your org

This is the part that matters most, and it's durable. The
[lethal trifecta](05-safety-security-and-reliability.md) from this module's safety
lesson **compounds** in an agent-to-agent world, because **one agent's output
becomes another agent's input** — a "trust cascade." Three consequences:

- **Every inbound agent message is untrusted content.** A prompt injection that
  lands in agent A propagates to agent B downstream — and trust labels are
  typically *dropped* as content crosses an agent boundary, so the injection
  arrives looking like a trusted instruction. Inter-agent channels are usually
  trusted and unfiltered, which *amplifies* injection compared to a single agent.
- **Authentication is necessary but not sufficient.** Knowing *who* an agent is
  (via signed Agent Cards and OAuth/mTLS) tells you nothing about whether its
  message is *safe* — an *authenticated* agent can still relay an injection it
  picked up upstream. An Agent Card's claimed capabilities are **assertions, not
  proofs**.
- **Delegation must be scoped.** A delegation chain that passes *full* privileges
  downstream (a worker agent inheriting a manager agent's full database rights) is
  privilege escalation waiting to happen. **Least-privilege, scoped delegation** is
  the mitigation — the [Module 4 least-privilege principle](05-safety-security-and-reliability.md)
  extended across organizational boundaries.

The formal threat models are catching up (OWASP now maintains an agentic-
applications top-10 covering insecure inter-agent communication, identity/privilege
abuse, and cascading failures — see [Module 12's red-teaming lesson](../part-12-governance/04-risk-assessment-and-red-teaming.md)).
The durable takeaway: **A2A moves your trust boundary outside your own
organization, so treat every cross-agent interaction as the untrusted, injectable
surface it is.**

`★ Insight ─────────────────────────────────────`
- **MCP is vertical, A2A is horizontal** — MCP connects an agent to its tools, A2A
  connects agents to each other, and a real multi-agent system uses both. The
  protocols are complementary layers, not rivals.
- **Interoperability moves the trust boundary outside your org, and the lethal
  trifecta compounds across the chain.** One agent's output is the next agent's
  (untrusted) input; authentication tells you *who*, never *whether it's safe* — so
  scoped delegation and treating every inbound agent message as injectable are the
  load-bearing defenses, exactly as with any untrusted content.
`─────────────────────────────────────────────────`

## Module complete

This closes **Module 4 — Agents & Tool Use**: from
[when (not) to build an agent](00-agent-fundamentals.md), through
[tools](01-tool-and-function-calling.md),
[architectures](02-agent-architectures-and-patterns.md),
[context](03-context-engineering-and-memory.md),
[MCP](04-mcp-and-the-tool-ecosystem.md),
[safety](05-safety-security-and-reliability.md), and
[evaluation](06-evaluating-and-operating-agents.md), out to the agent ecosystem's
interoperable frontier.

← [Evaluating & operating agents](06-evaluating-and-operating-agents.md) ·
↑ [Module index](../CURRICULUM.md)
