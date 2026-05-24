-- Phase 4.5 — Auto-Assembly app-level settings.
--
-- One row, keyed `1`. Holds the defaults that the auto-assemble
-- enqueue command reads at the moment the user clicks "🎞 Auto-
-- assemble". Defaults match the PLAN.md §8.5 spec — 1920x1080 @ 30fps,
-- 1.0s xfade between every clip, 10s title card.
--
-- Audio enhancement: loudnorm targets podcast-grade -16 LUFS plus a
-- mild compressor and two EQ bumps (200Hz warmth, 3kHz presence).
-- Settings stores the chain as flags so the UI can toggle individual
-- steps without re-encoding the filter graph at every run.

CREATE TABLE IF NOT EXISTS auto_assembly_settings (
    id                      INTEGER PRIMARY KEY CHECK(id = 1),
    target_width            INTEGER NOT NULL DEFAULT 1920,
    target_height           INTEGER NOT NULL DEFAULT 1080,
    target_fps              INTEGER NOT NULL DEFAULT 30,
    xfade_duration_secs     REAL    NOT NULL DEFAULT 1.0,
    title_duration_secs     REAL    NOT NULL DEFAULT 10.0,
    audio_enhance_enabled   INTEGER NOT NULL DEFAULT 1,
    deepfilternet_enabled   INTEGER NOT NULL DEFAULT 0, -- Phase 4.5b
    updated_at              TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO auto_assembly_settings (id) VALUES (1);
