# ContentSubmission

> **STATUS: PAUSED.** Code builds and tests pass, but the end-to-end workflow is blocked on a Slack file-ACL limitation (form-uploaded files aren't visible to the bot until shared into a channel). The local install was removed on 2026-05-16. See [HANDOFF.md](HANDOFF.md) before continuing — it documents what works, what doesn't, the dead ends to avoid, and the three architectural options for resolving the file-access problem.


A small Slack app that registers a **custom Workflow Builder step** named
**Post Content Submission**. It replaces Step 2 of the existing _Content
Submission_ workflow in the `sheer-enterprise` workspace so that the
form-uploaded audio file is posted to `#content-submission` as a clickable,
playable file rather than a raw `F0…` ID.

Step 1 of the workflow — the form titled _Editing Request_ — is unchanged.

## What it does

Given the six form fields (Persona, Title, Slack URL, GoLive Date, Description
Audio File, Special Requests) plus a destination channel, the step:

1. Calls `files.info` on the audio file to get its permalink.
2. Posts a Block Kit message to the channel with all fields rendered.
3. Includes the audio permalink in the post so Slack unfurls it as an inline
   playable audio player.
4. Falls back to a `:warning:` note (and still posts the submission) if the
   audio file can't be resolved — the submitter's work isn't lost.

## Architecture

- **Bolt for Python + Socket Mode.** No public HTTPS endpoint required.
- Connects to Slack as a Socket Mode client; receives `function_executed`
  events for the `post_content_submission` step.
- Runs on your Mac under `launchd` as a `KeepAlive` background job.
- Tokens live at `~/.config/content-submission/.env` (chmod 600), never in
  the repo.

```
Workflow Builder
   ↓ form (Step 1, unchanged)
   ↓ custom step "Post Content Submission" (Step 2, this app)
       ↓ function_executed event over Socket Mode
       ↓ files.info(audio_file)
       ↓ chat.postMessage(channel, blocks)
   #content-submission
```

## One-time Slack setup

1. **Create the app from manifest.**
   Go to https://api.slack.com/apps → **Create New App** → **From a manifest**
   → pick the `sheer-enterprise` workspace → paste the contents of
   [`manifest.yaml`](manifest.yaml) → **Create**.

2. **Get the bot token.**
   In the app's left nav: **OAuth & Permissions** → **Install to Workspace** →
   approve. Copy the **Bot User OAuth Token** (starts `xoxb-`).

3. **Get the app-level token.**
   **Basic Information** → **App-Level Tokens** → **Generate Token and Scopes**
   → add scope `connections:write` → **Generate**. Copy the token (starts
   `xapp-`).

4. **Invite the bot to the channel.**
   In Slack:
   ```
   /invite @Content Submission
   ```
   from within `#content-submission`.

## Install on your Mac

```sh
cd ContentSubmission
./install.sh
```

`install.sh` will:

- create `./.venv` and `pip install -r requirements.txt`
- prompt for the two Slack tokens and write them to
  `~/.config/content-submission/.env` (chmod 600)
- render `com.phantomlives.contentsubmission.plist` with absolute paths and
  copy it to `~/Library/LaunchAgents/`
- `launchctl bootstrap` the job (RunAtLoad + KeepAlive)

After install, the listener is running in the background and survives reboots.

### Logs

```
~/Library/Logs/ContentSubmission/contentsubmission.out.log
~/Library/Logs/ContentSubmission/contentsubmission.err.log
```

### Useful launchctl commands

```sh
# stop the job
launchctl bootout gui/$(id -u)/com.phantomlives.contentsubmission

# restart it
launchctl kickstart -k gui/$(id -u)/com.phantomlives.contentsubmission

# show state + PID
launchctl print gui/$(id -u)/com.phantomlives.contentsubmission
```

## Wire it into the workflow

1. Open Workflow Builder → **Content Submission** workflow → **Edit**.
2. Delete the current **Send a message to a channel** step.
3. **Add Step** → under **Steps from apps**, pick **Content Submission →
   Post Content Submission**.
4. Map the function inputs to the form variables:
   | Input | Map to (form variable) |
   |---|---|
   | Persona | What persona is this for? |
   | Title | Title |
   | Video URL | Slack URL |
   | GoLive Date | GoLive Date |
   | Audio File | Description Audio File |
   | Special Requests | Special Requests |
   | Destination channel | `#content-submission` |
5. **Save** → **Publish Changes**.

## Develop / iterate

Stop the launchd job and use `run.sh` for foreground DEBUG logging:

```sh
launchctl bootout gui/$(id -u)/com.phantomlives.contentsubmission
./run.sh
```

When you're done, `./install.sh` again to put the launchd job back.

## Tests

```sh
./.venv/bin/pytest test_content_submission.py -v
```

Twelve tests covering:

- block builder happy path
- optional fields omitted when blank or whitespace-only
- missing-audio `:warning:` fallback
- missing-video URL placeholder
- placeholder-dash rendering for missing persona / date
- fallback-text generation (with and without permalink)
- `files.info` permalink resolver: success, error, empty ID, missing field

## Uninstall

```sh
./uninstall.sh           # stops the launchd job, keeps the venv
./uninstall.sh --purge   # also removes the venv
```

Tokens at `~/.config/content-submission/.env` are kept by default so a
re-install is one command. Delete that file manually for a clean slate.

## Files in this subproject

| File | Purpose |
|---|---|
| `content_submission.py` | Bolt app, function handler, block builder |
| `test_content_submission.py` | pytest suite |
| `manifest.yaml` | Slack app manifest (paste at api.slack.com/apps) |
| `requirements.txt` | Python deps (slack_bolt, slack_sdk, python-dotenv, pytest) |
| `install.sh` | venv + tokens + launchd job |
| `uninstall.sh` | tear down the launchd job |
| `run.sh` | foreground debug run |
| `com.phantomlives.contentsubmission.plist` | launchd plist template |
| `config/.env.example` | env file template (real .env lives in ~/.config) |
| `CHANGELOG.md` | release notes |
| `USER_MANUAL.md` | day-to-day operator guide |

## PhantomLives conventions notes

- **Default output location:** N/A — this app's output is the Slack channel
  post, not a local file. No `~/Downloads/content-submission/` directory.
- **Auto-backup-on-launch:** N/A — the app holds no persistent user data.
  Tokens at `~/.config/content-submission/.env` are easily regenerated from
  Slack and aren't worth a backup loop.
- **`.app` bundle / install.sh standard:** doesn't apply (this is a daemon,
  not a `.app`). The `install.sh` here is the Python/launchd variant used by
  `messages-exporter` and friends.
