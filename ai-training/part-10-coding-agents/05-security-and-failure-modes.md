---
title: Security & failure modes
module: 10 — Coding Agents & AI-Assisted Development
lesson: 05
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, coding-agents, security, prompt-injection, supply-chain]
---

# Security & failure modes

This is the highest-stakes lesson in the course, for one reason: **a coding agent
runs code.** Every prompt-injection risk from
[Module 4](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)
is still here, but the payload is no longer a bad sentence — it's command
execution, exfiltrated secrets, and poisoned commits. By June 2026 these are not
hypotheticals; they're shipped CVEs. The good news: the failure modes share a
*small number of recurring patterns*, and the defenses are the ones from
[lesson 03](03-tools-and-mcp-in-the-loop.md).

---

## The lethal trifecta, in a dev context

The durable framing from [Module 4](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)
is the spine of this whole lesson. An agent becomes dangerous when **three things
combine**:

1. **Access to private data** (your repo, your secrets, your database),
2. **Exposure to untrusted content** (a public issue, a dependency's README, a
   web page, a code comment), and
3. **A way to exfiltrate** (open a PR, make a network call, write a file).

**Any two are safe; all three together is the lethal trifecta.** A coding agent
lands in it almost by default: it reads a *public* issue (untrusted) while
holding *private-repo* access and the ability to *open a PR or make a network
request*. That is the exact shape an attacker needs — and it's why the
mitigations below all work by *breaking one leg of the trifecta*.

---

## The recurring exploit pattern: untrusted content → config → execution

Across the real 2025–26 incidents — in Copilot, Cursor, Claude Code, Amazon Q —
the successful attacks share one shape, worth memorizing because it generalizes:

> **Untrusted content injects an instruction that rewrites the agent's own
> configuration, and auto-approval turns that into code execution.**

Concretely, the documented incidents:

- **Invisible instructions in a PR or issue.** A PR description carried
  instructions in *invisible HTML comments* (model-visible, human-invisible)
  that drove the assistant to exfiltrate private-repo secrets one character at a
  time through image-proxy URLs (the GitHub Copilot "CamoLeak," CVE-2025-59145).
- **Injection rewrites the trust config.** An injected instruction wrote
  `"autoApprove": true` into the editor's settings, flipping the agent into
  unattended-execution mode and turning a comment into arbitrary shell
  (CVE-2025-53773). Cursor's "CurXecute" (CVE-2025-54135) rewrote the MCP config
  so the agent auto-ran a malicious MCP server.
- **A malicious extension shipped to a marketplace.** Amazon Q's VS Code
  extension shipped a build containing an injected near-factory-reset prompt; it
  reportedly failed only because of a *syntax error* in the malicious payload.

The lesson is not the individual CVEs (all patched) — it's the **pattern**: the
agent's own config and auto-approve setting are an attack surface, and untrusted
content is trying to reach them.

---

## MCP tool poisoning

[Module 4's MCP security surface](../part-04-agents-and-tool-use/04-mcp-and-the-tool-ecosystem.md)
has a coding-specific sharp edge: **tool poisoning.** Malicious instructions are
hidden in a tool's *description or schema* — which the model reads but the user
never sees. Poison the description once and *every* session is compromised, with
nothing visible in the transcript. It's now codified as a top entry in the OWASP
MCP risk list. The defense: **vet the source of every MCP server you connect**,
exactly as you'd vet a dependency — an MCP server is untrusted third-party code
with a direct line to your agent's instructions.

---

## Supply-chain risk: slopsquatting & hallucinated dependencies

A failure mode unique to AI-generated code: models **hallucinate package names.**
Across a large study of LLM code suggestions, ~1 in 5 suggested packages didn't
exist — hundreds of thousands of unique fabricated names. Attackers exploit this
predictably: register the hallucinated name on the public registry with a
malicious payload and wait for an agent (or a developer trusting the agent) to
`npm install` / `pip install` it. This is **"slopsquatting"** — typosquatting's
AI-native cousin — and there's already a documented case of a hallucinated
package racking up tens of thousands of downloads. The defense is mundane and
effective: **verify every dependency an agent adds exists and is the real one**
before installing, and pin/lock your dependencies.

---

## Secret leakage

Coding agents ingest the *whole workspace* — and they don't honor `.gitignore` /
ignore files the way a git client does. An agent that auto-loads `.env`, reads
config files, or slurps the repo can pull secrets into its context, where they
can resurface in generated code, a log, or an upload. Surveys through 2026 found
tens of thousands of secrets sitting in MCP config files alone. The defenses:
**keep secrets out of the workspace** (environment injection at the boundary, a
secrets manager — never a plaintext file the agent reads), and treat the agent's
context as *potentially exfiltrable*.

---

## The defenses (all from lesson 03)

Reassuringly, the mitigations are the [lesson 03 guardrails](03-tools-and-mcp-in-the-loop.md),
each one breaking a leg of the trifecta:

- **OS-level sandbox** — network *off by default*, filesystem scoped to the
  project. This is the defense that **survives prompt injection**, because it's
  enforced below the model: even a fully-fooled agent can't reach a secret
  outside the box or call an attacker's server. Breaks the *exfiltration* leg.
- **Permission rules (deny → ask → allow)** — deny the catastrophic, prompt for
  one-way doors, allowlist only the safe-and-reversible. Breaks the *action* leg.
- **Don't auto-approve in the presence of untrusted content.** The single most
  important operational rule: **never combine untrusted input + network + secrets
  + auto-approve.** Every major incident above needed auto-approve (or a tricked
  config) to land. Keep the human in the loop precisely when the agent is reading
  things you didn't write.
- **Vet MCP servers and dependencies** like the untrusted third-party code they
  are. Breaks the *untrusted content* leg at the source.
- **Version control as the backstop** — commit often; an agent's change you don't
  like (or didn't expect) is a `git revert` away.

`★ Insight ─────────────────────────────────────`
- **Coding agents live in the lethal trifecta by default** (private repo +
  public issue + ability to push/call out), so security here is about
  *deliberately breaking one leg* — sandbox the exfiltration, gate the actions,
  or distrust the content — not about hoping the model behaves.
- **One pattern explains most real incidents:** untrusted content rewrites the
  agent's config and auto-approve turns it into execution. The corollary is a
  rule you can actually follow — **never auto-approve while the agent is reading
  untrusted input** — and the one defense that holds when everything else fails
  is the OS sandbox, because it doesn't depend on the model not being fooled.
`─────────────────────────────────────────────────`

## Module complete

This completes **Module 10 — Coding Agents & AI-Assisted Development**, and with
it the curriculum's tenth module. The arc: the
[autonomy ladder](00-the-coding-agent-landscape.md) →
[plan-act-verify workflows](01-agentic-coding-workflows.md) →
[context & orchestration](02-context-and-orchestration.md) →
[tools & MCP](03-tools-and-mcp-in-the-loop.md) →
[evaluation & trust](04-evaluating-and-trusting-coding-agents.md) → security. It
takes the agent foundations of [Module 4](../part-04-agents-and-tool-use/00-agent-fundamentals.md)
into the daily reality of AI-assisted software work — the application most
readers of this course will use every day.

→ Back to the [curriculum index](../CURRICULUM.md).
