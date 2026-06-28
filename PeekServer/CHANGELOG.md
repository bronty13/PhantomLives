# Changelog

## 0.1.0 — Phase 1 (LAN review MVP)

- New subproject: a dependency-free (Python stdlib + macOS `sips`/`qlmanage`) HTTP service for
  reviewing "NEW … TO REVIEW" media folders fast from any Mac/iPad on the LAN.
- **Scanner** (`scan.py`) walks configured roots → SQLite, decision-safe on re-scan (preserves
  keep/skip/metadata; marks vanished files missing).
- **Decisions DB** (`db.py`) mirrors PurplePeek's schema (keep, favorite, title, caption,
  keywords, albums, hidden) — one authoritative server-side store shared by all clients.
- **Thumbnails** (`media.py`) generated once via `sips` (images, incl. HEIC) / `qlmanage` (video
  posters) and cached on the server's local disk → browsing never reads the big originals.
- **HTTP server** (`server.py`, stdlib): web UI + JSON API + `/thumb` (cached) + `/full`
  (Range-aware, so video plays in-browser).
- **Web UI** (`web/`): keyboard-driven thumbnail grid (K/X/F/U), filter tabs with live counts,
  per-root switching, detail overlay with full media + editable title/caption/keywords/albums.
- `config.example.json` committed; real `config.json` gitignored (may carry local paths).
