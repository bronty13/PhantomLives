# Changelog

## Unreleased — 2026-05-16

### Status
- **Paused before first release.** End-to-end blocked on Slack's form-file ACL
  rule (form-uploaded files require an explicit share-into-channel step before
  the bot can read them via `files.info`). Local install removed; source kept.
  See `HANDOFF.md` for the full context, dead ends to avoid, and the three
  candidate paths forward.

### Added during this iteration
- Discovered and worked around the `slack#/types/file_id` Workflow Builder
  bug ([bolt-js#2407](https://github.com/slackapi/bolt-js/issues/2407)) by
  switching the audio_file input to `slack#/types/rich_text` and extracting
  the file ID from the nested rich_text payload at runtime, matching the
  Roy0815/slack-service-bot reference pattern.
- Force-rebuild the WebClient with `context.function_bot_access_token` in the
  Bolt handler so the per-execution token (not the static `xoxb-`) is used
  for downstream API calls. Did not fix file_not_found on its own — the
  share-first workflow restructure is still required.
- Install path moved to `~/Library/Application Support/ContentSubmission/`
  to escape macOS TCC restrictions on `~/Documents/`-based launchd jobs.

## 1.0.0 — 2026-05-16

### Added
- Initial release. Custom Slack Workflow Builder step (`post_content_submission`)
  that replaces the legacy "Send a message to a channel" step in the Content
  Submission workflow.
- Resolves the uploaded audio file via `files.info` and posts the file's
  permalink, so Slack renders an inline playable audio player in the channel
  instead of the raw `F0…` file ID.
- Block Kit message layout: header, Persona / Title / GoLive Date fields,
  Video URL, Description (audio), and optional Special Requests.
- Graceful degradation: if `files.info` fails, the submission is still posted
  with a `:warning:` note so the submitter's work isn't lost.
- Bolt for Python + Socket Mode runtime. No public HTTPS endpoint required.
- `install.sh` — creates a Python venv, installs deps, captures Slack tokens
  to `~/.config/content-submission/.env` (chmod 600), renders the launchd
  plist with absolute paths, and starts a `KeepAlive` job.
- `uninstall.sh` — removes the launchd job; `--purge` also drops the venv.
- `run.sh` — foreground DEBUG-logging run for development.
- Slack app manifest (`manifest.yaml`) with the function definition.
- pytest test suite (12 tests) covering block builder happy path, optional-field
  omission, whitespace handling, missing-audio fallback, missing-video
  fallback, fallback-text generation, and the permalink resolver.
