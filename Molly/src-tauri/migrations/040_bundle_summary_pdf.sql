-- v1.33.0 — Store SideMolly's Summary PDF from the imported return file.
--
-- SideMolly (v0.28.0+) bundles a human-readable Summary PDF into the return
-- file at `artifacts/summary.pdf`, pointed to by report.json's `summaryPdf`
-- field. On import we extract those bytes and keep them here so the PDF is
-- available straight from the bundle detail (Open report / Download) long
-- after the source ZIP is cleaned up.
--
-- One row per bundle (PRIMARY KEY on bundle_uid); a re-import REPLACEs it so
-- the stored PDF always reflects the most recently imported return file.
-- ON DELETE CASCADE drops the blob if the bundle row is ever removed.

CREATE TABLE IF NOT EXISTS bundle_summary_pdf (
    bundle_uid   TEXT    PRIMARY KEY REFERENCES bundles(uid) ON DELETE CASCADE,
    filename     TEXT    NOT NULL,
    size_bytes   INTEGER NOT NULL,
    pdf_data     BLOB    NOT NULL,
    imported_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);
