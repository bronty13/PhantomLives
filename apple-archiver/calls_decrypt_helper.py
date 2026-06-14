#!/usr/bin/env python3
# =============================================================================
#   CALL-HISTORY DECRYPT HELPER  (opt-in, on-source-Mac, GUI-session only)
#   File:     calls_decrypt_helper.py
#   Version:  1.0.0
#   Requires: macOS, PyObjC (`pip3 install --user pyobjc-core pyobjc`)
#
#   The ONLY way to recover the phone number / FaceTime address in macOS call
#   history (it is AES-GCM encrypted at rest; see DECRYPTION.md). It needs TWO
#   capabilities at once, which is why it must run as a GUI-session agent WITH a
#   Full Disk Access grant:
#     1. UNLOCKED login keychain — only in the logged-in (Aqua) GUI session;
#        over SSH it's locked and every address comes back blank.
#     2. FULL DISK ACCESS for this binary (/usr/bin/python3) — else macOS TCC
#        blocks reading the call store and recentCalls() returns 0. Grant it in
#        System Settings → Privacy & Security → Full Disk Access (one-time, manual;
#        TCC.db is SIP-protected and can't be scripted).
#   Miss either and you get 0 calls or blank numbers — the warning below says which.
#
#   It is read-only: it reads Apple's already-decrypted in-memory call objects via
#   the private CallHistory.framework and writes a plain JSON sidecar. It NEVER
#   modifies the call database. Run it manually in a Terminal Rachel is logged into:
#
#       python3 calls_decrypt_helper.py --out ~/calls_decrypted.json
#
#   then let the normal Vortex pull fetch calls_decrypted.json and fold it into the
#   archive (callhistory_archiver merges it when present).
# =============================================================================
import argparse
import json
import sys
from datetime import datetime, timezone

APPLE_EPOCH = 978307200  # 2001-01-01 UTC; NSDate/Core-Data reference date


def _epoch(nsdate):
    """CHRecentCall.date() → unix epoch seconds (float), or None. This is the
    timezone-proof key the archiver matches on (it derives the same epoch from the
    DB's Core-Data ZDATE)."""
    if nsdate is None:
        return None
    try:
        return float(nsdate.timeIntervalSince1970())
    except Exception:
        return None


def _iso(nsdate):
    """CHRecentCall.date() → ISO-8601 UTC string (human-readable, for the sidecar)."""
    ts = _epoch(nsdate)
    if ts is None:
        return ''
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime('%Y-%m-%d %H:%M:%S')


def _service(provider, call_type):
    p = (str(provider) if provider is not None else '').lower()
    if 'facetime' in p:
        return 'FaceTime'
    if 'telephony' in p or 'phone' in p:
        return 'Phone'
    return {1: 'Phone', 8: 'FaceTime', 16: 'FaceTime Video'}.get(int(call_type or 0), 'Call')


def _handle_value(h):
    """Pull the address string out of a participant-handle object, trying the
    selectors Apple has used across versions."""
    for sel in ('value', 'stringValue', 'uri', 'address', 'destination', 'identifier'):
        try:
            if h.respondsToSelector_(sel):
                v = getattr(h, sel)()
                if v:
                    return str(v).strip()
        except Exception:
            continue
    return str(h).strip()


def load_calls():
    try:
        import objc
    except ImportError:
        sys.exit('PyObjC not installed. Run: pip3 install --user pyobjc-core pyobjc')

    objc.loadBundle('CallHistory', globals(),
                    '/System/Library/PrivateFrameworks/CallHistory.framework')
    CHManager = globals()['CHManager']
    mgr = None
    for ctor in ('sharedManager', 'sharedInstance'):
        if CHManager.respondsToSelector_(ctor):
            mgr = getattr(CHManager, ctor)(); break
    if mgr is None:
        mgr = CHManager.alloc().init()

    # Prefer callsWithPredicate:limit:offset:batchSize: — it returns the FULL
    # history; recentCalls() caps at the most recent 200. Fall back to recentCalls.
    calls = None
    if mgr.respondsToSelector_('callsWithPredicate:limit:offset:batchSize:'):
        try:
            calls = mgr.callsWithPredicate_limit_offset_batchSize_(None, 1_000_000, 0, 0)
        except Exception:
            calls = None
    if not calls:
        calls = mgr.recentCalls()
    if not calls:
        sys.stderr.write(
            'WARNING: 0 calls returned — the call store could not be read. This '
            'binary almost certainly lacks Full Disk Access. Grant it in System '
            'Settings -> Privacy & Security -> Full Disk Access, then re-run.\n')
        return []

    out, blank = [], 0
    for c in calls:
        def g(sel, default=None):
            try:
                return getattr(c, sel)() if c.respondsToSelector_(sel) else default
            except Exception:
                return default

        addrs = []
        handles = g('remoteParticipantHandles')
        if handles is not None:
            for h in handles:
                v = _handle_value(h)
                if v:
                    addrs.append(v)
        if not addrs:
            blank += 1

        orig = bool(g('originated') or g('isOutgoing') or g('outgoing'))
        answered = bool(g('answered'))
        out.append({
            'address': addrs[0] if addrs else '',
            'all_addresses': addrs,
            'epoch': _epoch(g('date')),
            'date': _iso(g('date')),
            'duration_seconds': float(g('duration') or 0),
            'service': _service(g('serviceProvider'), g('callType')),
            'direction': 'outgoing' if orig else 'incoming',
            'answered': answered,
            'missed': bool(not answered and not orig),
        })
    if blank:
        sys.stderr.write(
            f'WARNING: {blank}/{len(calls)} calls had NO address — the Call History '
            'key was not unlocked. Are you running this inside an unlocked GUI '
            'session (not SSH)?\n')
    return out


def main():
    ap = argparse.ArgumentParser(
        prog='calls_decrypt_helper',
        description='Dump decrypted call-history addresses (GUI-session only).')
    ap.add_argument('--out', required=True, help='output JSON path')
    a = ap.parse_args()
    calls = load_calls()
    with open(a.out, 'w', encoding='utf-8') as f:
        json.dump({'generated': datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S'),
                   'count': len(calls), 'calls': calls}, f, indent=2)
    got = sum(1 for c in calls if c['address'])
    print(f'Wrote {len(calls)} calls ({got} with a decrypted address) → {a.out}')


if __name__ == '__main__':
    main()
