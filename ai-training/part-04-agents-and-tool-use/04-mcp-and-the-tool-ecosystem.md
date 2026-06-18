---
title: MCP & the tool ecosystem
module: 04 — Agents & Tool Use
lesson: 04
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, agents, mcp, tools, security]
---

# MCP & the tool ecosystem

[Lesson 01](01-tool-and-function-calling.md) showed how to give *one* model *your* tools.
But every team was rebuilding the same connectors (GitHub, Slack, Postgres, Google Drive)
for every model. **MCP — the Model Context Protocol — is the standard that fixes that.**

## The problem MCP solves: M×N → M+N

Without a standard, connecting **M** AI apps to **N** tools/data sources needs **M×N**
bespoke integrations. MCP defines one open protocol so each tool exposes itself **once**
and any MCP-capable app can use it — **M+N**. The canonical analogy:

> **MCP is a "USB-C port for AI applications"** — a standardized way to connect a model to
> external systems. Build a connector once, integrate everywhere.
> [(modelcontextprotocol.io)](https://modelcontextprotocol.io/introduction)

## Architecture

Three participants in a client-server design:

- **Host** — the AI application (Claude Code, an IDE, a chat app) that coordinates one or
  more clients.
- **Client** — a connector *inside* the host; **one client per server connection**.
- **Server** — a program that exposes capabilities to clients. Runs **locally** or
  **remotely**.

Servers expose three **primitives**:

| Primitive | What it is | Example |
|---|---|---|
| **Tools** | Executable functions the model can invoke | "create a GitHub issue," "run a query" |
| **Resources** | Read-only data/context | a file's contents, a DB record |
| **Prompts** | Reusable prompt templates | a "review this PR" template |

Clients can also expose primitives back to servers — notably **sampling** (the server asks
the *host* to run an LLM completion, so the server stays model-agnostic) and
**elicitation** (the server asks the user for input/confirmation).

**Under the hood:** JSON-RPC 2.0, a **stateful** protocol with an `initialize` handshake
that negotiates capabilities and a protocol version. Listings are dynamic — a server can
notify clients that its tool set changed.

## Transports

- **stdio** — local processes on the same machine talk over standard in/out. Fast, no
  network; usually one client. The default for local servers.
- **Streamable HTTP** — for remote servers serving many clients; supports bearer
  tokens/API keys, and **MCP recommends OAuth** for authorization.

## Why it matters in 2026

MCP became *the* agentic-tooling standard and went **vendor-neutral**: it was donated to
the **Agentic AI Foundation** (a Linux Foundation fund) co-founded by Anthropic, Block, and
OpenAI, with Google, Microsoft, AWS, Cloudflare, and Bloomberg supporting. At donation time
there were **10,000+ public MCP servers** and ~97M monthly SDK downloads, with adoption
across ChatGPT, Cursor, Gemini, Copilot, and VS Code.
[(Anthropic — donating MCP)](https://www.anthropic.com/news/donating-the-model-context-protocol-and-establishing-of-the-agentic-ai-foundation)
⚠️ *Exact server counts and the protocol version (the spec uses date-stamped revisions —
confirm the current one at modelcontextprotocol.io) are dated facts.*

## Security — MCP widens the attack surface

A standard tool interface is also a standard *attack* interface. MCP-specific threats (and
why they tie straight back to [Module 2's injection lesson](../part-02-prompt-engineering/04-reliability-security-and-evaluation.md)):

- **The lethal trifecta** — the concept to internalize. An agent is exploitable when it
  combines **(1) access to private data + (2) exposure to untrusted content + (3) the
  ability to communicate externally.** Any system with all three can be tricked (via
  injection) into *exfiltrating* the private data. MCP makes all three easy to assemble
  accidentally. Full treatment in [lesson 05](05-safety-security-and-reliability.md).
- **Tool poisoning** — malicious instructions hidden in a tool's *description/metadata*
  (invisible to the user, read by the model). Once a tool is poisoned, every session using
  it is compromised.
- **Rug pull** — a server changes a tool's behavior *after* you approved it.
- **Confused deputy / shared privilege** — internal and external tools share a privilege
  level, so a response from an untrusted external server can trigger a trusted internal
  tool.
- **Weak auth** — servers that don't verify identity or enforce scope (why the spec pushes
  OAuth).

**Mitigations (no single one suffices):** pin and vet the servers you trust; scope tools to
least privilege; require human approval for high-risk tool calls; validate inputs; and
monitor tool calls. These are the same defense-in-depth principles as
[lesson 05](05-safety-security-and-reliability.md) — MCP just makes them mandatory because
you're now running *other people's* tools.

---

## Next

→ [Safety, security & reliability](05-safety-security-and-reliability.md)
