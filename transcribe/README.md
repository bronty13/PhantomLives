# transcribe

Local video/audio transcription for Apple Silicon using Metal-accelerated Whisper on Apple MLX.

All processing happens on your machine — no data leaves your device.

## Requirements

- macOS on Apple Silicon (M1/M2/M3/M4/M5)
- Python 3.10+
- Homebrew (for ffmpeg auto-install)

## Installation

No manual installation needed. On first run, the script automatically:

1. Installs ffmpeg via Homebrew (if not already installed)
2. Creates a `.venv` virtual environment in the `transcribe/` directory
3. Installs all Python dependencies (mlx, mlx-whisper, mlx-lm, truststore)
4. Re-launches itself inside the venv

Just run it:

```bash
python3 transcribe.py -i your_video.mp4
```

Whisper and LLM models are downloaded from HuggingFace on first use of each model size.

To force a clean reinstall of dependencies, delete the `.venv/` directory and re-run.

## Quick Start

```bash
# Basic transcription — writes to ~/Downloads/transcribe/meeting.txt
python transcribe.py -i meeting.mp4

# Pipe to stdout instead (for grep / other tools)
python transcribe.py -i meeting.mp4 -o -

# Save as SRT subtitles to a specific path
python transcribe.py -i meeting.mp4 -o meeting.srt -f srt

# Use a smaller model for speed (still goes to ~/Downloads/transcribe/)
python transcribe.py -i meeting.mp4 -m small

# Transcribe and summarize
python transcribe.py -i lecture.mp4 --summarize -v

# Custom summarization prompt
python transcribe.py -i call.mp4 --summarize --prompt "List all action items and decisions"

# Read prompt from a file
python transcribe.py -i call.mp4 --summarize --prompt-file my_prompt.txt

# Translate non-English audio to English
python transcribe.py -i foreign_video.mp4 --task translate

# Specify language for better accuracy
python transcribe.py -i japanese_talk.mp4 -l ja

# Direct audio file input
python transcribe.py -i podcast.mp3 -o notes.txt
```

## Model Selection Guide

| Model  | Parameters | RAM    | Speed   | Quality | Notes                           |
|--------|-----------|--------|---------|---------|----------------------------------|
| tiny   | 39M       | ~1 GB  | Fastest | Low     | Quick drafts, testing            |
| base   | 74M       | ~1 GB  | Fast    | Fair    | Acceptable for clear speech      |
| small  | 244M      | ~2 GB  | Good    | Good    | Balanced speed and quality       |
| medium | 769M      | ~5 GB  | Moderate| High    | High quality transcription       |
| large  | 1550M     | ~10 GB | Slow    | Best    | Maximum accuracy                 |
| **turbo** | 809M   | ~6 GB  | Fast    | High    | **Default** — near-large quality, 8x faster |

**Recommendations:**
- **16 GB RAM**: turbo (default), medium, small, base, tiny
- **32 GB RAM**: Any model including large; turbo remains the best default
- **64 GB RAM**: Any model; large for maximum transcription quality
- **128+ GB RAM**: large Whisper + full-precision or 8-bit LLMs for summarization (e.g. `mlx-community/Mistral-7B-Instruct-v0.3-8bit` or larger 70B+ models)

## Output Formats

| Format | Flag      | Description                        |
|--------|-----------|------------------------------------|
| txt    | `-f txt`  | Plain text (default)               |
| srt    | `-f srt`  | SubRip subtitles with timestamps   |
| vtt    | `-f vtt`  | WebVTT subtitles with timestamps   |
| json   | `-f json` | Full Whisper result with metadata  |

## Summarization

Add `--summarize` to run the transcript through a local LLM after transcription.

### LLM Model Presets

Use `--llm-model` with a preset name or any HuggingFace MLX model repo.

| Preset                | Parameters | RAM    | Notes                              |
|-----------------------|-----------|--------|------------------------------------|
| `mistral-7b-4bit`    | 7B        | ~4 GB  | **Default** — fast, good summaries |
| `mistral-7b-8bit`    | 7B        | ~8 GB  | Higher precision 7B                |
| `llama-3.1-8b-4bit`  | 8B        | ~5 GB  | Good quality/speed balance         |
| `llama-3.1-8b-8bit`  | 8B        | ~9 GB  | Higher precision 8B                |
| `llama-3.1-70b-4bit` | 70B       | ~40 GB | Best quality, needs 64+ GB RAM    |
| `llama-3.1-70b-8bit` | 70B       | ~75 GB | Maximum quality, needs 128 GB RAM |

```bash
# Default summarization (key points, decisions, action items)
python transcribe.py -i meeting.mp4 --summarize

# Custom prompt
python transcribe.py -i interview.mp4 --summarize --prompt "Extract all questions asked and answers given"

# Use Llama 3.1 8B
python transcribe.py -i lecture.mp4 --summarize --llm-model llama-3.1-8b-4bit

# Use Llama 3.1 70B for best quality (needs 64+ GB RAM)
python transcribe.py -i lecture.mp4 -m large --summarize --llm-model llama-3.1-70b-4bit

# Full quality pipeline on 128 GB machine
python transcribe.py -i lecture.mp4 -m large --summarize --llm-model llama-3.1-70b-8bit

# Use any HuggingFace MLX model directly
python transcribe.py -i call.mp4 --summarize --llm-model mlx-community/some-custom-model

# Control output length
python transcribe.py -i call.mp4 --summarize --max-tokens 2048
```

When writing to a file (the default, or any explicit `-o`), the summary is saved as `<name>.summary.txt` alongside the transcript. With `-o -` (stdout mode), the summary prints after the transcript instead.

Default LLM: `mistral-7b-4bit` (Mistral 7B Instruct, ~4 GB RAM)

## Full Usage

```
usage: transcribe [-h] [-V] -i INPUT [-o OUTPUT] [-f {txt,srt,vtt,json}]
                  [-m {tiny,base,small,medium,large,turbo}]
                  [-l LANGUAGE] [--task {transcribe,translate}]
                  [--word-timestamps]
                  [--summarize] [--llm-model LLM_MODEL]
                  [--prompt PROMPT] [--prompt-file PROMPT_FILE]
                  [--max-tokens MAX_TOKENS]
                  [-v | -q]

options:
  -h, --help            show help message and exit
  -V, --version         show version and exit
  -i, --input INPUT     input video or audio file
  -o, --output OUTPUT   output file (default: ~/Downloads/transcribe/<input>.<fmt>; pass `-` for stdout)
  -f, --format FORMAT   output format: txt, srt, vtt, json (default: txt)

whisper options:
  -m, --model MODEL     whisper model size (default: turbo)
  -l, --language LANG   language code, e.g. en, es, ja (default: auto-detect)
  --task TASK           transcribe or translate to English (default: transcribe)
  --word-timestamps     enable word-level timestamps

summarization options:
  --summarize           summarize transcript with a local LLM
  --llm-model MODEL     HuggingFace model repo for LLM
  --prompt PROMPT       custom system prompt for summarization
  --prompt-file FILE    read summarization prompt from a file
  --max-tokens N        max tokens for LLM output (default: 1024)

output:
  -v, --verbose         show progress and debug info
  -q, --quiet           suppress all non-essential output
```

## Exit Codes

| Code | Meaning              |
|------|----------------------|
| 0    | Success              |
| 1    | Input/argument error |
| 2    | Missing dependency   |
| 3    | ffmpeg failure       |
| 4    | Transcription error  |
