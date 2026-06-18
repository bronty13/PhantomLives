---
title: Top ~100 local models
module: 01 — Model Landscape
lesson: 03
est_time: 30 min reference
last_reviewed: 2026-06-18
tags: [ai, models, open-weight, local, catalog]
---

# Top ~100 local models

A categorized catalog of locally-runnable (open-weight) models with one-line use
cases. Popularity is **anchored to live Hugging Face Hub data (June 2026)** —
download/like counts noted for the headliners so you can see what people actually
run, not just what's hyped.

> ⚠️ **Dated snapshot — June 2026, and it rots fast.** New flagships land weekly.
> Read [the local ecosystem page](02-open-weight-local-ecosystem.md) first for
> hardware sizing, quantization, and the **licensing trap** (Apache/MIT = safe for
> commercial; Llama/Cohere/Grok/Flux-Dev = restricted). Param sizes and 1T-class
> active-param figures are approximate; verify on Hugging Face before relying on one.

**Notation:** sizes like `35B-A3B` = MoE (total / active). "HF: 8.3M↓ / 6.1k♥" = lifetime
downloads / likes on Hugging Face, June 2026.

---

## A. General-purpose chat / assistant

1. **Qwen3** (0.6B / 1.7B / 4B / 8B / 14B / 32B; `-Instruct-2507` refreshes) — Apache 2.0 — *the* default "what do I run locally," every size. HF: Qwen3-0.6B **24.5M↓**, Qwen3-4B 14.1M↓, Qwen3-8B 11.5M↓.
2. **Qwen 3.5 / 3.6** (27B dense, 35B-A3B MoE, 122B, 397B) — Apache 2.0 — current Qwen flagship line; hybrid reasoning + agentic. (`Qwen3.6-35B-A3B` NVFP4 quant HF: 2.7M↓.)
3. **Llama 3.1-8B-Instruct** — Llama license — the most-*liked* open model on HF (**8.3M↓ / 6.1k♥**); rock-solid 8B workhorse, enormous fine-tune ecosystem.
4. **Llama 3.3-70B** — Llama license — last strong dense Llama; capable 70B general assistant.
5. **Llama 3.2 (1B / 3B)** — Llama license — tiny on-device Llama for edge/mobile. HF: 1B 7.2M↓.
6. **Llama 4 Scout / Maverick** (109B/17B-A; 400B/17B-A; MoE, multimodal) — Llama Community — MoE multimodal; Scout has up-to-10M context.
7. **Gemma 4** (E2B / E4B / 12B / 26B-A4B / 31B; multimodal) — Apache 2.0 — Google's Apr-2026 family from Gemini 3 research; vision + long context, phone-to-datacenter.
8. **Gemma 3** (1B / 4B / 12B / 27B; 270m nano) — Gemma license — prior gen, still hugely downloaded; multimodal from 4B, 140+ languages. HF: gemma-3-270m **7.3M↓**.
9. **gpt-oss** (20b / 120b; MoE, MXFP4) — Apache 2.0 — OpenAI's open-weight models; 20b on 16 GB, 120b on one 80 GB GPU / big Mac. HF: 120b 3.7M↓ / 4.9k♥, 20b 6.1M↓.
10. **DeepSeek V3.2** (671B/37B-A) — MIT — sparse-attention general+agentic workhorse. HF: 3.2M↓.
11. **DeepSeek V4-Pro / V4-Flash** (1.6T/49B-A; 284B/13B-A) — MIT — Apr-2026 frontier MoE, 1M context; Flash is the cheap variant. HF: V4-Pro **2.9M↓ / 4.9k♥**, V4-Flash 2.4M↓.
12. **GLM-5.1 / GLM-5.2** (Z.ai; ~754B/40B-A MoE) — MIT — top-tier agentic + long-context; among the highest-*trending* models on HF in June 2026 (GLM-5.1 1.8k♥).
13. **GLM-4.7-Flash** (30B/3B-A MoE) — MIT — one of the best *local* coding/agent options at consumer scale.
14. **Kimi K2.6** (Moonshot; 1T/32B-A MoE, 256K, native multimodal) — Modified MIT — leading open agentic/coding model; ties top closed models on coding.
15. **MiniMax M2.7 / MiniMax-01** (230B/10B-A; 456B/45.9B-A, 4M context) — Apache 2.0 / other — self-evolving agentic systems; -01 for ultra-long context. HF: M2.7 2.5M↓.
16. **Mistral Small 4** (119B/6B-A MoE) — Apache 2.0 — unifies reasoning+vision+coding, configurable reasoning effort; the new Mistral local default.
17. **Mistral Large 3** (675B/41B-A MoE) — Apache 2.0 — Mistral's multimodal reasoning flagship.
18. **Mistral Nemo (12B) / Mistral 7B** — Apache 2.0 — classic efficient workhorses, still widely run.
19. **NVIDIA Nemotron 3** (Nano 4B / Super 120B-A12B / Ultra 550B-A55B; Mamba-2 hybrid) — NVIDIA Open — 1M context, high throughput, edge-to-datacenter. HF: Ultra-NVFP4 257K↓.
20. **IBM Granite 4.0 / 4.1** (2–8B class + MoE) — Apache 2.0 — enterprise RAG/tool-use/JSON, multilingual, business-friendly.
21. **OLMo 3 / 3.1** (7B, 32B; Think + Instruct) — Apache 2.0 — the only *fully open* (data+code+weights) frontier-ish family; 32B rivals Qwen/Gemma.
22. **Yi 1.5** (6B / 9B / 34B; 01.AI) — Apache 2.0 — strong bilingual EN/ZH; popular fine-tune base.
23. **Falcon 3 / Falcon-H1** (TII; 1B–34B, hybrid SSM variants) — permissive — lightweight multilingual general models.
24. **AI21 Jamba Large 1.7** (398B/94B-A, SSM-Transformer hybrid) — Jamba Open — low-latency long-context.
25. **MiMo-V2.5-Pro** (Xiaomi) — MIT — agentic/long-context with speculative decoding. HF: 81K↓.

## B. Coding & agentic software engineering

26. **Qwen3-Coder** (30B-A3B; 480B/35B-A) — Apache 2.0 — RL-trained on SWE-bench; best open agentic coder, repo navigation + tool use; 256K–1M context.
27. **Qwen2.5-Coder** (0.5B–32B) — Apache 2.0 — still enormously downloaded; 32B ≈ GPT-4o on Aider; great fill-in-the-middle. HF: 7B 2.0M↓, 14B 3.7M↓.
28. **Devstral 2 / Devstral Small 2** (Mistral; 123B dense / 24B) — agentic SWE; Small 2 fits a 4090 or 32 GB Mac.
29. **Codestral** (22B; Mistral) — best-in-class fill-in-the-middle autocomplete.
30. **GLM-4.7-Flash / GLM-5.x** — MIT — top open coding-agent performance (5.x at frontier, Flash for local).
31. **Kimi K2.6** — Modified MIT — ties top closed models on coding/agentic benchmarks; agent-swarm orchestration.
32. **DeepSeek-Coder / DeepSeek-Coder-V2** (1.3B–236B/21B-A) — MIT — strong dedicated code MoE.
33. **CodeLlama** (7B/13B/34B/70B; Meta) — legacy but still widely used code base + FIM.
34. **StarCoder2** (3B/7B/15B; BigCode) — open, permissive, broad-language code completion.
35. **CodeQwen / CodeGemma** (7B class) — code-specialized Qwen/Gemma variants.
36. **Cohere North-Mini-Code 1.0** (MoE) — Apache 2.0 — new trending compact coding/agent model (June 2026). HF: 15.3K↓ / 435♥.
37. **Community Gemma-4 coder distills** (e.g. `gemma-4-12B-coder-fable5-composer2.5-GGUF`) — Apache 2.0 — top-*trending* local coder on HF June 2026 (**211K↓ / 1.6k♥**); reasoning-distilled.

## C. Reasoning ("thinking" / chain-of-thought)

38. **DeepSeek-R1 / R1-0528** (671B/37B-A) — MIT — the reference open reasoning model; one of the most-liked models on HF (**R1 13.4k♥ / 6.0M↓**).
39. **DeepSeek-R1 distills** (Qwen-1.5B/7B/14B/32B, Llama-8B/70B) — MIT — R1 reasoning packed into small runnable sizes; the most popular way to get strong reasoning locally.
40. **QwQ-32B** (Qwen) — Apache 2.0 — dedicated 32B reasoner; runs on a 24 GB GPU.
41. **Qwen3 "-Thinking" variants** (4B/8B/30B-A3B-Thinking-2507) — Apache 2.0 — toggleable reasoning across sizes.
42. **OLMo 3.1-Think-32B** — Apache 2.0 — fully-open reasoning model competitive on MATH/BBH.
43. **Phi-4-Reasoning / Reasoning-Plus** (14B) — MIT — STEM reasoning (~75% AIME 2024), consumer-GPU friendly.
44. **Magistral** (Mistral) — reasoning mode now folded into Mistral Small 4 / Large 3.
45. **VibeThinker-3B** (Weibo) — MIT — trending tiny math/code reasoner (June 2026) that punches far above 3B. HF: 6.6K↓ / 368♥.
46. **HRM-Text-1B** (Sapient; hierarchical reasoning) — Apache 2.0 — experimental non-chat reasoning architecture. HF: 139K↓ / 780♥.

## D. Small / on-device (<5B)

47. **Qwen3-0.6B / 1.7B / 4B** — Apache 2.0 — the most-downloaded small models on HF; 0.6B runs literally anywhere (**24.5M↓**).
48. **Qwen2.5 0.5B / 1.5B / 3B** — Apache 2.0 — still top-downloaded tiny workhorses (1.5B 9.4M↓, 3B 10.1M↓).
49. **Gemma 4 E2B / E4B** & **Gemma 3 270m / 1B** — Apache 2.0 / Gemma — phone/CPU-class, multimodal from 4B.
50. **Llama 3.2 1B / 3B** — Llama — edge Llama for mobile assistants.
51. **Phi-4-mini** (~3.8B) — MIT — "runs on the machine you already have, no GPU."
52. **SmolLM3** (~3B; Hugging Face) — Apache 2.0 — strong fully-open small model, good fine-tune base.
53. **LiquidAI LFM2.5-8B-A1B** (MoE, 1B active) — edge-optimized, multilingual, very fast on-device. HF: 141K↓ / 620♥.
54. **Granite 4.0 small** (2–3B class) — Apache 2.0 — on-device enterprise tasks.
55. **Falcon 3-1B / 3B** — lightweight multilingual edge.
56. **Nemotron 3 Nano 4B** — NVIDIA Open — Jetson/edge devices.
57. **Microsoft FastContext-1.0-4B** (Qwen3-4B base) — MIT — trending repo-exploration "Explorer subagent" small model (June 2026).

## E. Vision-language (multimodal)

58. **Qwen3-VL** (incl. 235B-A22B flagship; smaller variants) — Apache 2.0 — the leading open VLM: multimodal reasoning, OCR, video, 2D/3D grounding.
59. **Qwen2.5-VL** (3B / 7B / 72B) — Apache 2.0 — still the most-deployed open VLM; 7B fits a 24 GB GPU.
60. **InternVL3** (8B–78B; Shanghai AI Lab) — MIT — strongest MIT-licensed VLM (~72% MMMU), industrial/3D reasoning.
61. **Gemma 4 / Gemma 3 (4B+)** — multimodal built in; vision without 400B-model infra cost.
62. **Llama 4 Maverick / Scout** — native image understanding in the Llama 4 MoE.
63. **Pixtral (12B; Mistral)** — Apache 2.0 — best small VLM for edge (drones, cameras, wearables); folded into Mistral Small 4.
64. **Phi-4-Multimodal** (~5.6B) — MIT — vision+audio+text on a 16 GB GPU.
65. **LLaVA / LLaVA-NeXT** (7B/13B/34B) — the classic open VLM lineage; huge ecosystem, easy to fine-tune.
66. **Molmo** (AllenAI; 7B/72B) — Apache 2.0 — fully-open VLM with pointing/grounding.
67. **MiniCPM-V** (~8B) — efficient strong-for-size VLM, popular for on-device multimodal.
68. **DeepSeek-VL2** (MoE) — MIT — DeepSeek's vision line.

## F. Embeddings & retrieval (RAG)

69. **Qwen3-Embedding** (0.6B / 4B / 8B) — Apache 2.0 — current near-SOTA open embedding family; 0.6B is a top-downloaded embedder (**9.1M↓**).
70. **BGE-M3 / BGE family** (BAAI) — MIT — the multilingual workhorse: dense+sparse+multi-vector in one, 100+ languages.
71. **Nomic-embed-text v1.5 / v2** — Apache 2.0 — best size/quality balance, 8192-token context, popular in local RAG.
72. **E5 / multilingual-E5** (`intfloat`) — MIT — reliable general retrieval baselines.
73. **mxbai-embed-large** (Mixedbread) — Apache 2.0 — strong English retrieval, popular in Ollama.
74. **GTE** (`Alibaba-NLP/gte-*`) — Apache 2.0 — strong general text embeddings.
75. **Llama-Embed-Nemotron-8B** (NVIDIA) — open — tops multilingual MTEB; strongest free multilingual option.
76. **Jina Embeddings v4** — multimodal (text+image) embeddings.
77. **BGE-reranker / Qwen3-Reranker** — companion cross-encoder rerankers for RAG pipelines.

## G. Long-context specialists

78. **Llama 4 Scout** (10M) — longest-context open-weight model.
79. **MiniMax-01** (4M) — Apache 2.0 — ultra-long-document workloads.
80. **DeepSeek V4** (1M, sparse attention) — efficient frontier long-context.
81. **Nemotron 3** (1M, Mamba-2 hybrid) — long context even on consumer GPUs (Nano).
82. **Qwen3-Coder / Qwen 3.5** (256K–1M with YaRN) — long-context coding/agents.
83. **Jamba 1.7** (256K, SSM hybrid) — low-latency long context.

## H. Multilingual specialists

84. **Aya Expanse / Aya 23 / Tiny Aya** (Cohere; 8B/32B/3.35B) — **CC-BY-NC (non-commercial)** — 23–70+ languages, research multilingual leader.
85. **Gemma 3/4** — 140+ languages.
86. **BGE-M3** — 100+ language retrieval.
87. **Qwen** family — strong EN/ZH + broad multilingual.
88. **Falcon 3 / Granite 4** — multilingual permissive options.
89. **Regional fine-tunes** (e.g. `prefeitura-rio/Rio` PT on Qwen3 — HF 2.0M↓; EuroLLM; Teuken) — language/region-specialized.

## I. Uncensored / roleplay / creative finetunes

*(Community fine-tunes — quality and safety vary; verify the base model's license.)*

90. **Dolphin** series (e.g. `dolphin-2.9.1-yi-1.5-34b`, HF 4.1M↓; on Qwen/Llama) — de-aligned general assistant, very popular.
91. **Nous Hermes / Hermes 3** (on Llama/Qwen) — balanced, strong general instruction-tuned line.
92. **"Heretic" / "Abliterated" / "OBLITERATED" Gemma-4 & Qwen tunes** — refusal-removed variants; top-trending GGUFs June 2026 (`Gemma-4-12B-OBLITERATED` 96.8K↓).
93. **Gryphe Gemma-4 StyleTune** (26B-A4B / 31B) — roleplay/creative-writing tunes, trending.
94. **MythoMax / Mytho lineage** (Llama-based) — long-standing roleplay favorites.
95. **`supergemma4-26b-uncensored` GGUFs** — fast Apple-Silicon-targeted uncensored Gemma 4 (HF 114.9K↓ / 854♥).

## J. Other specialized (audio / speech / image-gen — runnable locally)

96. **Whisper Large v3** (OpenAI) — MIT — 99-language speech-to-text; the universal local STT. *(This repo's `transcribe/` runs the MLX port on Apple Silicon.)*
97. **Higgs-Audio v3 TTS (4B)** — open expressive TTS, trending June 2026 (HF 57.4K↓). Also **Voxtral TTS** (Mistral), **Bark** (Suno).
98. **Flux.1 Schnell** (BFL, 12B) — Apache 2.0 — fast **commercial-OK** local image generation. *(Flux.1 Dev = non-commercial.)*
99. **Stable Diffusion 3.5** (Stability, 8B) — local image generation with LoRA/ControlNet.
100. **Z-Image-Turbo + prompt-engineer LMs** (e.g. `Z-Image-Engineer`) — Apache 2.0 — local image-gen prompt tooling, trending.

---

## What to actually run (the short answer)

- **Most people, most tasks:** **Qwen3** at the largest size your hardware allows
  (Apache 2.0, every category, ecosystem center of gravity).
- **Coding locally:** Qwen2.5-Coder / Qwen3-Coder, or GLM-4.7-Flash / Devstral Small 2
  on a beefier box.
- **Reasoning locally:** a DeepSeek-R1 distill (small) or QwQ-32B (24 GB GPU).
- **On a phone / 8 GB laptop:** Qwen3-4B or Gemma 4 E4B.
- **RAG embeddings:** Qwen3-Embedding-0.6B or BGE-M3.
- **Mac specifically:** prefer the MLX builds; run via LM Studio or Ollama.

## How to re-verify this page

Re-run the build pipeline in [HANDOFF.md](../HANDOFF.md): query the Hugging Face
Hub for top-downloaded + top-trending `text-generation` models, cross-check the
ecosystem page, refresh the entries and download anchors, then bump `last_reviewed`
and log it in [../CHANGELOG.md](../CHANGELOG.md). Treat very-new trending
entries (community distills, brand-new flagships) as unproven until they persist.

## Sources

Live Hugging Face Hub queries (top-downloaded & top-trending text-generation models,
June 2026); the HF "best open-weight LLMs to run locally 2026" guides; Ollama and LM
Studio catalogs; r/LocalLLaMA. Provider model cards for each family. Full source list
is in the build research behind this module (see [HANDOFF.md](../HANDOFF.md)).

---

← [The Open-Weight / Local Ecosystem](02-open-weight-local-ecosystem.md) ·
↑ [Module index](../CURRICULUM.md)
