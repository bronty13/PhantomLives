---
title: Vision & document understanding
module: 09 — Multimodal & Generative Media
lesson: 01
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, vision, ocr, documents, multimodal]
---

# Vision & document understanding

This is the **image-in → text-out** cell of the [modality matrix](00-multimodal-fundamentals.md):
you hand a model a picture or a document and it answers questions, extracts
fields, or describes what it sees. It is the most mature and widely-supported
multimodal capability — nearly every frontier model does it.

> ⚠️ **Dated snapshot — June 2026.** Model tables and prices below are a
> point-in-time picture. Read the durable framing first; re-verify catalogs at
> the provider links.

---

## The three ways to "read" a document (most important concept)

Before any model table, internalize this: "read a document" is not one
operation. It is three escalating, differently-priced tiers, and picking the
wrong one is the most common and expensive mistake in document AI.

1. **Plain OCR** — pixels → a flat character stream. Loses all structure
   (tables become word soup). Cheapest; dedicated services like AWS Textract
   *DetectDocumentText*.
2. **Layout-aware extraction** — OCR *plus* geometry: reading order, blocks,
   tables (rows/columns/merged cells), key–value form pairs, and a
   **bounding box** per element. This is the "Document AI / IDP" tier —
   Mistral OCR, AWS Textract *AnalyzeDocument*, Azure Document Intelligence,
   Google Document AI.
3. **Document reasoning** — a multimodal LLM ingests the page image (or native
   PDF) and answers / extracts structured JSON in one pass, fusing OCR + layout
   + world knowledge. Most flexible (arbitrary schema, follow-up questions),
   but you pay LLM token rates per page.

The durable decision: **dedicated OCR wins on cost-per-page at scale and on
faithful table/coordinate fidelity; LLM-native ingestion wins on flexibility
and arbitrary-schema extraction.** Mature stacks combine them — a cheap
layout-aware pass produces markdown + boxes that *feed* an LLM — or use a single
LLM pass when accuracy and latency allow.

---

## Native PDF vs. render-to-image

"Accepts PDF" means one of two very different things:

- **Native document modality** — you upload the PDF bytes and the API renders
  pages and extracts text internally (Gemini, OpenAI Responses API, Amazon
  Nova, Mistral Document AI, **Claude**). Billed as image tokens per page.
- **You rasterize yourself** — convert each page to a PNG and send it as an
  image. Required for image-only vision models that have no document modality.

If a model offers native PDF, use it: it handles the text layer, page splitting,
and mixed text/image pages for you.

---

## Grounding: when you need coordinates, not prose

"Grounding" means the model returns **where** something is, not just **what** it
is — bounding boxes `[x0,y0,x1,y1]`, points, or segmentation masks. You need it
for click-targeting (computer-use agents), redaction, and *verifiable*
extraction (every field carries a box you can audit). Conventions differ wildly
— Gemini normalizes coordinates to `[0,1000]`, others use raw pixels or `[0,1]`
— so always check the per-model output format. Gemini and Qwen-VL have the
strongest grounding; most other LLMs only approximate boxes when prompted.

---

## The Claude lineup — modality & vision pricing

*Source: the repo's `claude-api` skill (authoritative current Anthropic facts).
Verify live with the Models API (`capabilities["image_input"]["supported"]`) or
[platform.claude.com](https://platform.claude.com/docs/en/build-with-claude/vision).*

Claude's modality shape is narrow and worth stating plainly: **every current
model is text + image-in → text-out.** None generate images or video, and there
is no audio in or out. A "multimodal Claude" pipeline means *understanding*
images and PDFs — generation and audio are handed to other providers (lessons
02–03).

| Model | ID | Modalities in | Context / Max out | Price (in/out per 1M) |
|---|---|---|---|---|
| **Claude Fable 5** | `claude-fable-5` | text, image | 1M / 128K | $10 / $50 |
| **Claude Opus 4.8** | `claude-opus-4-8` | text, image | 1M / 128K | $5 / $25 |
| **Claude Opus 4.7** | `claude-opus-4-7` | text, image | 1M / 128K | $5 / $25 |
| **Claude Sonnet 4.6** | `claude-sonnet-4-6` | text, image | 1M / 64K | $3 / $15 |
| **Claude Haiku 4.5** | `claude-haiku-4-5` | text, image | 200K / 64K | $1 / $5 |

Key Claude vision facts:

- **Vision is billed as plain input tokens** — image-token-count × the model's
  input rate. No separate vision surcharge. So the same downscale-to-fit rule
  from lesson 00 directly cuts cost.
- **High-resolution vision (Opus 4.7+, Fable 5).** Up to **2576px on the long
  edge** (up from 1568px on earlier models); a full-res image can use up to
  ~4784 image tokens. Coordinates the model returns map **1:1 to actual pixels**
  (no scale-factor math). It's automatic — no beta header. The flip side:
  full-res images cost ~3× the tokens of the old cap, so downsample when you
  don't need the fidelity.
- **Native PDF, no beta header.** Send a `document` content block with a base64
  PDF source. Limits: **32 MB per request, 600 pages** (100 pages on the
  200K-context Haiku tier). Or upload via the Files API and reference by
  `file_id` to reuse across calls.
- **Citations.** Set `citations: {enabled: true}` on a document block and the
  response splits into cited text blocks carrying `page_location` /
  `char_location` — grounded answers with provenance. (Incompatible with
  structured outputs / `output_config.format`.)

```python
# Claude vision + native PDF (Python SDK)
import base64, anthropic
client = anthropic.Anthropic()

with open("scan.pdf", "rb") as f:
    pdf_b64 = base64.standard_b64encode(f.read()).decode()

resp = client.messages.create(
    model="claude-opus-4-8",
    max_tokens=4096,
    messages=[{"role": "user", "content": [
        {"type": "document",
         "source": {"type": "base64", "media_type": "application/pdf", "data": pdf_b64},
         "citations": {"enabled": True}},
        {"type": "text", "text": "Extract every invoice line item as JSON."},
    ]}],
)
```

---

## Snapshot — other frontier vision models (June 2026)

Prices per **1M tokens** (image input billed at the input rate × the image's
token count). *Verify at each provider's pricing page.*

| Provider / Model | Status | Modalities in | Context | In / Out |
|---|---|---|---|---|
| **OpenAI GPT-5.5** | GA | text, image, **PDF** (Responses API) | 1M | $5 / $30 |
| **OpenAI GPT-5.4** | GA | text, image, document | 1M | $2.50 / $15 |
| **Google Gemini 3.5 Flash** | GA | text, image, **video, audio, PDF** | ~1M | $1.50 / $9 |
| **Google Gemini 2.5 Pro** | GA | text, image, video, audio, PDF | 1M | $1.25 / $10 (>200K: $2.50 / $15) |
| **Google Gemini 2.5 Flash-Lite** | GA | text, image, video, audio, PDF | 1M | $0.10 / $0.40 (cheapest multimodal) |
| **Meta Llama 4 Scout** | GA (open weights) | text, image | **10M** | self-host / hosted varies |
| **Mistral Pixtral Large** | GA | text, image | 128K | ~$2 / $6 |
| **Amazon Nova 2 Lite** | GA | text, image, **video** | up to 1M | $0.30 / $2.50 |
| **Qwen3-VL** (Alibaba) | GA (open weights) | text, image, **video** | 256K→1M | DashScope tiered |

Notes that the tables hide:
- **Gemini is the multimodal generalist** — the only mainstream lineup that
  ingests native **video and audio** alongside image and PDF, with the strongest
  grounding (boxes, points, masks, even 3D). Default here for video/audio
  understanding and long documents (2M-class context).
- **Llama 4 Scout / Qwen3-VL are the open-weight vision picks** — runnable
  locally (see [lesson 04](04-local-and-on-device.md)).
- The Gemini version naming is confused across 3.x in second-party sources;
  trust the first-party pricing page.

---

## Document-specialist tools (June 2026)

When you need layout-aware extraction at scale (tier 2 above), dedicated OCR
beats an LLM on cost-per-page and table fidelity:

| Tool | What it does | Pricing | Source |
|---|---|---|---|
| **Mistral OCR 3** | Markdown + table reconstruction, handwriting, forms, **box-level grounding**, confidence | $2 / 1k pages ($1 batch) | mistral.ai/news/mistral-ocr-3 |
| **AWS Textract** | OCR + forms + tables + IDs; boxes | tiered (~$1.50/1k OCR → volume discounts) | aws.amazon.com/textract/pricing |
| **Google Document AI** | OCR + form/layout parsers; boxes | ~$0.60–1.50 / 1k; 300 free/mo | cloud.google.com/document-ai/pricing |
| **Azure Document Intelligence** | Read/Layout/prebuilt/custom; boxes, KV | ~$1.50 / 1k Layout; 500 free/mo | azure.microsoft.com/.../document-intelligence |

---

## Multimodal RAG (cross-link)

When your knowledge base contains images, charts, or scanned pages, you have two
choices, and this is a direct extension of **[Module 3 — RAG](../part-03-rag/02-embeddings-and-vector-stores.md)**:

1. **OCR-then-embed** — run layout-aware OCR, embed the resulting text, retrieve
   normally. Simple, cheap, loses visual detail (a chart's shape).
2. **Multimodal embeddings** — embed the page *image* directly into a shared
   image/text vector space (CLIP-style, or Cohere/Gemini multimodal embeddings),
   so a text query can retrieve a relevant figure. Captures the visual, costs
   more, fewer mature tools.

The retrieval-quality, grounding, and citation lessons from Module 3 all carry
over unchanged — the only new ingredient is the image-embedding step.

`★ Insight ─────────────────────────────────────`
- **"Read a document" is three tiers, not one.** Most over-spend comes from
  reaching for tier-3 LLM reasoning when tier-1 OCR (or just the existing text
  layer) would do — or under-spending on tier-2 layout extraction and then
  fighting an LLM that mangled a table.
- **Claude is text + image-in only** — strong at document reasoning and cited
  extraction, but it does not generate images or hear audio. Knowing exactly
  where a model sits on the modality matrix prevents an architecture built
  around a capability the model doesn't have.
`─────────────────────────────────────────────────`

## Next

→ [Audio, voice & realtime](02-audio-voice-and-realtime.md) — the audio↔audio
cell: ASR, TTS, and live voice agents.
