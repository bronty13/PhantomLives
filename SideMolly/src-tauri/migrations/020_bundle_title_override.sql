-- v0.24.0 — editable working title.
--
-- SideMolly can now override a bundle's title for processing/output while
-- preserving Molly's original. The original stays in `bundles.title`; the
-- override lives here. The "effective title" used everywhere
-- (master-cut filename, title card, Dropbox {title} folder, posting {title}
-- URL, and all display) is COALESCE(NULLIF(title_override,''), title) — so
-- an empty override means "use the original". The change is surfaced in the
-- post-bundle (report.json originalTitle/workingTitle + notes.md).
--
-- A nullable/defaulted column add needs no table rebuild, so a plain
-- ALTER TABLE ... ADD COLUMN is sufficient (and the immutability guard still
-- hashes this file like any other migration).

ALTER TABLE bundles ADD COLUMN title_override TEXT NOT NULL DEFAULT '';
