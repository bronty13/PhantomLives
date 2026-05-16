# ContentSubmission — User Manual

This is the day-to-day operator guide. For one-time install instructions see
[`README.md`](README.md).

## What you'll see in Slack

When someone runs the **Content Submission** workflow, fills in the form, and
clicks Submit, the **Content Submission** bot posts a message to
`#content-submission` that looks like this:

```
📨  New Content Submission
Big Tits Big Ideas — Princess Of Addiction (PoA)
────────────────────────
Persona              Title                GoLive Date
Princess Of …(PoA)   Big Tits Big Ideas   2026-05-16

Video
https://sheer-enterprise.slack.com/archives/C0B…/p1778…

Description (audio)
https://sheer-enterprise.slack.com/files/U…/F0B42E4L8KV/audio.m4a
   [ ▶ playable audio player ]

Special Requests
This has an audio file inserted
```

The audio permalink is what triggers Slack to render the inline player. The
URL itself is clickable; the player appears below the message as an unfurl.

If you see a `⚠ Audio file could not be resolved.` line instead, the rest of
the submission posted fine but the bot couldn't reach `files.info` for the
upload. Most common cause: the bot wasn't invited to a channel it can see the
upload in. Re-`/invite @Content Submission` and re-run the workflow.

## Day-to-day commands

### Is it running?

```sh
launchctl print gui/$(id -u)/com.phantomlives.contentsubmission | head
```

Look for `state = running` and a PID. If the line says `state = not loaded`,
run `./install.sh` again.

### Tail the logs

```sh
tail -f ~/Library/Logs/ContentSubmission/contentsubmission.{out,err}.log
```

The `.out.log` shows the structured logger output (one line per event). The
`.err.log` captures any Python exceptions.

### Restart after editing code

```sh
launchctl kickstart -k gui/$(id -u)/com.phantomlives.contentsubmission
```

`-k` kills and restarts in one shot.

### Stop entirely

```sh
launchctl bootout gui/$(id -u)/com.phantomlives.contentsubmission
```

### Rotate tokens

If you regenerate either Slack token, edit
`~/.config/content-submission/.env` and then:

```sh
launchctl kickstart -k gui/$(id -u)/com.phantomlives.contentsubmission
```

## Troubleshooting

### "App is not appearing in Workflow Builder under 'Steps from apps'"

- Confirm the app is installed to the workspace (api.slack.com/apps → your
  app → Install App).
- Confirm `manifest.yaml` was saved with the `functions:` block — the
  `post_content_submission` function is what makes the step show up.
- In Slack, open Workflow Builder → Edit → Add Step → search for "Post
  Content Submission". If you don't see it, try a hard refresh in the Slack
  desktop app (Cmd-R inside a workspace).

### "The bot posts the message but no audio player appears below"

- Slack only unfurls links the bot can see. Confirm the bot was added to
  `#content-submission` *and* to any channel the audio file was uploaded
  into. The form uploads typically attach to the workflow runner's DM scope —
  the `files:read` scope plus `chat:write.public` covers most cases, but
  channel membership on the destination is mandatory.

### "Failed to post message: not_in_channel"

The bot isn't a member of the destination channel.

```
/invite @Content Submission
```

in the channel.

### "Logs show `missing SLACK_BOT_TOKEN and/or SLACK_APP_TOKEN`"

The `.env` at `~/.config/content-submission/.env` is missing or unreadable.
Re-run `./install.sh` — it'll prompt for tokens and rewrite the file with
the correct permissions.

### "I want to test without running the real workflow"

Easiest path: in the Slack app's Workflow Builder, duplicate the Content
Submission workflow, point its custom-step destination at a test channel, and
trigger it yourself. There's no useful way to invoke a Slack workflow
function from outside Slack.

You can run the test suite locally without touching Slack:

```sh
./.venv/bin/pytest test_content_submission.py -v
```

## Where things live

| Thing | Path |
|---|---|
| App code | this directory |
| Python venv | `./.venv/` |
| Tokens | `~/.config/content-submission/.env` (chmod 600) |
| launchd plist | `~/Library/LaunchAgents/com.phantomlives.contentsubmission.plist` |
| Logs | `~/Library/Logs/ContentSubmission/` |
