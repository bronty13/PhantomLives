# ContentSubmission — Handoff

**Status:** Paused, not working end-to-end. Source code is here; runtime has been uninstalled from the maintainer's Mac. The Slack app at api.slack.com/apps may still exist depending on whether the cleanup steps below have been executed.

**Date paused:** 2026-05-16

## Goal of this subproject

Replace Step 2 of the existing `Content Submission` workflow in the `sheer-enterprise` Slack workspace. The classic "Send a message to a channel" step renders the form-uploaded audio file as a raw `F0…` file ID instead of a clickable/playable file. Spec lives at `~/Downloads/content-submission-workflow-current-state.md`.

This app is a Bolt-for-Python + Socket Mode Slack app that registers a custom Workflow Builder function (`post_content_submission`) and posts a Block Kit message including the audio file as a playable unfurl. Step 1 (the `Editing Request` form) is unchanged.

## Final architecture

- **Runtime**: Bolt for Python, Socket Mode (no public HTTPS endpoint), launchd `KeepAlive` background agent.
- **Install layout**: deployed copy at `~/Library/Application Support/ContentSubmission/`; tokens at `~/.config/content-submission/.env` (chmod 600); logs at `~/Library/Logs/ContentSubmission/`. Source tree at `~/Documents/GitHub/PhantomLives/ContentSubmission/`.
- **Slack manifest version**: v1 (api.slack.com/apps web UI, NOT the next-gen Deno-based Slack Platform).
- **Function inputs**: 7 — `persona`, `title`, `video_url` (all `string`), `golive_date` (`slack#/types/date`), `audio_file` (`slack#/types/rich_text` — see the dead-end log below for why), `special_requests` (`string`, optional), `channel` (`slack#/types/channel_id`).
- **Tests**: 20 pytest tests, all passing.
- **Manifest validation**: clean against the v1 JSON Schema at github.com/slackapi/manifest-schema.

## What works

1. App is installed in the workspace, function appears in Workflow Builder under "Steps from Apps".
2. Workflow editor accepts the step config when audio_file is bound via the "File ID" sub-property of the form file variable.
3. `function_executed` event reaches the Bolt handler with all 7 inputs in the expected shape.
4. The handler correctly extracts the file ID from the nested rich_text payload.
5. The handler posts the metadata (Persona, Title, Video URL, GoLive Date, Special Requests) to `#content-submission` as a Block Kit message. **Confirmed working in production.**

## What does NOT work, and why

**The audio file cannot be resolved by the bot.** `client.files_info(file=<id>)` returns `{"ok": false, "error": "file_not_found"}`, even with Bolt's per-execution `function_bot_access_token` (which we explicitly force-rebuild the WebClient with — confirmed via log line `function_token=present`).

**Root cause**: form-uploaded files in Slack Workflow Builder are scoped to the form submitter. They are NOT auto-shared with the function-handling bot. No bot token — static `xoxb-` or per-execution function token — can read the file's metadata until the file is shared into a channel the bot is a member of.

**Documented precondition**: from the Roy0815/slack-service-bot manifest description (German): *"Die Datei muss in einem Channel mit dem Bot verfügbar sein, bevor diese Funktion gerufen werden kann"* — *the file must be available in a channel with the bot before this function can be called*.

**The fix (not yet implemented in the workflow)**: add a built-in "Send a message to a channel" step between the form and the custom step. Bind its Files field to the form's audio variable; channel = `#content-submission`. This share-first pattern grants the bot read access via channel membership. Then `files.info` succeeds in the custom step and the audio permalink unfurls.

**Tradeoff**: this produces TWO messages in `#content-submission` per submission — message 1 is the bare audio file from the share step; message 2 is the structured metadata post from the custom step. The original spec asked for one message but Slack's architecture makes that impossible for this combination of (form file upload + custom step posting to the same channel).

## Architecture decision left open

When this is picked back up, the maintainer should decide between three workflow restructurings:

1. **Share to `#content-submission` first** (recommended). Add `Send a message to #content-submission` step bound to the audio variable BEFORE the custom step. Audio appears as message 1; metadata + unfurled audio appears as message 2 in the same channel. Two messages, audio playable both places.
2. **Share to a hidden staging channel.** New private channel where only the bot is a member; the share step posts the file there. The metadata message in `#content-submission` will contain a clickable audio link but it will NOT unfurl as a playable player, because channel members of `#content-submission` don't have file ACL access.
3. **Re-share inside the custom step.** Workflow shares to staging channel; custom step then `chat.postMessage`s with the file as an attachment so it lands in `#content-submission` as part of the metadata block. Cleaner UX (one visible message) but requires code changes — `extract_file_id` + an explicit re-share via the `attachments[].file_id` or `files.completeUploadExternal` API, neither well-documented for this use case.

## Dead-end log (so a future implementer doesn't repeat these)

In rough chronological order of attempts during the original build, with citations:

1. **Tried v2 manifest schema** with `_metadata.major_version: 2`. Failed because the api.slack.com web UI uses v1; v2 is for the next-gen Slack Platform / `slack` CLI / Deno SDK. v2 wraps `input_parameters` in `properties:` + `required:` arrays (JSON Schema style); v1 puts them flat with inline `is_required: true`. Source: [slackapi/manifest-schema](https://github.com/slackapi/manifest-schema) — separate v1 / v2 schema files.

2. **Tried `slack#/types/file_id` for audio_file input**. The v1 schema doesn't enum-check types so it saves clean, but Slack's classic Workflow Builder editor **silently drops the field from the step config dialog** — the field doesn't render. Slack acknowledged this in [bolt-js#2407](https://github.com/slackapi/bolt-js/issues/2407): "the `slack#/types/file_id` is not yet supported in the workflow builder and there is no clear timeline for the support."

3. **Tried `type: string` for audio_file input**. The editor renders the field but mapping the form file variable to a string-typed input shows "Currently unsupported" — Save button silently stays disabled with no per-field error. Same root cause as #2.

4. **The working file-input pattern**: `type: slack#/types/rich_text`. The form file variable is array-of-`slack#/types/file_id` internally; Slack offers a "File ID" sub-property selector on the chip when the destination type is `rich_text`. The runtime payload is a nested rich_text JSON. Reference: [Roy0815/slack-service-bot v3.2.0 manifest](https://github.com/Roy0815/slack-service-bot/blob/main/slack-config-files/manifest.json) and the [matching workflow JSON](https://github.com/Roy0815/slack-service-bot/blob/main/slack-config-files/workflows/Rechnung%20einreichen.json).

5. **Tried `slack#/types/date` for `golive_date`** — this works at both manifest and runtime levels. Was briefly considered as a culprit during debugging but is fine.

6. **Initial install path was inside `~/Documents/GitHub/…`** — the launchd background agent failed with `PermissionError: Operation not permitted: …pyvenv.cfg` because macOS TCC protects `~/Documents/`. Fixed by deploying the venv + script copy to `~/Library/Application Support/ContentSubmission/` and pointing the plist at that location. Source tree at `~/Documents/…` stays as the dev/editing tree; `install.sh` redeploys to the install dir.

7. **Manifest editor JSON vs YAML tab confusion**: pasting YAML into the JSON tab produces `Expecting 'STRING','NUMBER','NULL','TRUE','FALSE','{','[', got: 'INVALID'`. Also pasting from a markdown code block can introduce invisible BOM / zero-width characters that produce the same error on the YAML tab. Workaround in this repo: `manifest.json` is generated from `manifest.yaml`; `cat manifest.json | pbcopy` gives a clean paste.

8. **Manifest required-keys discovered the hard way** (instead of via the slackapi/manifest-schema repo, which would have surfaced them in one read):
   - `settings.function_runtime: remote` is required when `functions:` is declared.
   - `settings.org_deploy_enabled: true` is required when `functions:` is declared (even for non-Grid workspaces).
   - `settings.event_subscriptions.bot_events: [function_executed]` is required when `functions:` is declared.
   None of these are obvious from the api.slack.com/apps UI error messages; each surfaced as a separate "Fix errors to save changes" cycle.

9. **`function_bot_access_token`**: Bolt-Python's `AttachingFunctionToken` middleware auto-swaps `client.token` to the per-execution function token when inside `@app.function` handlers. We initially didn't request `context` in the handler signature; adding `context` and force-rebuilding the WebClient with the function token did NOT fix file access on its own — see "What does NOT work" above. Source: [Bolt-Python BaseContext docs](https://docs.slack.dev/tools/bolt-python/reference/context/base_context.html).

## How to clean up Slack-side (delete the app)

If you want to fully reset the Slack workspace state before a future restart:

1. Open https://api.slack.com/apps and pick **Content Submission**.
2. In Workflow Builder (your workspace → Tools → Workflow Builder → Content Submission workflow → Edit), **delete the "Post Content Submission" step** from the workflow. The workflow will need either the original "Send a message to a channel" step re-added (with the known audio-file-ID rendering bug) or the workflow can be left unpublished.
3. Publish or unpublish the workflow as appropriate.
4. In `#content-submission`, kick the bot if you want: open channel → channel name → Members → ⋯ next to Content Submission → Remove from channel.
5. Back at api.slack.com/apps → Content Submission → scroll to the bottom of **Basic Information** → **Delete App** → confirm. This revokes both tokens automatically.

If instead you want to **resume** later: leave the app in place. The local install was removed; running `./install.sh` from the source tree will rebuild the venv, re-prompt for the existing tokens, and redeploy.

## Repo layout (preserved)

```
ContentSubmission/
├── README.md, USER_MANUAL.md, CHANGELOG.md
├── HANDOFF.md                       (this file)
├── content_submission.py            (Bolt handler — works end-to-end except files.info)
├── test_content_submission.py       (20 tests, all passing)
├── manifest.yaml                    (canonical v1 manifest)
├── manifest.json                    (JSON snapshot for paste into Slack)
├── install.sh, uninstall.sh, run.sh
├── com.phantomlives.contentsubmission.plist
├── requirements.txt
├── config/.env.example
└── .gitignore
```

## To restart later

1. `cd ~/Documents/GitHub/PhantomLives/ContentSubmission`
2. Decide which of the three architecture options above to take.
3. If continuing with the current Slack app: `./install.sh` (will prompt for tokens; reuse the ones from your last session at api.slack.com/apps).
4. If deleted the Slack app: re-create from `manifest.yaml` (or `manifest.json`) at api.slack.com/apps → Create New App → From a manifest.
5. Add the workflow share step before the custom step in Workflow Builder.
6. Test by submitting the form with a real audio file.

## Key citations

- Bolt-JS issue confirming `file_id` is unsupported in Workflow Builder: https://github.com/slackapi/bolt-js/issues/2407
- Deno-SDK feature request (still open) for file inputs: https://github.com/slackapi/deno-slack-sdk/issues/338
- Working repo with the share-first + rich_text pattern: https://github.com/Roy0815/slack-service-bot
- Slack manifest JSON schema: https://github.com/slackapi/manifest-schema
- Bolt-Python function context (function_bot_access_token): https://docs.slack.dev/tools/bolt-python/reference/context/base_context.html
- Slack Steps from Apps tutorial: https://docs.slack.dev/tools/bolt-js/tutorials/custom-steps-workflow-builder-new/
