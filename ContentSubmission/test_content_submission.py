"""Tests for ContentSubmission block builder and permalink resolver."""
from __future__ import annotations

import json
import logging
from unittest.mock import MagicMock

import pytest

from content_submission import (
    build_blocks,
    build_fallback_text,
    extract_file_id,
    resolve_audio_permalink,
)


def _fixture_inputs(**overrides):
    base = {
        "persona": "Princess Of Addiction (PoA)",
        "title": "Big Tits Big Ideas",
        "video_url": "https://sheer-enterprise.slack.com/archives/C0B4WRH66SU/p1778860504112339",
        "golive_date": "2026-05-16",
        "special_requests": "This has an audio file inserted",
        "audio_file": "F0B42E4L8KV",
        "channel": "C0CONTENTSUB",
    }
    base.update(overrides)
    return base


def test_build_blocks_full_submission_includes_all_fields():
    inputs = _fixture_inputs()
    permalink = "https://sheer-enterprise.slack.com/files/U123/F0B42E4L8KV/audio.m4a"
    blocks = build_blocks(inputs, permalink)
    payload = json.dumps(blocks)
    assert "Big Tits Big Ideas" in payload
    assert "Princess Of Addiction" in payload
    assert "2026-05-16" in payload
    assert permalink in payload
    assert "This has an audio file inserted" in payload
    assert "warning" not in payload.lower()


def test_build_blocks_omits_special_requests_when_blank():
    inputs = _fixture_inputs(special_requests="")
    blocks = build_blocks(inputs, "https://example.com/file")
    payload = json.dumps(blocks)
    assert "Special Requests" not in payload


def test_build_blocks_strips_whitespace_only_special_requests():
    inputs = _fixture_inputs(special_requests="   \n\t  ")
    blocks = build_blocks(inputs, "https://example.com/file")
    payload = json.dumps(blocks)
    assert "Special Requests" not in payload


def test_build_blocks_warns_when_audio_permalink_unavailable():
    inputs = _fixture_inputs()
    blocks = build_blocks(inputs, None)
    payload = json.dumps(blocks)
    assert "Audio file could not be resolved" in payload
    assert ":warning:" in payload


def test_build_blocks_falls_back_when_video_url_missing():
    inputs = _fixture_inputs(video_url="")
    blocks = build_blocks(inputs, "https://example.com/file")
    payload = json.dumps(blocks)
    assert "_(none)_" in payload


def test_build_blocks_placeholder_dash_for_missing_persona_and_date():
    inputs = _fixture_inputs(persona="", golive_date="")
    blocks = build_blocks(inputs, "https://example.com/file")
    field_texts = [f["text"] for f in blocks[2]["fields"]]
    assert "*Persona*\n—" in field_texts
    assert "*GoLive Date*\n—" in field_texts


def test_build_fallback_text_contains_title_and_permalink():
    inputs = _fixture_inputs()
    permalink = "https://example.com/file/X"
    text = build_fallback_text(inputs, permalink)
    assert "Big Tits Big Ideas" in text
    assert permalink in text


def test_build_fallback_text_omits_permalink_when_none():
    inputs = _fixture_inputs()
    text = build_fallback_text(inputs, None)
    assert "https://" not in text
    assert "Big Tits Big Ideas" in text


def test_resolve_audio_permalink_returns_permalink_on_success():
    client = MagicMock()
    client.files_info.return_value = {
        "file": {"permalink": "https://example.com/file/F0B42E4L8KV"}
    }
    logger = logging.getLogger("test")
    result = resolve_audio_permalink(client, "F0B42E4L8KV", logger)
    assert result == "https://example.com/file/F0B42E4L8KV"
    client.files_info.assert_called_once_with(file="F0B42E4L8KV")


def test_resolve_audio_permalink_returns_none_on_error():
    client = MagicMock()
    client.files_info.side_effect = RuntimeError("nope")
    logger = logging.getLogger("test")
    result = resolve_audio_permalink(client, "F0B42E4L8KV", logger)
    assert result is None


def test_resolve_audio_permalink_returns_none_for_empty_id():
    client = MagicMock()
    logger = logging.getLogger("test")
    result = resolve_audio_permalink(client, "", logger)
    assert result is None
    client.files_info.assert_not_called()


def test_resolve_audio_permalink_returns_none_when_response_missing_permalink():
    client = MagicMock()
    client.files_info.return_value = {"file": {}}
    logger = logging.getLogger("test")
    result = resolve_audio_permalink(client, "F0B42E4L8KV", logger)
    assert result is None


def test_extract_file_id_from_string():
    assert extract_file_id("F0B42E4L8KV") == "F0B42E4L8KV"


def test_extract_file_id_from_dict_with_id():
    assert extract_file_id({"id": "F0B42E4L8KV", "name": "audio.m4a"}) == "F0B42E4L8KV"


def test_extract_file_id_from_dict_with_file_id_alias():
    assert extract_file_id({"file_id": "F0B42E4L8KV"}) == "F0B42E4L8KV"


def test_extract_file_id_handles_none_and_empty():
    assert extract_file_id(None) == ""
    assert extract_file_id("") == ""
    assert extract_file_id({}) == ""
    assert extract_file_id([]) == ""


def test_extract_file_id_from_rich_text_payload():
    payload = [
        {
            "type": "rich_text_section",
            "elements": [
                {
                    "type": "rich_text",
                    "elements": [
                        {"type": "text", "text": "F0B42E4L8KV"},
                    ],
                }
            ],
        }
    ]
    assert extract_file_id(payload) == "F0B42E4L8KV"


def test_extract_file_id_from_shallow_rich_text():
    payload = [{"type": "text", "text": "F0B42E4L8KV"}]
    assert extract_file_id(payload) == "F0B42E4L8KV"


def test_extract_file_id_skips_non_text_leaves_in_rich_text():
    payload = [
        {
            "type": "rich_text_section",
            "elements": [
                {"type": "broadcast", "range": "channel"},
                {"type": "text", "text": "F0B42E4L8KV"},
            ],
        }
    ]
    assert extract_file_id(payload) == "F0B42E4L8KV"


def test_resolve_audio_permalink_accepts_dict_file_input():
    client = MagicMock()
    client.files_info.return_value = {"file": {"permalink": "https://example.com/X"}}
    logger = logging.getLogger("test")
    result = resolve_audio_permalink(client, {"id": "F0B42E4L8KV"}, logger)
    assert result == "https://example.com/X"
    client.files_info.assert_called_once_with(file="F0B42E4L8KV")
