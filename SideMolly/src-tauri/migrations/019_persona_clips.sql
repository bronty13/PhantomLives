-- v0.23.0 — per-persona intro / outro clips for YouTube master assembly.
--
-- YouTube bundles bookend their assembled master with a persona-specific
-- intro and outro clip (intro replaces the generated title card):
--   intro + clip1 ⤫ clip2 ⤫ … ⤫ clip[n] + outro   (⤫ = cross-dissolve)
--
-- Each persona has up to two clips (one intro, one outro). Each is
-- independently enable/disable-able and defaults OFF until Sallie uploads
-- a clip AND turns it on. The actual video lives on disk under
-- ~/Downloads/SideMolly/persona-clips/; only its path + enabled flag are
-- recorded here. Keyed by (persona_code, role) and UPSERTed, mirroring the
-- per-persona `watermark_profiles` table (migration 005). `persona_code`
-- uses '' for the no-persona default, same convention as the Watermark
-- settings pane.

CREATE TABLE IF NOT EXISTS persona_clips (
    persona_code  TEXT NOT NULL,
    role          TEXT NOT NULL CHECK(role IN ('intro','outro')),
    clip_path     TEXT NOT NULL DEFAULT '',
    enabled       INTEGER NOT NULL DEFAULT 0,
    updated_at    TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (persona_code, role)
);
