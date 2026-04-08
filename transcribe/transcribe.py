#!/usr/bin/env python3
"""
transcribe — Local video/audio transcription for Apple Silicon.

Metal-accelerated speech-to-text using Whisper on Apple MLX.
All processing is local — no data leaves your machine.
"""

__version__ = "1.3.0"

import os
import subprocess
import sys

# ---------------------------------------------------------------------------
# Virtual environment bootstrap
# ---------------------------------------------------------------------------
# When run outside the venv, create it, install deps, and re-exec.

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VENV_DIR = os.path.join(SCRIPT_DIR, ".venv")
VENV_PYTHON = os.path.join(VENV_DIR, "bin", "python")

REQUIRED_PACKAGES = [
    "mlx>=0.16.0",
    "mlx-whisper>=0.4.0",
    "mlx-lm>=0.19.0",
    "truststore>=0.10.0",
]


def _in_venv() -> bool:
    """Return True if we are running inside our .venv."""
    return os.path.abspath(sys.prefix) == os.path.abspath(VENV_DIR)


def _bootstrap_venv() -> None:
    """Create the venv, install packages, and re-exec this script."""
    import venv

    if not os.path.isdir(VENV_DIR):
        print("Creating virtual environment ...", file=sys.stderr)
        venv.create(VENV_DIR, with_pip=True)

    # Check if ffmpeg is available
    import shutil
    if not shutil.which("ffmpeg"):
        print("ffmpeg not found — installing via Homebrew ...", file=sys.stderr)
        subprocess.run(["brew", "install", "ffmpeg"], check=True)

    # Install / update packages
    print("Installing dependencies (first run may take a few minutes) ...", file=sys.stderr)
    subprocess.run(
        [VENV_PYTHON, "-m", "pip", "install", "--quiet"] + REQUIRED_PACKAGES,
        check=True,
    )

    # Re-exec this script under the venv Python, preserving all arguments
    os.execv(VENV_PYTHON, [VENV_PYTHON] + sys.argv)


if not _in_venv():
    _bootstrap_venv()
    # execv replaces the process; this line is never reached

# ---------------------------------------------------------------------------
# Imports (only reached inside the venv)
# ---------------------------------------------------------------------------

import argparse
import json
import platform
import shutil
import tempfile

# Use macOS Keychain for SSL certificates (avoids issues with corporate proxies
# and Python 3.14+ stricter certificate validation).
try:
    import truststore
    truststore.inject_into_ssl()
except ImportError:
    pass

# ---------------------------------------------------------------------------
# Model registry
# ---------------------------------------------------------------------------

MODEL_REGISTRY = {
    "tiny": {
        "repo": "mlx-community/whisper-tiny",
        "params": "39M",
        "ram": "~1 GB",
        "note": "Fastest, lowest quality",
    },
    "base": {
        "repo": "mlx-community/whisper-base",
        "params": "74M",
        "ram": "~1 GB",
        "note": "Fast, acceptable quality",
    },
    "small": {
        "repo": "mlx-community/whisper-small",
        "params": "244M",
        "ram": "~2 GB",
        "note": "Good balance of speed and quality",
    },
    "medium": {
        "repo": "mlx-community/whisper-medium-mlx",
        "params": "769M",
        "ram": "~5 GB",
        "note": "High quality, moderate speed",
    },
    "large": {
        "repo": "mlx-community/whisper-large-v3-mlx",
        "params": "1550M",
        "ram": "~10 GB",
        "note": "Best quality, slowest",
    },
    "turbo": {
        "repo": "mlx-community/whisper-large-v3-turbo",
        "params": "809M",
        "ram": "~6 GB",
        "note": "Near-large quality, 8x faster",
    },
}

LLM_REGISTRY = {
    "mistral-7b-4bit": {
        "repo": "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
        "params": "7B",
        "ram": "~4 GB",
        "note": "Default — fast, good for basic summaries",
    },
    "mistral-7b-8bit": {
        "repo": "mlx-community/Mistral-7B-Instruct-v0.3-8bit",
        "params": "7B",
        "ram": "~8 GB",
        "note": "Higher precision 7B",
    },
    "llama-3.1-8b-4bit": {
        "repo": "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
        "params": "8B",
        "ram": "~5 GB",
        "note": "Llama 3.1 8B, good quality/speed balance",
    },
    "llama-3.1-8b-8bit": {
        "repo": "mlx-community/Meta-Llama-3.1-8B-Instruct-8bit",
        "params": "8B",
        "ram": "~9 GB",
        "note": "Llama 3.1 8B, higher precision",
    },
    "llama-3.1-70b-4bit": {
        "repo": "mlx-community/Meta-Llama-3.1-70B-Instruct-4bit",
        "params": "70B",
        "ram": "~40 GB",
        "note": "Best quality, needs 64+ GB RAM",
    },
    "llama-3.1-70b-8bit": {
        "repo": "mlx-community/Meta-Llama-3.1-70B-Instruct-8bit",
        "params": "70B",
        "ram": "~75 GB",
        "note": "Maximum quality, needs 128 GB RAM",
    },
}

AUDIO_EXTENSIONS = {".mp3", ".wav", ".m4a", ".flac", ".ogg", ".aac", ".wma", ".opus"}

DEFAULT_SUMMARY_PROMPT = (
    "You are a helpful assistant. Summarize the following transcript concisely, "
    "capturing the key points, decisions, and action items. "
    "Use bullet points where appropriate."
)

DEFAULT_LLM_MODEL = "mistral-7b-4bit"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

_verbosity = 0  # -1 = quiet, 0 = normal, 1 = verbose


def log(msg: str, level: int = 0) -> None:
    """Print to stderr if verbosity allows."""
    if _verbosity >= level:
        print(msg, file=sys.stderr)


def log_verbose(msg: str) -> None:
    log(msg, level=1)


# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------


def check_dependencies(need_summarize: bool) -> None:
    if platform.machine() != "arm64":
        log("Warning: This tool is optimized for Apple Silicon (arm64). "
            "Performance on other architectures may be degraded.")

    if not shutil.which("ffmpeg"):
        log("Error: ffmpeg not found. Install via: brew install ffmpeg")
        sys.exit(2)

    try:
        import mlx_whisper  # noqa: F401
    except ImportError:
        log("Error: mlx-whisper not installed. Try deleting .venv/ and re-running.")
        sys.exit(2)

    if need_summarize:
        try:
            import mlx_lm  # noqa: F401
        except ImportError:
            log("Error: mlx-lm not installed. Try deleting .venv/ and re-running.")
            sys.exit(2)


# ---------------------------------------------------------------------------
# Audio extraction
# ---------------------------------------------------------------------------


def is_audio_file(path: str) -> bool:
    return os.path.splitext(path)[1].lower() in AUDIO_EXTENSIONS


def extract_audio(input_path: str) -> str:
    """Extract audio from a video file to a temporary 16 kHz mono WAV.

    Returns the path to the temp WAV file. Caller must delete it.
    """
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    tmp.close()

    log_verbose(f"Extracting audio from {input_path} ...")
    cmd = [
        "ffmpeg", "-y", "-i", input_path,
        "-vn", "-acodec", "pcm_s16le", "-ar", "16000", "-ac", "1",
        tmp.name,
    ]
    # Suppress ffmpeg output unless verbose
    stderr_dest = None if _verbosity >= 1 else subprocess.DEVNULL
    try:
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=stderr_dest)
    except subprocess.CalledProcessError as exc:
        os.unlink(tmp.name)
        log(f"Error: ffmpeg failed (exit code {exc.returncode}). "
            "Is the input a valid media file?")
        sys.exit(3)

    log_verbose(f"Audio extracted to {tmp.name}")
    return tmp.name


def prepare_audio(input_path: str) -> tuple[str, bool]:
    """Return (audio_path, needs_cleanup).

    If the input is already a WAV at 16 kHz mono, use it directly.
    Otherwise, run ffmpeg to convert/extract.
    """
    if is_audio_file(input_path):
        # Re-encode to ensure 16 kHz mono WAV for consistency
        log_verbose("Input is an audio file — re-encoding to 16 kHz mono WAV ...")
        return extract_audio(input_path), True

    # Assume video — extract audio track
    return extract_audio(input_path), True


# ---------------------------------------------------------------------------
# Transcription
# ---------------------------------------------------------------------------


def transcribe_audio(
    audio_path: str,
    model: str,
    language: str | None,
    task: str,
    word_timestamps: bool,
) -> dict:
    import mlx_whisper

    repo = MODEL_REGISTRY[model]["repo"]
    log(f"Transcribing with model '{model}' ({repo}) ...")
    log_verbose(f"  RAM estimate: {MODEL_REGISTRY[model]['ram']}")

    result = mlx_whisper.transcribe(
        audio_path,
        path_or_hf_repo=repo,
        verbose=True if _verbosity >= 1 else None,
        word_timestamps=word_timestamps,
        language=language,
        task=task,
    )
    log_verbose(f"Detected language: {result.get('language', 'unknown')}")
    return result


# ---------------------------------------------------------------------------
# Output formatters
# ---------------------------------------------------------------------------


def _fmt_ts_srt(seconds: float) -> str:
    """Format seconds as HH:MM:SS,mmm (SRT style)."""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def _fmt_ts_vtt(seconds: float) -> str:
    """Format seconds as HH:MM:SS.mmm (VTT style)."""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int(round((seconds - int(seconds)) * 1000))
    return f"{h:02d}:{m:02d}:{s:02d}.{ms:03d}"


def format_txt(result: dict) -> str:
    segments = result.get("segments", [])
    if not segments:
        return result.get("text", "").strip()
    return "\n".join(seg["text"].strip() for seg in segments)


def format_srt(result: dict) -> str:
    lines = []
    for i, seg in enumerate(result.get("segments", []), start=1):
        start = _fmt_ts_srt(seg["start"])
        end = _fmt_ts_srt(seg["end"])
        text = seg["text"].strip()
        lines.append(f"{i}\n{start} --> {end}\n{text}\n")
    return "\n".join(lines)


def format_vtt(result: dict) -> str:
    lines = ["WEBVTT", ""]
    for seg in result.get("segments", []):
        start = _fmt_ts_vtt(seg["start"])
        end = _fmt_ts_vtt(seg["end"])
        text = seg["text"].strip()
        lines.append(f"{start} --> {end}\n{text}\n")
    return "\n".join(lines)


def format_json(result: dict) -> str:
    return json.dumps(result, indent=2, ensure_ascii=False)


FORMATTERS = {
    "txt": format_txt,
    "srt": format_srt,
    "vtt": format_vtt,
    "json": format_json,
}

# ---------------------------------------------------------------------------
# Summarization
# ---------------------------------------------------------------------------


def resolve_llm_model(name: str) -> str:
    """Resolve an LLM name to a HuggingFace repo path.

    Accepts either a registry shorthand (e.g. 'llama-3.1-70b-4bit')
    or a full HuggingFace repo path (e.g. 'mlx-community/...').
    """
    if name in LLM_REGISTRY:
        return LLM_REGISTRY[name]["repo"]
    # Assume it's a direct HuggingFace repo path
    return name


def summarize_text(
    text: str,
    llm_model: str,
    prompt: str,
    max_tokens: int,
) -> str:
    from mlx_lm import generate, load

    repo = resolve_llm_model(llm_model)
    display_name = llm_model if llm_model == repo else f"{llm_model} ({repo})"
    if llm_model in LLM_REGISTRY:
        log_verbose(f"  RAM estimate: {LLM_REGISTRY[llm_model]['ram']}")
    log(f"Loading LLM '{display_name}' for summarization ...")
    model, tokenizer = load(repo)

    messages = [
        {"role": "system", "content": prompt},
        {"role": "user", "content": text},
    ]

    # Check if transcript may exceed typical context windows
    approx_tokens = len(text.split()) * 1.3  # rough estimate
    if approx_tokens > 28000:
        log("Warning: Transcript is very long and may exceed the LLM context window. "
            "Summary quality may be affected.")

    if hasattr(tokenizer, "apply_chat_template"):
        formatted = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True
        )
    else:
        # Fallback for tokenizers without chat template
        formatted = f"{prompt}\n\nTranscript:\n{text}\n\nSummary:"

    log("Generating summary ...")
    summary = generate(
        model,
        tokenizer,
        prompt=formatted,
        max_tokens=max_tokens,
        verbose=_verbosity >= 1,
    )
    return summary.strip()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def build_model_table() -> str:
    lines = ["  Model    RAM       Notes"]
    lines.append("  " + "-" * 50)
    for name, info in MODEL_REGISTRY.items():
        lines.append(f"  {name:<8} {info['ram']:<9} {info['note']}")
    return "\n".join(lines)


def build_llm_table() -> str:
    lines = ["  Name                  RAM       Notes"]
    lines.append("  " + "-" * 62)
    for name, info in LLM_REGISTRY.items():
        lines.append(f"  {name:<22} {info['ram']:<9} {info['note']}")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    epilog = f"""
whisper model guide:
{build_model_table()}

llm model guide (for --summarize):
{build_llm_table()}

  You can also pass any HuggingFace MLX model repo directly to --llm-model.

examples:
  %(prog)s -i meeting.mp4
  %(prog)s -i meeting.mp4 -o transcript.srt -f srt
  %(prog)s -i lecture.mp4 -m small -l en
  %(prog)s -i interview.mp4 --summarize
  %(prog)s -i call.mp4 --summarize --prompt "List action items"
  %(prog)s -i call.mp4 --summarize --llm-model llama-3.1-8b-4bit
  %(prog)s -i lecture.mp4 -m large --summarize --llm-model llama-3.1-70b-4bit
  %(prog)s -i podcast.mp3 --summarize --llm-model mlx-community/some-custom-model
"""

    parser = argparse.ArgumentParser(
        prog="transcribe",
        description="Local video/audio transcription for Apple Silicon using MLX Whisper.",
        epilog=epilog,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("-V", "--version", action="version", version=f"%(prog)s {__version__}")

    # Input / Output
    parser.add_argument("-i", "--input", required=True, help="Input video or audio file")
    parser.add_argument("-o", "--output", default=None, help="Output file (default: stdout)")
    parser.add_argument(
        "-f", "--format",
        choices=["txt", "srt", "vtt", "json"],
        default="txt",
        help="Output format (default: txt)",
    )

    # Whisper options
    whisper_group = parser.add_argument_group("whisper options")
    whisper_group.add_argument(
        "-m", "--model",
        choices=list(MODEL_REGISTRY.keys()),
        default="turbo",
        help="Whisper model size (default: turbo)",
    )
    whisper_group.add_argument("-l", "--language", default=None, help="Language code, e.g. en, es, ja (default: auto-detect)")
    whisper_group.add_argument(
        "--task",
        choices=["transcribe", "translate"],
        default="transcribe",
        help="Task: transcribe or translate to English (default: transcribe)",
    )
    whisper_group.add_argument("--word-timestamps", action="store_true", help="Enable word-level timestamps")

    # LLM / summarization
    llm_group = parser.add_argument_group("summarization options")
    llm_group.add_argument("--summarize", action="store_true", help="Summarize transcript with a local LLM")
    llm_group.add_argument(
        "--llm-model",
        default=DEFAULT_LLM_MODEL,
        help=f"LLM preset name or HuggingFace repo (default: {DEFAULT_LLM_MODEL})",
    )
    llm_group.add_argument("--prompt", default=None, help="Custom system prompt for summarization")
    llm_group.add_argument("--prompt-file", default=None, help="Read summarization prompt from a file")
    llm_group.add_argument("--max-tokens", type=int, default=1024, help="Max tokens for LLM output (default: 1024)")

    # Verbosity
    verb_group = parser.add_mutually_exclusive_group()
    verb_group.add_argument("-v", "--verbose", action="store_true", help="Show progress and debug info")
    verb_group.add_argument("-q", "--quiet", action="store_true", help="Suppress all non-essential output")

    return parser


def main() -> None:
    global _verbosity

    parser = build_parser()
    args = parser.parse_args()

    # Set verbosity
    if args.verbose:
        _verbosity = 1
    elif args.quiet:
        _verbosity = -1
    else:
        _verbosity = 0

    # Validate input
    if not os.path.isfile(args.input):
        log(f"Error: Input file not found: {args.input}")
        sys.exit(1)

    # Validate output directory
    if args.output:
        out_dir = os.path.dirname(os.path.abspath(args.output))
        if not os.path.isdir(out_dir):
            log(f"Error: Output directory does not exist: {out_dir}")
            sys.exit(1)

    # Resolve prompt
    prompt = DEFAULT_SUMMARY_PROMPT
    if args.prompt_file:
        if not os.path.isfile(args.prompt_file):
            log(f"Error: Prompt file not found: {args.prompt_file}")
            sys.exit(1)
        with open(args.prompt_file, "r", encoding="utf-8") as f:
            prompt = f.read().strip()
    elif args.prompt:
        prompt = args.prompt

    # Check dependencies
    check_dependencies(need_summarize=args.summarize)

    # Prepare audio
    audio_path, needs_cleanup = prepare_audio(args.input)

    try:
        # Transcribe
        result = transcribe_audio(
            audio_path=audio_path,
            model=args.model,
            language=args.language,
            task=args.task,
            word_timestamps=args.word_timestamps,
        )

        # Format output
        formatter = FORMATTERS[args.format]
        transcript_output = formatter(result)

        # Write transcript
        if args.output:
            with open(args.output, "w", encoding="utf-8") as f:
                f.write(transcript_output)
            log(f"Transcript written to {args.output}")
        else:
            print(transcript_output)

        # Optional summarization
        if args.summarize:
            transcript_text = format_txt(result)
            summary = summarize_text(
                text=transcript_text,
                llm_model=args.llm_model,
                prompt=prompt,
                max_tokens=args.max_tokens,
            )

            if args.output:
                # Write summary alongside transcript
                summary_path = os.path.splitext(args.output)[0] + ".summary.txt"
                with open(summary_path, "w", encoding="utf-8") as f:
                    f.write(summary)
                log(f"Summary written to {summary_path}")
            else:
                print("\n--- Summary ---\n")
                print(summary)

        log("Done.")

    except KeyboardInterrupt:
        log("\nInterrupted.")
        sys.exit(130)
    except Exception as exc:
        log(f"Error during transcription: {exc}")
        if _verbosity >= 1:
            import traceback
            traceback.print_exc(file=sys.stderr)
        sys.exit(4)
    finally:
        if needs_cleanup and os.path.exists(audio_path):
            os.unlink(audio_path)
            log_verbose(f"Cleaned up temp file {audio_path}")


if __name__ == "__main__":
    main()
