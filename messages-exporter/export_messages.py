#!/usr/bin/env python3
# =============================================================================
#
#   MESSAGES EXPORTER
#
#   File:        export_messages.py
#   Version:     1.0.1
#   Author:      Generated with Claude Code
#   License:     MIT
#   Requires:    macOS, Python 3.9+
#                Brew: exiftool, ffmpeg
#                Pip:  Pillow, pillow-heif, emoji
#
#   Description:
#     Exports iMessage conversations from the Mac Messages app by contact
#     name and date range. Copies photos, videos, and files into an
#     organized folder structure; names each media file after the next
#     text message that follows it in the thread. Converts HEIC -> JPG
#     and strips EXIF/GPS metadata from images and videos.
#
#   Usage:
#     export_messages "<Name>" --start "YYYY-MM-DD HH:MM:SS" \
#                              --end   "YYYY-MM-DD HH:MM:SS" \
#                              --output <folder> [--emoji word|strip|keep]
#
#   Dates are interpreted in LOCAL time.
#
#   Output layout:
#     <output>/<Contact>_<timestamp>/
#       attachments/    all photos, videos, files
#       transcript.txt  human-readable chronological transcript
#       manifest.json   structured export record (one entry per message)
#       summary.txt     run summary (counts, range, output path)
#
#   Reads:
#     ~/Library/Messages/chat.db                       (needs Full Disk Access)
#     ~/Library/Application Support/AddressBook/...    (for contact lookup)
#
# =============================================================================

"""Messages Exporter — iMessage conversation exporter for macOS.

See module header for full description. Run with --help for CLI options or
--version for the version string.
"""

import sqlite3, shutil, re, json, argparse, subprocess, sys, hashlib
from datetime import datetime, timezone
from pathlib import Path

__version__ = '1.2.0'

# Offset from Unix epoch (1970-01-01 UTC) to Mac absolute time epoch
# (2001-01-01 UTC). chat.db stores `message.date` in Mac absolute time;
# newer macOS releases store it in nanoseconds (see mts() for the heuristic).
MAC = 978307200


# ─── Capability detection ───────────────────────────────────────────────────
#
# The exporter degrades gracefully based on what's installed. At startup we
# probe for optional binaries and Python packages; main() prints a banner
# showing which paths will be used.

def _have(cmd):
    """Return True if the given command is on PATH."""
    return shutil.which(cmd) is not None

HAS_SIPS     = _have('sips')      # macOS built-in — fallback HEIC->JPG converter
HAS_EXIFTOOL = _have('exiftool')  # preferred metadata stripper (no re-encoding)
HAS_FFMPEG   = _have('ffmpeg')    # preferred video metadata stripper

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    Image = None
    HAS_PIL = False

# pillow_heif registers HEIF/HEIC support into PIL. Without it, PIL cannot open
# iPhone HEIC files and we fall back to `sips`.
HAS_HEIF = False
if HAS_PIL:
    try:
        import pillow_heif
        pillow_heif.register_heif_opener()
        HAS_HEIF = True
    except ImportError:
        pass

# The `emoji` library provides demojize() with customizable delimiters, used
# for --emoji word mode to turn e.g. 🔥 into (fire).
try:
    import emoji as _emoji_lib
    HAS_EMOJI = True
except ImportError:
    _emoji_lib = None
    HAS_EMOJI = False


def print_caps():
    """Print the Python path and detected sanitize capabilities."""
    heic = ('PIL+pillow_heif' if (HAS_PIL and HAS_HEIF)
            else 'sips' if HAS_SIPS
            else 'NONE — HEIC will be copied unchanged')
    img  = ('exiftool' if HAS_EXIFTOOL
            else 'PIL re-save' if HAS_PIL
            else 'NONE — metadata will remain')
    vid  = ('ffmpeg' if HAS_FFMPEG
            else 'exiftool' if HAS_EXIFTOOL
            else 'NONE — metadata will remain')
    print(f'Version    : {__version__}')
    print(f'Python     : {sys.executable}')
    print('Sanitize:')
    print(f'  HEIC->JPG  : {heic}')
    print(f'  Image EXIF : {img}')
    print(f'  Video meta : {vid}')
    print(f'  Emoji lib  : {"installed" if HAS_EMOJI else "NOT installed"}')
    hints = []
    if not HAS_PIL: hints.append('pip install Pillow pillow-heif')
    elif not HAS_HEIF: hints.append('pip install pillow-heif')
    if not HAS_EMOJI: hints.append('pip install emoji')
    if not HAS_EXIFTOOL: hints.append('brew install exiftool')
    if not HAS_FFMPEG: hints.append('brew install ffmpeg')
    if hints:
        print('  Missing: ' + ' ; '.join(hints))


# ─── Time and text helpers ──────────────────────────────────────────────────

def mts(x):
    """Mac timestamp -> timezone-aware UTC datetime.

    chat.db historically stored seconds since Mac epoch; macOS 10.13+ stores
    nanoseconds. We use 1e10 as the boundary heuristic: anything above that
    is treated as nanoseconds.
    """
    if x > 1e10:
        x /= 1e9
    return datetime.fromtimestamp(x + MAC, tz=timezone.utc)

def parse(s):
    """Parse a user-supplied date string (LOCAL time) to UTC datetime.

    Accepts 'YYYY-MM-DD HH:MM:SS', 'YYYY-MM-DD HH:MM', or 'YYYY-MM-DD'.
    astimezone() is what makes the input LOCAL — datetime.strptime produces
    a naive datetime, and astimezone() on a naive dt assumes local time.
    """
    for f in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y-%m-%d'):
        try:
            return datetime.strptime(s, f).astimezone(timezone.utc)
        except ValueError:
            pass
    raise ValueError(f'Bad date: {s}')

def tts(t):
    """UTC datetime -> Mac-epoch seconds (float) for chat.db WHERE filters."""
    return t.timestamp() - MAC

def norm(p):
    """Normalize phone to last 10 digits for matching across formats."""
    d = re.sub(r'\D', '', p)
    return d[-10:] if len(d) >= 10 else d

def san(n):
    """Replace filesystem-unsafe chars with underscores (non-emoji-aware)."""
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', n)


def slug(t, mode='word', mx=120):
    """Build a filename-safe slug from caption text.

    Modes:
      strip — drop emoji and non-word characters (legacy behavior)
      word  — replace each emoji with its (name) form, e.g. 🔥 -> (fire)
      keep  — preserve emoji literally (macOS APFS handles UTF-8 fine)

    `mx` bounds the slug length; 120 chars comfortably fits multi-word emoji
    names like (face_with_hand_over_mouth) even after a long caption.
    """
    if not t or not t.strip():
        return 'NO_TEXT'
    s = t.strip()
    if mode == 'word':
        # demojize rewrites emoji chars to (name); everything else passes through.
        if HAS_EMOJI:
            s = _emoji_lib.demojize(s, delimiters=('(', ')'))
        # Keep Unicode alnum (so café, 日本語 survive) + safe ASCII punctuation.
        s = ''.join(c for c in s if c.isalnum() or c in ' -_()')
    elif mode == 'keep':
        # Same as 'word' but also keep any printable non-ASCII char (emoji).
        s = ''.join(c for c in s
                    if c.isalnum()
                       or c in ' -_()'
                       or (ord(c) > 127 and c.isprintable()))
    else:  # strip
        s = re.sub(r'[^\w\s\-]', '', s, flags=re.UNICODE)
    s = re.sub(r'\s+', '_', s).strip('_')[:mx].rstrip('_')
    return s or 'NO_TEXT'


def uniq(d, stem, ext, seen):
    """Reserve a unique filename in folder `d`. Appends _2, _3, ... on collision."""
    c = stem + ext
    if c not in seen:
        seen.add(c)
        return d / c
    i = 2
    while True:
        c = f'{stem}_{i}{ext}'
        if c not in seen:
            seen.add(c)
            return d / c
        i += 1


def knd(mime, ext):
    """Classify attachment as 'photo', 'video', or 'file' by mime-type or extension."""
    m = mime or ''
    e = ext.lower()
    if m.startswith('image/') or e in ('.jpg', '.jpeg', '.png', '.gif',
                                       '.heic', '.heif', '.webp', '.bmp', '.tiff'):
        return 'photo'
    if m.startswith('video/') or e in ('.mp4', '.mov', '.m4v', '.avi', '.mkv'):
        return 'video'
    return 'file'


# ─── Caption extraction ─────────────────────────────────────────────────────
#
# Modern iMessage often stores the message body in `message.attributedBody`
# (a binary NSKeyedArchiver blob) rather than `message.text` (which is then
# empty). The blob contains an NSString entry whose layout is approximately:
#
#     NSString \x01 \x94 \x84 \x01 + <length_byte> <utf8_bytes>
#
# We locate the NSString marker, then scan forward for a '+' (0x2b) that
# encodes the string. Multiple '+' bytes can appear; we validate a candidate
# by checking that the first few bytes after the length byte are either
# printable ASCII or UTF-8 continuation bytes. Invalid candidates are skipped.

def get_body(text, ab):
    """Return the message body. Prefers the plain text column; falls back to
    extracting from the attributedBody NSKeyedArchiver blob when text is empty.

    Returns '' if nothing usable is found.
    """
    # Strip U+FFFC (Object Replacement Character) — iMessage inserts it
    # as a placeholder for inline attachments. Noise in filenames/transcript.
    t = (text or '').replace('￼', '').strip()
    if t:
        return t
    if not ab:
        return ''
    try:
        blob = bytes(ab)
        idx = blob.find(b'NSString')
        if idx == -1:
            return ''
        # String delimiter sits within ~40 bytes after the NSString marker.
        search_end = min(idx + 40, len(blob) - 2)
        pos = idx
        while pos < search_end:
            plus = blob.find(b'+', pos, search_end)
            if plus == -1 or plus + 2 > len(blob):
                return ''
            length = blob[plus + 1]
            if length == 0 or plus + 2 + length > len(blob):
                pos = plus + 1
                continue
            # Validate: the first few bytes of the purported string must be
            # printable ASCII (>=32, !=127) or UTF-8 continuation (>=0x80).
            probe = blob[plus + 2 : plus + 2 + min(length, 4)]
            if probe and all((b >= 32 and b != 127) or b >= 0x80 for b in probe):
                result = blob[plus + 2 : plus + 2 + length].decode('utf-8',
                                                                   errors='ignore')
                result = result.replace('￼', '').strip()
                if result:
                    return result
            # False candidate — keep scanning for the next '+'.
            pos = plus + 1
        return ''
    except Exception:
        return ''


# ─── Contact resolution ─────────────────────────────────────────────────────
#
# Given a display name, find all handle IDs (phone numbers / emails) that
# Messages associates with the contact. We look up the contact in the
# AddressBook SQLite DB, collect their phone numbers and emails, then match
# those against the handle table in chat.db.

def get_handles(conn, name):
    """Return chat.db handle IDs for a contact named (substring match) `name`."""
    h = []   # matched handle IDs in chat.db
    pe = []  # all phones/emails associated with contact in AddressBook
    ab_sources = (Path.home() / 'Library' / 'Application Support'
                  / 'AddressBook' / 'Sources')
    for ab in ab_sources.glob('*/AddressBook-v22.abcddb'):
        try:
            c = sqlite3.connect(f'file:{ab}?mode=ro', uri=True)
            pids = []
            for pk, f, l, n in c.execute(
                    'SELECT Z_PK,ZFIRSTNAME,ZLASTNAME,ZNICKNAME FROM ZABCDRECORD'):
                f, l, n = (f or '').strip(), (l or '').strip(), (n or '').strip()
                names = [x for x in [f'{f} {l}'.strip(), f, l, n] if x]
                if any(name.lower() in x.lower() for x in names):
                    pids.append(pk)
            if pids:
                ph = ','.join('?' * len(pids))
                for (r,) in c.execute(
                        f'SELECT ZFULLNUMBER FROM ZABCDPHONENUMBER WHERE ZOWNER IN ({ph})',
                        pids):
                    if r: pe.append(r)
                for (r,) in c.execute(
                        f'SELECT ZADDRESS FROM ZABCDEMAILADDRESS WHERE ZOWNER IN ({ph})',
                        pids):
                    if r: pe.append(r)
            c.close()
        except sqlite3.DatabaseError:
            pass

    nums = {norm(x) for x in pe if x and '@' not in x}
    mails = {x.lower() for x in pe if '@' in x}
    for (x,) in conn.execute('SELECT id FROM handle'):
        if x.lower() in mails or norm(x) in nums:
            h.append(x)
    # Loose fallback: substring match on name tokens (handles edge cases where
    # AddressBook is incomplete or the chat is with a non-contact).
    if not h:
        for (x,) in conn.execute('SELECT id FROM handle'):
            if any(len(p) > 2 and p in x.lower() for p in name.lower().split()):
                h.append(x)
    return list(dict.fromkeys(h))


# ─── Sanitize helpers ───────────────────────────────────────────────────────
#
# Priority chain (see sanitize_image / sanitize_video):
#   HEIC -> JPG:  PIL+pillow_heif  ->  sips             ->  keep HEIC
#   Image EXIF:   exiftool         ->  PIL re-save      ->  leave as-is
#   Video meta:   ffmpeg           ->  exiftool         ->  leave as-is
#
# exiftool and ffmpeg -c copy are preferred because they strip metadata
# WITHOUT re-encoding the media (lossless). PIL re-save is a last resort.

def _exiftool_strip(path):
    """Run `exiftool -all= -overwrite_original` on path. Returns True on success."""
    if not HAS_EXIFTOOL:
        return False
    try:
        subprocess.run(['exiftool', '-all=', '-overwrite_original', '-q', '-q',
                        str(path)], check=True, capture_output=True)
        return True
    except subprocess.CalledProcessError:
        return False

def _pil_resave(path):
    """Re-save the image in place via PIL to drop metadata.

    JPEGs incur a mild re-encode quality hit. Only used when exiftool isn't
    available.
    """
    if not HAS_PIL:
        return False
    tmp = None
    try:
        img = Image.open(path)
        fmt = img.format or 'JPEG'
        if fmt == 'JPEG' and img.mode not in ('RGB', 'L'):
            img = img.convert('RGB')
        kw = {'quality': 92, 'optimize': True} if fmt == 'JPEG' else {}
        tmp = path.with_name(path.name + '.__tmp__')
        img.save(tmp, fmt, **kw)
        img.close()
        tmp.replace(path)
        return True
    except Exception as ex:
        print(f'      PIL strip failed on {path.name}: {ex}')
        try:
            if tmp: tmp.unlink(missing_ok=True)
        except Exception:
            pass
        return False


def sanitize_image(src, folder, stem, orig_ext, seen):
    """Copy `src` image into `folder`, converting HEIC->JPG when possible and
    stripping metadata. Returns (dest_path, converted_bool).

    `seen` is a shared set of reserved filenames; updated in place.
    """
    is_heic = orig_ext in ('.heic', '.heif')

    # Primary HEIC path: PIL + pillow_heif. Saving via PIL without passing
    # exif= drops EXIF automatically, so no separate strip pass is needed.
    if is_heic and HAS_PIL and HAS_HEIF:
        dest = uniq(folder, stem, '.jpg', seen)
        try:
            img = Image.open(src).convert('RGB')
            img.save(dest, 'JPEG', quality=92, optimize=True)
            img.close()
            return dest, True
        except Exception as ex:
            print(f'      PIL HEIC failed on {src.name}: {ex}')
            try: dest.unlink(missing_ok=True)
            except Exception: pass
            seen.discard(dest.name)

    # Fallback HEIC path: macOS sips converter, then strip metadata separately.
    if is_heic and HAS_SIPS:
        dest = uniq(folder, stem, '.jpg', seen)
        try:
            subprocess.run(['sips', '-s', 'format', 'jpeg', str(src),
                            '--out', str(dest)],
                           check=True, capture_output=True)
            _exiftool_strip(dest) or _pil_resave(dest)
            return dest, True
        except subprocess.CalledProcessError:
            print(f'      sips HEIC failed on {src.name}')
            try: dest.unlink(missing_ok=True)
            except Exception: pass
            seen.discard(dest.name)

    # Non-HEIC (or HEIC conversion unavailable): plain copy + metadata strip.
    dest = uniq(folder, stem, orig_ext, seen)
    shutil.copy2(src, dest)
    if not _exiftool_strip(dest):
        _pil_resave(dest)
    return dest, False


def sanitize_video(src, folder, stem, orig_ext, seen):
    """Copy `src` video into `folder`, stripping container/stream metadata.
    Returns dest_path.

    ffmpeg -c copy avoids re-encoding (no quality loss, no disk bloat).
    """
    dest = uniq(folder, stem, orig_ext, seen)
    if HAS_FFMPEG:
        try:
            subprocess.run([
                'ffmpeg', '-y', '-loglevel', 'error',
                '-i', str(src),
                '-map_metadata', '-1',
                '-map_metadata:s:v', '-1',
                '-map_metadata:s:a', '-1',
                '-c', 'copy',
                str(dest),
            ], check=True, capture_output=True)
            return dest
        except subprocess.CalledProcessError as ex:
            print(f'      ffmpeg failed on {src.name}: '
                  f'{ex.stderr.decode("utf-8", "ignore")[:200]}')
            try: dest.unlink(missing_ok=True)
            except Exception: pass

    # ffmpeg unavailable or failed — copy raw, try exiftool for container meta.
    shutil.copy2(src, dest)
    _exiftool_strip(dest)
    return dest


# ─── Raw-mode helpers ───────────────────────────────────────────────────────
#
# "Raw" / forensic mode: copy attachments byte-for-byte (no HEIC->JPG, no
# EXIF strip), keep their original filenames (prefixed for sort order),
# capture SHA-256 + filesystem timestamps + EXIF dump for every artifact,
# and write an append-only chain_of_custody.log alongside metadata.json.

def hashes_file(path, chunk_size=1 << 20):
    """Compute MD5, SHA-1, and SHA-256 of a file in a single streaming pass.

    Returns {'md5': hex, 'sha1': hex, 'sha256': hex}. Forensic chain-of-
    custody records traditionally include all three: SHA-256 is the modern
    integrity primitive, but MD5 and SHA-1 are still expected by older
    forensic tooling and historical reports. Computing them together is
    cheaper than three separate file reads — the chunk loop runs once.
    """
    md5    = hashlib.md5()
    sha1   = hashlib.sha1()
    sha256 = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(chunk_size), b''):
            md5.update(chunk)
            sha1.update(chunk)
            sha256.update(chunk)
    return {
        'md5':    md5.hexdigest(),
        'sha1':   sha1.hexdigest(),
        'sha256': sha256.hexdigest(),
    }


def fs_stat(path):
    """Return size + filesystem timestamps as ISO strings (UTC).
    `birthtime` is macOS-specific and may be absent on other filesystems.
    """
    st = path.stat()
    out = {
        'size_bytes': st.st_size,
        'mtime': datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).isoformat(),
        'ctime': datetime.fromtimestamp(st.st_ctime, tz=timezone.utc).isoformat(),
    }
    bt = getattr(st, 'st_birthtime', None)
    if bt:
        out['birthtime'] = datetime.fromtimestamp(bt, tz=timezone.utc).isoformat()
    return out


def exiftool_version():
    """Return the installed exiftool version string, or None if unavailable."""
    if not HAS_EXIFTOOL:
        return None
    try:
        r = subprocess.run(['exiftool', '-ver'],
                           check=True, capture_output=True, timeout=5)
        return r.stdout.decode('utf-8', errors='replace').strip()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError):
        return None


def extract_exif(path):
    """Read-only EXIF/metadata extraction via `exiftool -json -G`.

    Does not modify the file. Returns a dict of tag-group => value, or None
    when exiftool is unavailable, fails, or yields nothing.
    """
    if not HAS_EXIFTOOL:
        return None
    try:
        r = subprocess.run(
            ['exiftool', '-json', '-G', '-n', str(path)],
            check=True, capture_output=True, timeout=30)
        data = json.loads(r.stdout.decode('utf-8', errors='replace'))
        if data and isinstance(data, list) and data[0]:
            entry = data[0]
            # Drop noisy / path-leaking fields. SourceFile is just the path
            # we passed in; the ExifTool group is metadata about exiftool.
            entry.pop('SourceFile', None)
            for k in list(entry.keys()):
                if k.startswith('ExifTool:'):
                    entry.pop(k, None)
            return entry or None
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired,
            json.JSONDecodeError, OSError):
        return None
    return None


def raw_prefix(seq, dt, is_from_me, sender_handle, contact):
    """Sortable filename prefix: '00001_20260426T155500_Me' or
    '00001_20260426T155500_+15551234567'. Compact local-time stamp keeps
    the directory listing chronological; the seq number disambiguates
    same-second collisions and matches transcript/manifest entries.
    """
    ts = dt.strftime('%Y%m%dT%H%M%S')
    who = 'Me' if is_from_me else (sender_handle or contact or 'unknown')
    return f'{seq:05d}_{ts}_{san(who)}'


def _now_iso():
    """UTC now as an ISO-8601 string (used as the chain-of-custody timestamp)."""
    return datetime.now(tz=timezone.utc).isoformat()


def export_raw(base, contact, handles, start_dt, end_dt, msgs, atts):
    """Forensic export: original bytes, flat layout, hashes + EXIF metadata.

    Writes into `base` (already created):
      <prefix>.txt              — message body, when present
      <prefix>_<orig_filename>  — attachment, byte-identical to source
      transcript.txt            — human-readable chronological log
      manifest.json             — compact per-message + saved-name + sha256
      metadata.json             — full per-attachment metadata (mime, size,
                                  fs timestamps, exif, source path, and
                                  hashes={md5,sha1,sha256})
      chain_of_custody.log      — append-only line per action; COPY and
                                  WRITE_BODY records carry md5+sha1+sha256
      summary.txt               — written by main(), not here

    Returns counters (photos, videos, other, errors) for the summary.
    """
    started = _now_iso()
    log = []
    log.append(f'{started} START contact="{contact}" handles={list(handles)} '
               f'range_start={start_dt.isoformat() if start_dt else "None"} '
               f'range_end={end_dt.isoformat() if end_dt else "None"}')
    ev = exiftool_version()
    log.append(f'{started} VERSION exporter={__version__} '
               f'exiftool={ev or "unavailable"}')

    metadata = {
        'export': {
            'version': __version__,
            'mode': 'raw',
            'contact': contact,
            'handles': list(handles),
            'range_start_utc': start_dt.isoformat() if start_dt else None,
            'range_end_utc':   end_dt.isoformat()   if end_dt   else None,
            'started_at_utc':  started,
            'exiftool_version': ev,
        },
        'messages': [],
    }

    tx, mf = [], []
    seen = set()
    pc = vc = fc = errors = 0
    seq = 0

    for m in msgs:
        seq += 1
        rowid = m[0]
        dt_local = mts(m[1]).astimezone()
        ts_local = dt_local.strftime('%Y-%m-%d %H:%M:%S %Z')
        is_from_me = bool(m[2])
        sender_handle = None if is_from_me else m[5]
        sender_label = 'Me' if is_from_me else (sender_handle or contact)
        body = get_body(m[3], m[4])
        prefix = raw_prefix(seq, dt_local, is_from_me, sender_handle, contact)

        msg_meta = {
            'seq': seq, 'rowid': rowid,
            'timestamp_utc':   mts(m[1]).isoformat(),
            'timestamp_local': ts_local,
            'is_from_me': is_from_me,
            'sender': sender_label,
            'handle': sender_handle,
            'body': body,
            'body_file': None,
            'body_hashes': None,
            'attachments': [],
        }

        tx.append(f'[{seq:05d}] {ts_local}  |  {sender_label}')
        if body:
            tx.append(body)
            body_path = uniq(base, prefix, '.txt', seen)
            body_path.write_text(body, encoding='utf-8')
            body_h    = hashes_file(body_path)
            body_size = body_path.stat().st_size
            msg_meta['body_file']   = body_path.name
            msg_meta['body_hashes'] = body_h
            log.append(f'{_now_iso()} WRITE_BODY {body_path.name} '
                       f'md5={body_h["md5"]} sha1={body_h["sha1"]} '
                       f'sha256={body_h["sha256"]} size={body_size}')

        for att in atts[rowid]:
            fname, mime, xfer, att_rowid = att[0], att[1], att[2], att[3]
            xfer = xfer or f'att_{att_rowid}'
            # Preserve the original extension verbatim — no .jpeg->.jpg, no
            # case-fold. Forensic mode: byte-for-byte fidelity to source.
            ext = Path(xfer).suffix
            stem = f'{prefix}_{san(Path(xfer).stem)}'
            src = (Path(fname.replace('~', str(Path.home()))).resolve()
                   if fname else None)
            kind = knd(mime, ext.lower())

            att_meta = {
                'orig_filename': xfer,
                'orig_path': str(src) if src else None,
                'mime_type': mime,
                'rowid': att_rowid,
                'kind': kind,
                'saved_as': None,
                'size_bytes': None,
                'hashes': None,         # {'md5','sha1','sha256'} once copied
                'fs_timestamps': None,
                'exif': None,
                'error': None,
            }

            if kind == 'photo':
                pc += 1
            elif kind == 'video':
                vc += 1
            else:
                fc += 1

            if not src or not src.exists():
                att_meta['error'] = 'MISSING_SOURCE'
                tx.append(f'  [{kind.upper()}] {xfer} MISSING: {fname}')
                log.append(f'{_now_iso()} MISSING_SOURCE rowid={att_rowid} '
                           f'orig={xfer} src={fname}')
                errors += 1
                msg_meta['attachments'].append(att_meta)
                continue

            dest = uniq(base, stem, ext, seen)
            try:
                shutil.copy2(src, dest)
            except OSError as ex:
                att_meta['error'] = f'COPY_FAILED: {ex}'
                tx.append(f'  [{kind.upper()}] {xfer} COPY FAILED: {ex}')
                log.append(f'{_now_iso()} COPY_FAILED rowid={att_rowid} '
                           f'src={src} err={ex}')
                seen.discard(dest.name)
                errors += 1
                msg_meta['attachments'].append(att_meta)
                continue

            h    = hashes_file(dest)
            stat = fs_stat(dest)
            exif = extract_exif(dest) if kind in ('photo', 'video') else None
            att_meta.update({
                'saved_as': dest.name,
                'size_bytes': stat['size_bytes'],
                'hashes': h,
                'fs_timestamps': {k: v for k, v in stat.items()
                                  if k != 'size_bytes'},
                'exif': exif,
            })
            # Transcript stays compact (sha256 only, truncated). Full
            # MD5/SHA-1/SHA-256 are recorded in metadata.json and
            # chain_of_custody.log for forensic verification.
            tx.append(f'  [{kind.upper()}] {xfer} -> {dest.name} '
                      f'sha256={h["sha256"][:16]}…')
            log.append(f'{_now_iso()} COPY src={src} dest={dest.name} '
                       f'md5={h["md5"]} sha1={h["sha1"]} '
                       f'sha256={h["sha256"]} size={stat["size_bytes"]}')
            msg_meta['attachments'].append(att_meta)

        tx.append('')
        mf.append({
            'seq': seq,
            'ts': mts(m[1]).astimezone().isoformat(),
            'sender': sender_label,
            'body': body,
            'att': [{'orig': a['orig_filename'], 'saved': a['saved_as'],
                     'sha256': (a['hashes'] or {}).get('sha256'),
                     'error': a['error']}
                    for a in msg_meta['attachments']],
        })
        metadata['messages'].append(msg_meta)

    completed = _now_iso()
    metadata['export']['completed_at_utc'] = completed
    metadata['export']['counts'] = {
        'messages': len(msgs), 'photos': pc, 'videos': vc,
        'other': fc, 'errors': errors,
    }
    log.append(f'{completed} END messages={len(msgs)} photos={pc} '
               f'videos={vc} other={fc} errors={errors}')

    (base / 'transcript.txt').write_text('\n'.join(tx), encoding='utf-8')
    (base / 'manifest.json').write_text(
        json.dumps(mf, indent=2, ensure_ascii=False), encoding='utf-8')
    (base / 'metadata.json').write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False), encoding='utf-8')
    (base / 'chain_of_custody.log').write_text(
        '\n'.join(log) + '\n', encoding='utf-8')

    return {'pc': pc, 'vc': vc, 'fc': fc, 'errors': errors}


# ─── Main ───────────────────────────────────────────────────────────────────

def build_arg_parser():
    ap = argparse.ArgumentParser(
        prog='export_messages',
        description='Export iMessage conversations by contact + date range.')
    ap.add_argument('contact',
                    help='contact name substring (matched against AddressBook)')
    ap.add_argument('--start', default=None,
                    help='start datetime in LOCAL time (YYYY-MM-DD [HH:MM[:SS]])')
    ap.add_argument('--end', default=None,
                    help='end datetime in LOCAL time (YYYY-MM-DD [HH:MM[:SS]])')
    ap.add_argument('--output', default='messages_export',
                    help='output directory (default: messages_export)')
    ap.add_argument('--emoji', choices=['strip', 'word', 'keep'], default='word',
                    help='emoji handling in filenames: strip=drop, '
                         'word=(name) [default], keep=literal')
    ap.add_argument('--raw', action='store_true',
                    help='forensic raw export: byte-identical attachment copies '
                         '(no HEIC->JPG, no EXIF strip, original filenames), '
                         'flat directory layout, MD5+SHA1+SHA256 + extracted '
                         'EXIF in metadata.json, append-only '
                         'chain_of_custody.log carrying all three hashes per '
                         'action. Implies --emoji is ignored.')
    ap.add_argument('--version', action='version',
                    version=f'%(prog)s {__version__}')
    return ap


def main():
    ap = build_arg_parser()
    a = ap.parse_args()
    s = parse(a.start) if a.start else None
    e = parse(a.end) if a.end else None
    if s: print(f'Start (local): {s.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")}')
    if e: print(f'End   (local): {e.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")}')

    print_caps()

    # Loud warning when the user asked for word-mode but the emoji lib is
    # missing in this interpreter — otherwise the script would silently
    # degrade to strip mode, which previously caused confusion.
    if a.emoji == 'word' and not HAS_EMOJI:
        print()
        print('!' * 60)
        print('WARNING: --emoji word requested but `emoji` lib not found in')
        print(f'         {sys.executable}')
        print('         Filenames will drop emoji entirely (strip mode).')
        print('         Fix: install `emoji` into this interpreter, or run')
        print('         the script directly so its shebang picks the venv.')
        print('!' * 60)
        print()

    db = Path.home() / 'Library' / 'Messages' / 'chat.db'
    conn = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
    conn.row_factory = sqlite3.Row

    print(f'\n[1/5] Handles for "{a.contact}"...')
    hh = get_handles(conn, a.contact)
    if not hh:
        print('None found')
        conn.close()
        return
    print(f'      {hh}')

    ph = ','.join('?' * len(hh))
    cids = [r[0] for r in conn.execute(
        f'SELECT DISTINCT cmj.chat_id FROM chat_handle_join cmj '
        f'JOIN handle h ON h.ROWID=cmj.handle_id WHERE h.id IN ({ph})', hh)]
    print(f'[2/5] Chats: {cids}')

    where_cids = ','.join('?' * len(cids))
    conds = [f'cmj.chat_id IN ({where_cids})']
    params = list(cids)
    # chat.db stores message.date in Mac-epoch nanoseconds on modern macOS;
    # our tts() returns seconds, so multiply by 1e9 for the comparison.
    if s: conds.append('m.date>=?'); params.append(tts(s) * 1e9)
    if e: conds.append('m.date<=?'); params.append(tts(e) * 1e9)
    where = ' AND '.join(conds)

    # GROUP BY m.ROWID (effectively DISTINCT on the message identity) is the
    # defensive fix for a class of double-counting bugs: in some DB states a
    # single message can have multiple chat_message_join rows (handle change,
    # forwarded delivery, malformed history). Without dedup the SELECT
    # returns the same row N times, inflating the export. We always want one
    # row per message regardless of how many cmj rows exist.
    msgs = conn.execute(
        f'SELECT m.ROWID, m.date, m.is_from_me, m.text, m.attributedBody, h.id '
        f'FROM message m '
        f'JOIN chat_message_join cmj ON cmj.message_id=m.ROWID '
        f'LEFT JOIN handle h ON h.ROWID=m.handle_id '
        f'WHERE {where} GROUP BY m.ROWID ORDER BY m.date',
        params).fetchall()

    print(f'[3/5] {len(msgs)} messages in range')

    # Bounds + observed-range diagnostic. Surfaces what the SQL filter
    # actually applied vs. what made it through, so out-of-range bugs can
    # be diagnosed from the log without re-running with a debugger.
    if s:
        print(f'      Start bound : {s.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")} '
              f'(mac-epoch ns: {tts(s) * 1e9:.0f})')
    if e:
        print(f'      End bound   : {e.astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")} '
              f'(mac-epoch ns: {tts(e) * 1e9:.0f})')
    if msgs:
        first_date = msgs[0][1]
        last_date  = msgs[-1][1]
        first_dt = mts(first_date).astimezone()
        last_dt  = mts(last_date).astimezone()
        print(f'      First msg   : {first_dt.strftime("%Y-%m-%d %H:%M:%S %Z")} '
              f'(m.date: {first_date:.0f})')
        print(f'      Last msg    : {last_dt.strftime("%Y-%m-%d %H:%M:%S %Z")} '
              f'(m.date: {last_date:.0f})')

        # Sanity check: if any returned message falls outside the bounds we
        # passed in, that's a real bug (heuristic mismatch, units, etc.) and
        # we want to surface it loudly rather than silently exporting too much.
        # The seconds-vs-nanoseconds mts() heuristic is the most likely culprit
        # if this ever fires on a healthy DB.
        s_ns = tts(s) * 1e9 if s else None
        e_ns = tts(e) * 1e9 if e else None
        oob = []
        for m in msgs:
            d = m[1]
            if s_ns is not None and d < s_ns:
                oob.append((m[0], d, 'before start'))
            elif e_ns is not None and d > e_ns:
                oob.append((m[0], d, 'after end'))
        if oob:
            print(f'      ⚠️  {len(oob)} messages outside bounds (showing first 5):')
            for rowid, d, why in oob[:5]:
                dt = mts(d).astimezone().strftime("%Y-%m-%d %H:%M:%S %Z")
                print(f'         rowid={rowid} m.date={d:.0f} ({dt}) — {why}')

    if not msgs:
        conn.close()
        return

    # Pre-fetch attachments for each message (one query per message kept for
    # simplicity — typical export sizes are small).
    atts = {}
    for m in msgs:
        atts[m[0]] = conn.execute(
            'SELECT a.filename, a.mime_type, a.transfer_name, a.ROWID '
            'FROM attachment a '
            'JOIN message_attachment_join maj ON maj.attachment_id=a.ROWID '
            'WHERE maj.message_id=?', (m[0],)).fetchall()

    def has_media(m):
        return any(knd(a[1], Path(a[2] or '').suffix.lower()) in ('photo', 'video')
                   for a in atts[m[0]])

    def body_of(m):
        return get_body(m[3], m[4])

    tag = datetime.now().strftime('%Y%m%d_%H%M%S')
    conv_n = 0  # HEIC->JPG conversion counter (sanitized mode only)
    errors = 0  # missing-source / copy-failed counter (raw mode only)

    if a.raw:
        # Forensic mode skips caption derivation entirely (no slug naming),
        # which also keeps the [3/5] banner uncluttered for the operator.
        base = Path(a.output) / f'{san(a.contact)}_{tag}_raw'
        base.mkdir(parents=True, exist_ok=True)
        print(f'[4/5] Writing to {base}')
        counts = export_raw(base, a.contact, hh, s, e, msgs, atts)
        pc, vc, fc, errors = counts['pc'], counts['vc'], counts['fc'], counts['errors']
    else:
        # Caption rule: if a message has media, its caption is the body of
        # the first following message that has non-empty text. Matches the
        # observed pattern where the sender posts photos first, then texts
        # a description.
        caps = {}
        for i, m in enumerate(msgs):
            if has_media(m):
                own = body_of(m)
                if own:
                    caps[i] = own
                else:
                    for j in range(i + 1, len(msgs)):
                        b = body_of(msgs[j])
                        if b:
                            caps[i] = b
                            break

        mc = sum(1 for m in msgs if has_media(m))
        print(f'      Media: {mc}  Captions found: {len(caps)}')
        # Rough heuristic — chars in the "symbols & pictographs" range upward.
        # Useful for quickly confirming emoji survive the attributedBody parse.
        has_emoji_in_caps = sum(1 for c in caps.values()
                                if any(ord(ch) > 0x2600 for ch in c))
        print(f'      Captions containing emoji-range chars: {has_emoji_in_caps}')
        for i, cap in list(caps.items())[:8]:
            sl_dbg = slug(cap, mode=a.emoji)
            print(f'      [{i:03d}] cap={cap[:150]!r}')
            print(f'            slug={sl_dbg!r}')

        base = Path(a.output) / f'{san(a.contact)}_{tag}'
        att_dir = base / 'attachments'
        for d in (base, att_dir):
            d.mkdir(parents=True, exist_ok=True)
        print(f'[4/5] Writing to {base}')

        tx = []     # transcript lines
        mf = []     # manifest entries
        seq = 0     # 1-based message sequence number (stable across runs)
        pc = vc = fc = 0
        seen = set()  # filenames already written in this run (for uniq())

        for i, m in enumerate(msgs):
            seq += 1
            dt = mts(m[1]).astimezone()
            ts = dt.strftime('%Y-%m-%d %H:%M:%S %Z')
            sender = 'Me' if m[2] else (m[5] or a.contact)
            body = body_of(m)
            tx.append(f'[{seq:05d}] {ts}  |  {sender}')
            if body:
                tx.append(body)
            entry = {'seq': seq, 'ts': dt.isoformat(), 'sender': sender,
                     'body': body, 'att': []}

            for att in atts[m[0]]:
                fname, mime, xfer, rowid = att[0], att[1], att[2], att[3]
                xfer = xfer or f'att_{rowid}'
                ext = Path(xfer).suffix.lower()
                # Normalize .jpeg -> .jpg so output is a single canonical extension.
                if ext == '.jpeg':
                    ext = '.jpg'
                k = knd(mime, ext)
                if k in ('photo', 'video'):
                    stem = f'{seq:05d}_{slug(caps.get(i), mode=a.emoji)}'
                else:
                    stem = f'{seq:05d}_{san(Path(xfer).stem)}'
                src = (Path(fname.replace('~', str(Path.home()))).resolve()
                       if fname else None)
                dest = None
                converted = False
                if src and src.exists():
                    if k == 'photo':
                        dest, converted = sanitize_image(src, att_dir, stem, ext, seen)
                        if converted:
                            conv_n += 1
                        pc += 1
                    elif k == 'video':
                        dest = sanitize_video(src, att_dir, stem, ext, seen)
                        vc += 1
                    else:
                        dest = uniq(att_dir, stem, ext, seen)
                        shutil.copy2(src, dest)
                        fc += 1
                    res = (f'-> {dest.relative_to(base)}'
                           + (' [HEIC->JPG]' if converted else ''))
                else:
                    res = f'MISSING: {fname}'
                cap = caps.get(i, '')
                tx.append(f'  [{k.upper()}] {xfer} caption="{cap}" {res}')
                entry['att'].append({
                    'k': k, 'orig': xfer, 'cap': cap,
                    'saved': str(dest.relative_to(base)) if dest else None,
                    'converted': bool(converted) if k == 'photo' else None,
                })
            tx.append('')
            mf.append(entry)

        (base / 'transcript.txt').write_text('\n'.join(tx), encoding='utf-8')
        (base / 'manifest.json').write_text(
            json.dumps(mf, indent=2, ensure_ascii=False), encoding='utf-8')

    sl = s.astimezone().strftime('%Y-%m-%d %H:%M:%S %Z') if s else 'beginning'
    el = e.astimezone().strftime('%Y-%m-%d %H:%M:%S %Z') if e else 'now'
    out = ['=' * 40, 'Messages Export Summary', '=' * 40,
           f'Contact   : {a.contact}',
           f'Handles   : {", ".join(hh)}',
           f'Range     : {sl} -> {el}',
           f'Mode      : {"raw (forensic)" if a.raw else "sanitized"}',
           f'Messages  : {len(msgs)}',
           f'Photos    : {pc}',
           f'Videos    : {vc}',
           f'Other     : {fc}']
    if a.raw:
        out += [f'Errors    : {errors}',
                f'Exported  : {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}', '',
                'Naming    : [seq]_[YYYYMMDDTHHMMSS]_[sender]_[orig_filename]',
                '            [seq]_[YYYYMMDDTHHMMSS]_[sender].txt for body text',
                '',
                'Forensic  : original bytes preserved (no HEIC->JPG, no EXIF strip)',
                '            md5 + sha1 + sha256 + EXIF in metadata.json',
                '            chain_of_custody.log records every action with all 3 hashes', '',
                f'Version   : {__version__}',
                f'Output    : {base}']
    else:
        out += [f'HEIC->JPG : {conv_n}',
                f'Exported  : {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}', '',
                'Naming    : [seq]_[next message text].[ext]',
                '            [seq]_NO_TEXT.[ext] when no text follows', '',
                'Sanitized : EXIF/GPS stripped from images and videos', '',
                f'Version   : {__version__}',
                f'Output    : {base}']
    (base / 'summary.txt').write_text('\n'.join(out), encoding='utf-8')
    conn.close()
    print('[5/5] Done!\n')
    for line in out:
        print(line)


if __name__ == '__main__':
    main()
