---
title: Audio, voice & realtime
module: 09 — Multimodal & Generative Media
lesson: 02
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, audio, asr, tts, voice, realtime, speech]
---

# Audio, voice & realtime

This lesson covers the **audio cells** of the [modality matrix](00-multimodal-fundamentals.md):
speech-to-text (audio→text), text-to-speech (text→audio), and the increasingly
important diagonal, **speech-to-speech** (audio→audio) that powers live voice
agents.

> ⚠️ **Dated snapshot — June 2026.** ASR/TTS/realtime models and prices churn
> fast (several below changed in the weeks around this snapshot). Lead with the
> architecture; re-verify the numbers.

---

## The durable mental model: two voice-agent architectures

A voice assistant — phone IVR, in-app talk button, smart speaker — is built one
of two ways, and this choice dominates everything else:

- **Cascade (STT → LLM → TTS).** Three swappable components: transcribe the
  user's speech, reason over the text with any LLM, synthesize the reply.
  *Pros:* best-of-breed at each stage, a cheap text LLM in the middle, easy to
  log and guardrail the text, full control over the wording. *Cons:* latency
  *stacks* across three hand-offs, and you throw away paralinguistics — the LLM
  never hears the caller's tone, hesitation, or interruption.
- **Native speech-to-speech (one model).** Audio in → audio out in a single
  model (OpenAI Realtime, Gemini Live native audio). *Pros:* lowest hand-off
  latency, preserves prosody and emotion, natural interruption. *Cons:* pricier
  (audio tokens ≫ text tokens), less granular text-level control, fewer model
  choices, harder to insert deterministic logic mid-stream.

This is the same **pipeline-of-specialists vs. native-multimodal** tradeoff from
lesson 00, made concrete. The durable rule: **start with a cascade** — it's
cheaper, debuggable, and each part is replaceable — and graduate to native
speech-to-speech only when conversational latency or emotional nuance genuinely
matters.

### The latency budget

For a voice agent that feels natural, target **sub-800ms voice-to-voice** (p50
under ~400ms). A rough cascade budget:

```
~300ms telephony + ~150ms STT + ~200ms LLM TTFT + ~75ms TTS + network ≈ ~700ms
```

The **LLM's time-to-first-token is almost always the bottleneck** — which is
exactly why native speech-to-speech wins for live conversation: it collapses the
three hand-offs into one model and removes the inter-stage latency. (Latency
fundamentals — TTFT, streaming, perceived vs. real — are in
**[Module 7, lesson 04](../part-07-cost-and-latency/04-latency-engineering.md)**.)

---

## Speech-to-text (ASR) — snapshot, June 2026

| Provider · Model | Price | Mode | Notes |
|---|---|---|---|
| **OpenAI gpt-4o-transcribe** | ~$0.006/min | batch + streaming | higher accuracy than whisper-1, multilingual |
| **OpenAI gpt-4o-mini-transcribe** | ~$0.003/min | batch | cheapest OpenAI tier |
| **Google Cloud STT (Chirp 3)** | ~$0.064/min realtime; ~$0.004/min batch | both | 90+ languages |
| **AssemblyAI Universal-3 Pro** | $0.21/hr (~$0.0035/min) | batch | (Universal-2 / Slam-1 superseded) |
| **Deepgram Nova-3** | ~$0.0048/min stream | both | real-time multilingual code-switching |
| **ElevenLabs Scribe v2** | $0.22/hr batch; $0.39/hr realtime | both | claims >98% accuracy; API price cut ~45% in June 2026 |

**Open-weight Whisper.** OpenAI's open ASR lineage tops out at
**large-v3-turbo** (Sept 2024 — 4 decoder layers, much faster, can't translate;
use `large`/`medium` for translation). No newer open Whisper generation has
shipped — OpenAI's frontier ASR is now the *closed* gpt-4o-transcribe family.
You run large-v3-turbo locally via **whisper.cpp** or **MLX-Whisper** (see
[lesson 04](04-local-and-on-device.md); this is the engine behind the repo's
[`transcribe/`](../../transcribe/) tool).

---

## Text-to-speech (TTS) — snapshot, June 2026

| Provider · Model | Price | Cloning | Realtime latency |
|---|---|---|---|
| **OpenAI gpt-4o-mini-tts** | ~$0.015/min | **none** | steerable voice via NL instructions |
| **OpenAI tts-1 / tts-1-hd** | $15 / $30 per 1M chars | none | fixed voices |
| **ElevenLabs Flash v2.5** | ~$0.05/1k chars | instant + professional | **~75ms** (inference only) |
| **ElevenLabs Multilingual v3** | ~$0.10/1k chars | instant + professional | quality tier (now GA) |
| **Google Chirp 3: HD** | $30 / 1M chars | instant custom voice | — |
| **Cartesia Sonic-3.5** | ~$0.03/min | instant (3s) + professional | **~40ms** model-inference (≈100ms p90 end-to-end) |
| **PlayHT PlayDialog** | credit-based | yes | multi-turn 2-speaker, <300ms |

**Teaching caveat:** vendor "~75ms" / "~40ms" figures are *model-inference*
latency, **not end-to-end TTFB**. Cartesia itself publishes ~100ms p90 once
network is included. Always distinguish inference latency from the number your
user actually feels. (OpenAI is notable as the only major provider here with
**no voice cloning** — a clean line to draw when consent/likeness matters.)

---

## Realtime / speech-to-speech APIs — snapshot, June 2026

These are the native audio↔audio models — the "one model" architecture.

**OpenAI Realtime API:**

| Model | Status | Audio in / cached / out (per 1M) |
|---|---|---|
| **gpt-realtime-2** | GA (May 2026) | $32 / $0.40 / $64 (text $4 / $24) |
| **gpt-realtime** | GA (Aug 2025) | $32 / $0.40 / $64 |
| gpt-4o-realtime-preview | legacy (superseded) | — |

**Google Gemini Live API** — all current Live models are **Preview**, not GA:
`gemini-2.5-flash-native-audio-preview` (audio in $3 / out $12 per 1M),
`gemini-3.1-flash-live-preview` (newest). Stateful WebSocket; PCM 16kHz in /
24kHz out; session limits ~15 min audio-only.

The durable shape of any realtime stack:

- **Transport:** browser/device client → **WebRTC** (Opus + jitter buffer + NAT
  traversal, ~20–50ms media transport); backend ↔ model → **WebSocket** (event
  control); telephony → SIP.
- **Turn-taking:** server-side voice-activity detection (VAD) decides when the
  user stopped talking. "Semantic VAD" uses the content, not just silence, to
  detect end-of-turn.
- **Barge-in (interruption):** the user starts talking over the model; the API
  cancels the in-flight response. This is *the* feature that makes a voice agent
  feel human, and it's why native speech-to-speech beats a cascade for live
  conversation.

### Audio-token billing — the cost trap

Audio is tokenized **by duration, not characters**: input ~1 tok/100ms
(~600 tok/min of user speech), output ~1 tok/50ms (~1200 tok/min). Audio tokens
cost **far more than text** ($32/$64 vs. $4/$24 on gpt-realtime-2). The classic
blow-up: a verbose, *uncached* system prompt re-ingested every turn. Note the
steeply discounted **cached input** rate ($0.40/1M) — prompt caching
(**[Module 7, lesson 02](../part-07-cost-and-latency/02-caching.md)**) is even
more valuable here than in text-only work, because the per-token stakes are
higher.

`★ Insight ─────────────────────────────────────`
- **Cascade vs. native is the whole game.** A cascade is three cheap, swappable,
  loggable parts with stacking latency; native speech-to-speech is one
  expensive low-latency model that hears tone and handles interruption. Default
  to the cascade; upgrade only when live conversation demands it.
- **The LLM's TTFT is the latency bottleneck** in a cascade — so everything you
  learned about streaming, effort, and prefix-cache TTFT in Module 7 is the
  lever that makes a voice agent feel responsive.
`─────────────────────────────────────────────────`

## Next

→ [Image & video generation](03-image-and-video-generation.md) — the
text→pixels cell.
