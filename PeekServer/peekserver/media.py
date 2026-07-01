"""Media classification + thumbnail generation via macOS-native tools.

Thumbnails are generated ONCE and cached on the server's local disk, then served to every client.
That's the whole speed trick: browsing reads tiny cached JPEGs, never the big originals off slow
or remote storage. Images use `sips` (fast, handles HEIC); video/other use `qlmanage` (QuickLook
poster frame). Audio has no thumbnail (the UI shows a glyph).
"""
import os
import subprocess
import tempfile
import threading

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".tiff", ".tif",
             ".bmp", ".webp", ".dng", ".cr2", ".nef", ".arw", ".raf"}
VIDEO_EXT = {".mov", ".mp4", ".m4v", ".avi", ".mkv", ".hevc", ".3gp", ".mpg", ".mpeg", ".webm"}
AUDIO_EXT = {".m4a", ".mp3", ".wav", ".aiff", ".aif", ".caf", ".aac", ".flac"}


def classify(path: str) -> str:
    ext = os.path.splitext(path)[1].lower()
    if ext in IMAGE_EXT:
        return "image"
    if ext in VIDEO_EXT:
        return "video"
    if ext in AUDIO_EXT:
        return "audio"
    return "other"


def is_media(path: str) -> bool:
    return classify(path) in ("image", "video", "audio")


def thumb_path(cache_dir: str, mid: str) -> str:
    # shard by first 2 chars to avoid one giant directory
    sub = os.path.join(cache_dir, mid[:2])
    return os.path.join(sub, mid + ".jpg")


def ensure_thumb(src: str, dst: str, ftype: str, size: int) -> bool:
    """Generate a JPEG thumbnail at `dst` if missing/stale. Returns True if a thumb exists after."""
    if not os.path.exists(src):
        return False
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return True
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if ftype == "image":
        return _sips_thumb(src, dst, size)
    if ftype == "video" or ftype == "other":
        return _ql_thumb(src, dst, size)
    return False  # audio → no thumb


def _sips_thumb(src: str, dst: str, size: int) -> bool:
    try:
        r = subprocess.run(
            ["sips", "-s", "format", "jpeg", "-Z", str(size), src, "--out", dst],
            capture_output=True, timeout=60,
        )
        return r.returncode == 0 and os.path.exists(dst)
    except Exception:
        return False


def _ql_thumb(src: str, dst: str, size: int) -> bool:
    """QuickLook poster frame → PNG in a temp dir → convert to the cache JPEG via sips."""
    try:
        with tempfile.TemporaryDirectory() as td:
            subprocess.run(["qlmanage", "-t", "-s", str(size), "-o", td, src],
                           capture_output=True, timeout=90)
            pngs = [f for f in os.listdir(td) if f.lower().endswith(".png")]
            if not pngs:
                return False
            png = os.path.join(td, pngs[0])
            subprocess.run(["sips", "-s", "format", "jpeg", png, "--out", dst],
                           capture_output=True, timeout=60)
            return os.path.exists(dst)
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Video streaming proxies
#
# Full-resolution originals (4K, tens of Mbps) don't stream smoothly to a review
# client over LAN/Wi-Fi: the player stalls fetching the moov index and can't keep
# up with the bitrate. So — exactly like thumbnails — we transcode each video ONCE
# to a small, faststart, bitrate-capped 720p H.264 MP4 cached on the server's disk,
# and serve THAT to the player. moov-at-front = instant start; low bitrate = smooth
# playback. The full original stays available (via /full) for the actual import.
# ---------------------------------------------------------------------------

_proxy_locks_guard = threading.Lock()
_proxy_locks: dict = {}


def proxy_path(cache_dir: str, mid: str) -> str:
    sub = os.path.join(cache_dir, mid[:2])
    return os.path.join(sub, mid + ".mp4")


def ffmpeg_proxy_args(ffmpeg_bin: str, src: str, dst: str, height: int, maxrate_k: int) -> list:
    """Pure builder for the transcode command (unit-tested). 720p (never upscaled), H.264
    veryfast/CRF 26 with a hard bitrate cap so it always fits the pipe, AAC audio, moov moved
    to the front for instant start."""
    return [
        ffmpeg_bin, "-y", "-nostdin", "-i", src,
        "-vf", r"scale=-2:'min(%d,ih)'" % height,
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "26",
        "-maxrate", "%dk" % maxrate_k, "-bufsize", "%dk" % (maxrate_k * 2),
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        dst,
    ]


def ensure_video_proxy(src: str, dst: str, ffmpeg_bin: str = "ffmpeg",
                       height: int = 720, maxrate_k: int = 4000) -> bool:
    """Generate the streaming proxy at `dst` if missing/stale. Serialized per-destination so
    concurrent player requests for the same video don't launch duplicate transcodes. Writes to a
    temp file then atomically renames, so a killed transcode never leaves a half file that looks
    valid. Returns True if a proxy exists after."""
    if not os.path.exists(src):
        return False
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return True
    with _proxy_locks_guard:
        lock = _proxy_locks.setdefault(dst, threading.Lock())
    with lock:
        # re-check inside the lock — another thread may have just built it
        if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
            return True
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        tmp = dst + ".tmp.mp4"
        try:
            r = subprocess.run(ffmpeg_proxy_args(ffmpeg_bin, src, tmp, height, maxrate_k),
                               capture_output=True, timeout=1800)
            if r.returncode == 0 and os.path.exists(tmp) and os.path.getsize(tmp) > 0:
                os.replace(tmp, dst)
                return True
            return False
        except Exception:
            return False
        finally:
            if os.path.exists(tmp):
                try:
                    os.remove(tmp)
                except OSError:
                    pass
