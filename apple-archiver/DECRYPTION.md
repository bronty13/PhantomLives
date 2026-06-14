# Call-history address decryption — investigation & conclusion

**Question (from the maintainer):** can we recover the *phone numbers / FaceTime
addresses* in Rachel's call history? On her macOS 12 (Monterey) Mac the
`ZADDRESS` and `ZNAME` columns of `CallHistory.storedata` are not plaintext —
the archiver shows them as `(encrypted)`.

**Short answer:** the metadata (when, how long, Phone vs FaceTime, direction,
answered/missed, country) is fully recoverable and already archived. The
**address/number itself is encrypted at rest and cannot be decrypted from a
pulled copy of the database** — only from inside Rachel's *unlocked, logged-in
GUI session*. We can build an opt-in on-Mac helper for that, but it breaks the
"pull only, run nothing on the source" model, so it's left disabled pending a
decision.

## What the data looks like

`ZADDRESS` / `ZNAME` are 44-byte opaque blobs whose length tracks the plaintext
length — the signature of **AES-GCM**: `ciphertext ‖ 16-byte IV ‖ 16-byte tag`.
The symmetric key is the *"Call History User Data Key"*, stored in the source
Mac's **login keychain** and released only to a process running in an
interactive (Aqua) session.

## What we tried (offline / over our existing SSH pull)

1. **Decode the blob directly** — not possible without the key. Confirmed AES-GCM
   shape; no key material is in the database file.
2. **Read the key from the keychain over SSH** — the login keychain is locked in
   a non-interactive SSH session, so any key fetch returns *"User interaction is
   not allowed."*
3. **Let Apple's own framework do the decryption, over SSH** — the decisive test.
   Using `CallHistory.framework` via PyObjC on Rachel's Mac:

   ```python
   import objc
   objc.loadBundle('CallHistory', globals(),
                   '/System/Library/PrivateFrameworks/CallHistory.framework')
   CHManager = globals()['CHManager']
   m = None
   for ctor in ('sharedManager', 'sharedInstance'):
       if CHManager.respondsToSelector_(ctor):
           m = getattr(CHManager, ctor)(); break
   if m is None:
       m = CHManager.alloc().init()
   calls = m.recentCalls()         # → 200 CHRecentCall objects, even over SSH
   ```

   Every call object came back, and all the **non-sensitive** fields read fine:

   | selector | meaning | observed |
   |---|---|---|
   | `date()` | call time | real `NSDate` |
   | `duration()` | seconds | real float |
   | `serviceProvider()` | service | `com.apple.Telephony` (145) / `com.apple.FaceTime` (55) |
   | `callType()` | service code | `1` = Phone, `8` = FaceTime |
   | `callCategory()` | category | `1` / `2` (mirrors service) |
   | `handleType()` | address kind | `2` = phone number (197), `3` = email/FaceTime id (3) |
   | `answered()`, `read()` | flags | booleans |
   | `remoteParticipantHandles()` | **the number/address** | **EMPTY for all 200** |

   The number lives in `remoteParticipantHandles`, and it was empty for **every**
   call, accompanied by exactly one diagnostic line:

   > `Failed to get Call History User Data Key from keychain — User interaction is not allowed.`

   So the framework *tries* to decrypt and populate the handles, fails to unlock
   the key in the SSH session, and returns the objects with their addresses
   blanked. This is a **keychain-session lock, not an app-ACL denial** — i.e. the
   same call in an unlocked GUI session would populate the handles.

## Conclusion

- **Offline / pulled-DB / over-SSH decryption is impossible by design.** The key
  is gated behind an interactive session; nothing about the pulled file changes
  that.
- **In Rachel's unlocked GUI session, decryption almost certainly works** via
  `recentCalls()` → `remoteParticipantHandles[].value`. One unknown remains
  unverified: whether the keychain item's ACL admits a *non-Apple* binary (our
  Python) even in a GUI session. The only way to know is to run it there once.

## The opt-in path (not enabled)

A small helper — `calls_decrypt_helper.py` — is included but **not deployed**. It
must run **inside Rachel's logged-in GUI session** (a Terminal window she's
logged into, or a per-user LaunchAgent with `LimitLoadToSessionType = Aqua`).
It calls `recentCalls()`, reads each handle's value + the matching metadata, and
writes `calls_decrypted.json` for the normal Vortex pull to fold into the
archive. Trade-offs to weigh before enabling:

- It puts a *running component* on the source Mac — a departure from the strict
  "pull only, the source does nothing but `rsync`/`.backup`" guarantee.
- If the key's ACL rejects non-Apple readers, it returns nothing and we've lost
  nothing.
- For anyone Rachel has **texted**, the real number is already in the Messages +
  Contacts archives — so the only addresses this would newly recover are
  *call-only* numbers (telemarketers, one-off calls, etc.). The practical payoff
  is modest; that's why it's opt-in.

**Recommendation:** keep call history archived **metadata-only** (current
behavior) unless the maintainer specifically wants call-only numbers, in which
case enable the GUI-session helper and verify it on one run.
