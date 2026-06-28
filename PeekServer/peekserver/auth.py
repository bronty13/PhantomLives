"""HTTP Basic Auth — gate the whole service so it isn't open on the LAN.

The password is stored only as a SHA-256 hash in the local (gitignored) config; the plaintext is
never persisted. Comparison is constant-time. Auth is OFF only if no user/hash is configured.
Basic Auth is sent base64 (not encrypted) — fine on a trusted home LAN; for stronger protection
put it behind a TLS reverse proxy.
"""
import base64
import hashlib
import hmac


def password_hash(plaintext: str) -> str:
    return hashlib.sha256(plaintext.encode("utf-8")).hexdigest()


def check_basic(authorization_header: str, user: str, pw_hash: str) -> bool:
    """True if the request is authorized. If no user/hash configured, auth is disabled (True)."""
    if not user or not pw_hash:
        return True                                   # not configured → open
    if not authorization_header or not authorization_header.startswith("Basic "):
        return False
    try:
        decoded = base64.b64decode(authorization_header[6:]).decode("utf-8", "replace")
    except Exception:
        return False
    u, sep, p = decoded.partition(":")
    if not sep:
        return False
    return hmac.compare_digest(u, user) and hmac.compare_digest(password_hash(p), pw_hash)
