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

## The catch: the two needed capabilities live in mutually-exclusive contexts

Decryption needs **two** things at once: (1) **Full Disk Access** to read the
TCC-protected CallHistory DB, and (2) an **unlocked login keychain** to release the
data key. We verified — by running the *same* probe in both contexts on Rachel's
Mac — that no single context we can reach has both:

| Context | Full Disk Access (read the DB) | Unlocked login keychain |
|---|---|---|
| **Our SSH login** (the pull) | ✅ yes — granted for photo archiving (`READ OK`, `recentCalls: 200`) | ❌ locked — *"User interaction is not allowed"*, handles blank |
| **Aqua LaunchAgent** (GUI session) | ❌ no — `Operation not permitted` reading the DB → `recentCalls: 0` | ✅ unlocked |

So the SSH path sees every call but no numbers; the GUI-agent path has the keychain
but is blocked by TCC from even reading the call store. (The earlier "ACL admits a
non-Apple binary?" unknown is moot — TCC blocks it first.)

## Conclusion

- **Offline / pulled-DB / over-SSH decryption is impossible by design.**
- **A GUI-session helper CAN decrypt — but only after a one-time Full Disk Access
  grant** to the binary that runs it (`/usr/bin/python3`, or better a dedicated
  helper app). That grant is a manual click in **System Settings → Privacy &
  Security → Full Disk Access** on the source Mac: TCC.db is SIP-protected and
  cannot be scripted. Once granted, the Aqua LaunchAgent has *both* capabilities
  and `recentCalls()` returns decrypted numbers.

## The opt-in path (helper staged on the source Mac, not enabled)

`calls_decrypt_helper.py` is deployed to the source Mac at
`~/Library/Application Support/PurpleAttic/` but **not loaded**. To enable:

1. On the source Mac, grant **Full Disk Access** to `/usr/bin/python3` (System
   Settings → Privacy & Security → Full Disk Access → add it). *Trade-off:* this is
   broad — any Python the user runs then has full-disk access. Tighter alternative:
   build a small codesigned helper app and grant FDA to only that.
2. Load the `com.bronty13.calls-decrypt.<id>` Aqua LaunchAgent
   (`launchctl bootstrap gui/<uid> …`); it writes `calls_decrypted.json`.
3. The Vortex calls pull fetches that sidecar and runs
   `callhistory_archiver.py --decrypted calls_decrypted.json` to fold the numbers in
   (matched on the raw call instant, timezone-proof).

**Why it's worth weighing, not automatic:** it puts a *running component* + a broad
FDA grant on the source Mac (vs. the strict "pull only" model), and for anyone the
user has **texted** the real number is already in the Messages + Contacts archives —
so the only numbers this newly recovers are *call-only* contacts (telemarketers,
one-off calls). Modest payoff; deliberate opt-in.
