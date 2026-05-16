#!/usr/bin/env python3
"""ContentSubmission — Slack custom workflow step for content submissions.

Replaces Step 2 of the legacy Workflow Builder workflow so the uploaded audio
file is posted to the channel as a playable file rather than a raw file ID.

Runtime: Bolt for Python + Socket Mode. No public HTTPS endpoint required.
"""
from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler
from slack_sdk import WebClient

__version__ = "1.0.0"

FUNCTION_CALLBACK_ID = "post_content_submission"
DEFAULT_CHANNEL = "#content-submission"


def load_environment() -> Path | None:
    """Load Slack tokens from the first .env file found.

    Search order matches the install.sh layout:
      1. ~/.config/content-submission/.env   (canonical, chmod 600)
      2. <project>/config/.env               (dev/local override)
      3. <project>/.env                      (fallback)
    """
    candidates = [
        Path.home() / ".config" / "content-submission" / ".env",
        Path(__file__).resolve().parent / "config" / ".env",
        Path(__file__).resolve().parent / ".env",
    ]
    for path in candidates:
        if path.is_file():
            load_dotenv(path)
            logging.info("loaded env from %s", path)
            return path
    return None


def extract_file_id(audio_file_input: Any) -> str:
    """Pull a Slack file ID out of whatever shape Workflow Builder hands us.

    `slack#/types/file_id` is documented but currently broken in classic
    Workflow Builder (slackapi/bolt-js#2407). The documented workaround is to
    type the input as `slack#/types/rich_text` and have the workflow author
    bind the form file variable's "File ID" sub-property. At runtime that
    arrives as a nested rich_text payload:

        [{"type": "rich_text_section",
          "elements": [{"type": "rich_text",
                        "elements": [{"type": "text", "text": "F0123ABCD"}]}]}]

    We unwrap to the first text leaf, regardless of how deeply nested. Also
    tolerate the simpler shapes (bare string, dict with `id`) in case Slack
    fixes file_id support in the future or sends a different payload.

    Reference: github.com/Roy0815/slack-service-bot/blob/v3.2.0/helper/rechnungen/app.js
    """
    if not audio_file_input:
        return ""
    if isinstance(audio_file_input, str):
        return audio_file_input
    if isinstance(audio_file_input, dict):
        return audio_file_input.get("id") or audio_file_input.get("file_id") or ""
    if isinstance(audio_file_input, list):
        for item in audio_file_input:
            text = _first_text_in_rich_text(item)
            if text:
                return text
    return ""


def _first_text_in_rich_text(node: Any) -> str:
    """Depth-first walk of a rich_text payload, returning the first text leaf."""
    if isinstance(node, dict):
        if node.get("type") == "text" and isinstance(node.get("text"), str):
            return node["text"]
        for child in node.get("elements", []) or []:
            text = _first_text_in_rich_text(child)
            if text:
                return text
    elif isinstance(node, list):
        for child in node:
            text = _first_text_in_rich_text(child)
            if text:
                return text
    return ""


def resolve_audio_permalink(client, audio_file_input: Any, logger) -> str | None:
    """Look up a Slack file's permalink so it unfurls into a playable preview.

    The audio file's permalink is what Slack uses to render an inline audio
    player. Raw file IDs render as plain text — that's the bug this app fixes.
    """
    file_id = extract_file_id(audio_file_input)
    if not file_id:
        return None
    try:
        resp = client.files_info(file=file_id)
        return resp.get("file", {}).get("permalink")
    except Exception:
        logger.exception("files_info failed for file_id=%s", file_id)
        return None


def build_blocks(inputs: dict[str, Any], audio_permalink: str | None) -> list[dict[str, Any]]:
    """Render the channel post as Block Kit blocks."""
    persona = (inputs.get("persona") or "").strip() or "—"
    title = (inputs.get("title") or "").strip() or "—"
    video_url = (inputs.get("video_url") or "").strip()
    golive_date = (inputs.get("golive_date") or "").strip() or "—"
    special_requests = (inputs.get("special_requests") or "").strip()

    blocks: list[dict[str, Any]] = [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f":incoming_envelope:  *New Content Submission*\n*{title}* — _{persona}_",
            },
        },
        {"type": "divider"},
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Persona*\n{persona}"},
                {"type": "mrkdwn", "text": f"*Title*\n{title}"},
                {"type": "mrkdwn", "text": f"*GoLive Date*\n{golive_date}"},
            ],
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Video*\n{video_url}" if video_url else "*Video*\n_(none)_",
            },
        },
    ]

    if audio_permalink:
        blocks.append({
            "type": "section",
            "text": {"type": "mrkdwn", "text": f"*Description (audio)*\n{audio_permalink}"},
        })
    else:
        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": ":warning: *Description (audio)*\n_Audio file could not be resolved._",
            },
        })

    if special_requests:
        blocks.append({
            "type": "section",
            "text": {"type": "mrkdwn", "text": f"*Special Requests*\n{special_requests}"},
        })

    return blocks


def build_fallback_text(inputs: dict[str, Any], audio_permalink: str | None) -> str:
    """Plain-text fallback used for notifications and to trigger URL unfurls."""
    title = (inputs.get("title") or "").strip() or "(untitled)"
    parts = [f"New Content Submission: {title}"]
    if audio_permalink:
        parts.append(audio_permalink)
    return "\n".join(parts)


def register_handlers(app: App) -> None:
    @app.function(FUNCTION_CALLBACK_ID)
    def handle_function(ack, inputs, fail, complete, client, context, logger):
        ack()
        # Workflow-form-uploaded files are NOT visible to the static xoxb- bot
        # token. Slack mints a per-execution `function_bot_access_token` that
        # has scoped access to those files. Bolt's AttachingFunctionToken
        # middleware should swap `client.token` to it automatically, but we
        # force the rebuild here to guarantee it regardless of middleware order
        # or future SDK changes. Cost is one extra WebClient init per event.
        function_token = getattr(context, "function_bot_access_token", None)
        logger.info("function_executed inputs=%s function_token=%s",
                    inputs, "present" if function_token else "missing")
        if function_token:
            client = WebClient(token=function_token)

        channel = (inputs.get("channel") or "").strip() or DEFAULT_CHANNEL
        audio_permalink = resolve_audio_permalink(client, inputs.get("audio_file"), logger)
        blocks = build_blocks(inputs, audio_permalink)
        fallback_text = build_fallback_text(inputs, audio_permalink)

        try:
            result = client.chat_postMessage(
                channel=channel,
                text=fallback_text,
                blocks=blocks,
                unfurl_links=True,
                unfurl_media=True,
            )
            complete(outputs={"message_ts": result["ts"]})
        except Exception as exc:
            logger.exception("chat_postMessage failed")
            fail(error=f"Failed to post message: {exc}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="ContentSubmission Slack app")
    parser.add_argument("--version", action="version",
                        version=f"ContentSubmission {__version__}")
    parser.add_argument("--log-level", default="INFO",
                        help="DEBUG, INFO, WARNING, ERROR")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    load_environment()

    bot_token = os.environ.get("SLACK_BOT_TOKEN")
    app_token = os.environ.get("SLACK_APP_TOKEN")
    if not bot_token or not app_token:
        logging.error(
            "missing SLACK_BOT_TOKEN and/or SLACK_APP_TOKEN — "
            "set them in ~/.config/content-submission/.env"
        )
        return 2

    app = App(token=bot_token)
    register_handlers(app)
    handler = SocketModeHandler(app, app_token)
    logging.info("ContentSubmission %s starting in Socket Mode", __version__)
    handler.start()
    return 0


if __name__ == "__main__":
    sys.exit(main())
