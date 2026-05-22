-- Full per-run log file path. Complements `log_excerpt` (the last ~200
-- lines kept inline for the run-history pill expansion) with a pointer
-- to the complete on-disk log so the user can open it for debugging.
-- Path is relative to nothing — stored as an absolute path so we don't
-- have to re-resolve app_data_dir on every read.
ALTER TABLE background_job_runs ADD COLUMN log_path TEXT;
