-- Phase 13 follow-up: per-note font size override. The frontend
-- applies a per-font visual-baseline scale (Paper Daisy reads small
-- at the same point size as a normal sans, etc.); on top of that
-- Sallie can pick a size multiplier per note (Tiny → Huge).
-- NULL = inherit app default (notes.defaultFontSizeScale in app_settings).
ALTER TABLE notes ADD COLUMN font_size_scale REAL;

INSERT OR IGNORE INTO app_settings (key, value) VALUES
    ('notes.defaultFontSizeScale', '1.0');
