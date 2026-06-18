---
title: Embeddings & vector stores
module: 03 — Retrieval-Augmented Generation
lesson: 02
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, rag, embeddings, vector-database, ann]
---

# Embeddings & vector stores

How chunks become searchable. Two pieces: the **embedding model** that turns text into
vectors, and the **vector store** that indexes those vectors for fast nearest-neighbor
search.

## How embeddings work

An **embedding model** maps a piece of text to a fixed-length **vector** (e.g. 768–4096
floating-point numbers). The trick: semantically similar text lands close together in
that space, so "find relevant chunks" becomes "find nearby vectors."

- **Similarity** is usually **cosine similarity** (the angle between two vectors). Many
  models return **L2-normalized** vectors, in which case cosine, dot-product, and
  Euclidean rank results identically — and dot-product is fastest to compute.
  [(OpenAI embeddings guide)](https://developers.openai.com/api/docs/guides/embeddings)
- **Dimensions** trade quality for storage/speed: more dimensions ≈ more capacity, but a
  bigger index and slower search.
- **Matryoshka (MRL)** embeddings are trained so you can **truncate** the vector (drop
  trailing dimensions) and still keep most of the meaning — a quality/cost dial you set at
  query time (e.g. 3072 → 1024 → 256) *without re-embedding*.

**Practical rules:** embed query and documents with the **same model**; store the model
**version** with the vectors (an embedding upgrade requires re-embedding the whole corpus
— vector spaces aren't compatible across models); normalize if your store expects it.

## Choosing an embedding model (June 2026)

> ⚠️ **The most volatile facts in this module.** Names, dimensions, and benchmark scores
> change monthly, and cross-leaderboard scores aren't strictly comparable. **Re-verify on
> the live [MTEB leaderboard](https://huggingface.co/spaces/mteb/leaderboard)** before
> committing. Snapshot below is ~March–June 2026.

| Model | Provider | Dims (range) | Notes |
|---|---|---|---|
| **Gemini Embedding** | Google | 3072 (768–3072 MRL) | Strong general; multimodal variant embeds text+image+more in one space |
| **OpenAI text-embedding-3-large / -small** | OpenAI | 3072 / 1536 | The proprietary default at scale; cheap, well-supported |
| **Voyage-3-large** | Voyage AI | 2048 | Quality-first proprietary option |
| **Cohere Embed v4** | Cohere | 1024 (256–1536) | Pairs with Cohere Rerank for grounded RAG |
| **Qwen3-Embedding (0.6/4/8B)** | Alibaba (open) | up to 4096 (32–4096 MRL) | Top open family; flexible dims, long context, strong on code |
| **BGE-M3** | BAAI (open) | — | The common open production default — native dense **+ sparse + multi-vector** in one model |
| **Nomic / E5** | open | — | Solid size/quality balance; popular in local RAG |

(These overlap the embedding section of [Module 1's local-model catalog](../part-01-model-landscape/03-top-100-local-models.md) — cross-reference for self-hosting.)

**Quick guidance:** proprietary default at scale → OpenAI `text-embedding-3-large`;
quality-first → Voyage / Cohere; multimodal → Gemini; self-hosting → Qwen3-Embedding or
**BGE-M3** (a very common open stack is **BGE-M3 + BGE-reranker**). Anthropic's own
Contextual Retrieval tests favored Gemini and Voyage embedders.

## Vector databases

Where vectors + metadata live and get searched.

| Store | Shape | Reach for it when |
|---|---|---|
| **pgvector / pgvectorscale** | Postgres extension | Your data is already in Postgres — one system, transactional, metadata joins. `pgvectorscale` pushes the old ~10–50M-vector ceiling much higher. |
| **Qdrant** | Purpose-built (Rust) | Low latency + rich metadata filtering; great default dedicated store. |
| **Weaviate** | Purpose-built, OSS | Modular, native hybrid search, per-tenant sharding. |
| **Milvus** | Purpose-built | Billion-scale self-hosting. |
| **Chroma** | Lightweight | Local dev / prototyping. |
| **FAISS** | Library (not a server) | Maximum control, embeddable; you build the service around it. |
| **Pinecone** | Fully managed / serverless | You don't want to run infrastructure. |

[(Firecrawl — best vector DBs)](https://www.firecrawl.dev/blog/best-vector-databases)

## ANN indexes (how nearest-neighbor stays fast)

Exhaustively comparing the query vector to millions of chunks is too slow, so vector
stores use **Approximate Nearest Neighbor (ANN)** indexes:

- **HNSW** (graph-based) — best recall/latency for most workloads, absorbs inserts
  without rebuilds. Memory-hungry. **The de-facto default.** Tune `ef_search` to dial
  recall ↔ latency at query time.
- **IVF / IVFFlat** (cluster into lists, search a few) — better when memory is tight and
  the corpus is huge (50M+) and fairly static. Tune `nprobe`.
- **Quantization** (scalar / product / binary) compresses vectors in memory — scalar
  quantization is ~4× smaller at <1% recall loss (nearly free); binary is up to ~32× but
  lossy and needs rescoring.

**The tradeoff to remember:** *recall ↔ latency ↔ memory ↔ build/update cost.* HNSW for
quality and frequent inserts; IVF + quantization for billion-scale on constrained
hardware. And **you rarely need 99% recall** — targeting 90–95% can roughly **triple**
throughput versus chasing 99%.

## Hybrid search needs both indexes

Pure vector search misses exact terms (error codes, names, rare keywords); pure keyword
search misses paraphrases. The strong default is **hybrid search** — run a dense
(embedding) query *and* a sparse (BM25/keyword) query and fuse the results. That's a
retrieval-quality technique, covered next → [lesson 03](03-retrieval-quality.md). Build
the keyword index alongside the vectors now so you have the option.

---

## Next

→ [Retrieval quality](03-retrieval-quality.md) — where most real-world RAG quality is won
or lost.
