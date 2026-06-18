---
title: Safety, security & reliability
module: 04 — Agents & Tool Use
lesson: 05
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, agents, safety, security, guardrails, excessive-agency]
---

# Safety, security & reliability

A single LLM call can produce a bad sentence. An **agent** can send the email, delete the
rows, or spend the budget. Autonomy + tools = real-world consequences, so agents need a
layer of defenses that single calls never did. This lesson is that layer.

## Failure modes to design against

- **Compounding error** — each step builds on the last, so a small early mistake snowballs.
  A 90%-reliable step is far less than 90% reliable over ten steps. *Mitigation: keep the
  design simple, verify against the environment each step ([lesson 00](00-agent-fundamentals.md)).*
- **Loops / getting stuck** — the agent repeats an action or never terminates. *Mitigation:
  a hard **max-iterations / max-turns cap** — the single most important guard.*
- **Runaway cost** — loops, retries, and huge tool outputs burn tokens. *Mitigation: token
  budgets + step caps + token-efficient tools ([lesson 01](01-tool-and-function-calling.md)).*
- **Hallucinated tool calls** — invented tool names or arguments. *Mitigation: mistake-proof
  ("poka-yoke") tools, clear descriptions, and validation.*

> Anthropic's standing requirement: test agents **in sandboxed environments with
> guardrails** before they touch production. Treat that as non-negotiable.

## Guardrails

Wrap the agent in cheap checks that can **halt** it:

- **Input guardrails** run on the incoming request — catch jailbreaks/injection *before*
  the expensive model runs.
- **Output guardrails** run on the result — catch PII, policy violations, unsafe actions
  *before* they reach the user or a tool.
- A **tripwire** that fires on a violation should *stop execution*, not just log — and
  running a **cheap, fast model as the gatekeeper** in front of the expensive one saves
  both money and risk.

Verify your guardrails actually halt (not merely warn), and screen *tool outputs* too —
retrieved/tool content is untrusted ([Module 3, lesson 05](../part-03-rag/05-evaluation-security-and-production.md)).

## Human-in-the-loop (approval gates)

For **irreversible or high-impact** actions — sending money/email, deleting data, prod
writes, running shell/SQL — pause and get a human decision. The canonical four options:
**approve / edit / reject (with feedback) / respond.** (LangGraph implements this with an
`interrupt()` + a checkpointer that persists state until the human answers.)

> ⚠️ **Approval fatigue is real.** Anthropic found users approved **~93%** of permission
> prompts, and *more* prompting led to *less* careful review. So **gate selectively** — on
> genuinely consequential actions only. A prompt for every trivial step trains people to
> rubber-stamp, which is worse than no gate.

## Least privilege — tools are the attack surface

The biggest lever is giving the agent the **minimum capability** the task needs:

- A read-only agent (Read/Glob/Grep) "can analyze anything and damage nothing." Add write
  power only where required.
- Minimize the number of tools and the scope of each; avoid open-ended extensions.
- **Authorize in the downstream system, not in the LLM.** Don't trust the model to decide
  whether an action is allowed — enforce permissions in the API/database/OS that actually
  executes it. ⚠️ Watch for "bypass" modes that ignore your tool allowlist; deny-by-default
  is the safe posture.

### OWASP LLM06: Excessive Agency
The formal name for "the agent could do more than it should." Three root causes
([OWASP LLM Top 10 2025](https://genai.owasp.org/llmrisk/llm062025-excessive-agency/)):

| Root cause | Meaning | Fix |
|---|---|---|
| **Excessive functionality** | Tools/functions beyond what the task needs | Strip unneeded tools |
| **Excessive permissions** | Downstream access beyond what's needed | Scope credentials (OAuth) tightly |
| **Excessive autonomy** | Acts on high-impact steps without verification | Human approval gate |

## The lethal trifecta (injection that exfiltrates)

This is the most important security concept for agents. Prompt injection (Module 2)
becomes *dangerous* when an agent combines all three of:

1. **Access to private data**, **+**
2. **Exposure to untrusted content** (a web page, email, doc, tool result — which may carry
   hidden instructions), **+**
3. **The ability to communicate externally** (any tool that can make an outbound request).

With all three, injected instructions in the untrusted content can make the agent **read
private data and send it to an attacker** — classically by embedding it in a URL the agent
fetches. [(Simon Willison — the lethal trifecta)](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/)

**Defense:** break the trifecta. Once an agent has ingested untrusted content, constrain it
so that content can't trigger consequential or outbound actions — restrict egress to an
allowlist, drop tool privileges after ingesting untrusted data, or split the work across a
privileged tool-using agent that never sees raw untrusted content and a quarantined agent
that does. A useful heuristic is the **"Rule of Two"**: try not to satisfy more than two of
the three legs in one session.

## Cost & latency control

Safety and budget share the same knobs:

- **Max-turns cap** — the primary defense against both loops and runaway spend.
- **Token budgets** — abort when exceeded.
- **Model per step** — cheap model for routing/triage/guardrails, strong model only for the
  hard subtasks ([Module 1](../part-01-model-landscape/00-how-to-choose-a-model.md)).
- **Early stopping** — a tripwire before the expensive model means it never even runs on a
  bad request.

## The mindset: defense in depth

No single control stops a determined prompt injection — the model is **not** a security
boundary. Layer the defenses: least-privilege tools **+** guardrails **+** selective human
gates **+** downstream authorization **+** trifecta-breaking **+** tracing
([lesson 06](06-evaluating-and-operating-agents.md)). And never rely on the model to police
itself.

---

## Next

→ [Evaluating & operating agents](06-evaluating-and-operating-agents.md)
