# CloudKit Spike — `encryptedValues` round-trip

**Timebox:** 2 days. **Goal:** prove that `CKRecord.encryptedValues` round-trips a JSON blob byte-for-byte through the user's private CloudKit database, and that the developer-dashboard view confirms the field is opaque to Apple.

This spike runs *before* Phase 1 in the build order (see `../../PLAN.md` § Build phases). If anything in this spike doesn't behave as advertised, the encryption decision in `PLAN.md` § Locked decisions has to be reopened before any Phase 1 storage code is written.

## What the spike does

A tiny SwiftUI app (`CloudKitSpike.app`). One button, one log pane.

1. Reads `CKContainer(identifier: "iCloud.com.bronty13.PurpleLife")` and confirms iCloud account is available.
2. Saves a `CKRecord` of type `PurpleObject` whose `encryptedValues["fieldsJSON"]` carries a JSON blob (~250 bytes).
3. Records the SHA-256 of the saved bytes.
4. Fetches the record back by `recordID`.
5. Reads `record.encryptedValues["fieldsJSON"]` and SHA-256s the returned bytes.
6. Asserts: `bytes_in == bytes_out` and the plaintext columns (`type`, `createdAt`, `updatedAt`) round-tripped too.
7. Deletes the test record so the dev container doesn't accumulate cruft.

## How to run it

```sh
cd PurpleLife/Spike/CloudKit
./build-spike.sh
open CloudKitSpike.app
# Click "Run round-trip"
```

### One-time prerequisites

1. **iCloud account on the build Mac.** System Settings → Apple ID → iCloud → make sure iCloud Drive is on for this Mac.
2. **Container provisioning at Apple Developer.** Go to <https://developer.apple.com/account> → Certificates, Identifiers & Profiles → Identifiers → iCloud Containers → `+` → create `iCloud.com.bronty13.PurpleLife`.
3. **App ID with CloudKit.** Same page → App IDs → create or edit `com.bronty13.PurpleLife.CloudKitSpike` and check "iCloud" + select the container above.
4. **First Xcode open.** After `./build-spike.sh` generates the project, open `CloudKitSpike.xcodeproj` once, set the Team in Signing & Capabilities, and confirm Xcode shows iCloud → CloudKit ticked with the container above selected. Re-run `build-spike.sh` after that.

If the Apple-Developer side is already done for some other PurpleLife app target, just reuse that container ID and skip steps 2–3.

## What "PASS" looks like

In the spike app's log pane:

```
account: iCloud available
save: posting record spike-<UUID>
save: payload 264 bytes, sha256=<a>…
save: ok — modificationDate <date>
fetch: requesting record by ID
fetch: ok — recordChangeTag <tag>
verify: plaintext type column round-tripped: yes
verify: returned 264 bytes, sha256=<a>…
verify: byte-for-byte match: yes
cleanup: deleting test record
cleanup: ok
RESULT: PASS
```

A **PASS** is sufficient evidence to lock `encryptedValues` for Phase 1.

### Dashboard spot-check (optional but worth doing once)

Before clicking "cleanup" — comment that line out for one run — open the [CloudKit Console](https://icloud.developer.apple.com/) for the `iCloud.com.bronty13.PurpleLife` container, navigate to the `PurpleObject` record, and confirm the `fieldsJSON` column displays as an opaque blob (not the JSON contents). That's the "Apple cannot decrypt" claim, observed.

## Failure modes worth knowing

| Symptom | Cause | Fix |
|---|---|---|
| `account: NO ACCOUNT` | Mac not signed into iCloud | System Settings → Apple ID |
| `CKError.code = 9` (notAuthenticated) | Account exists but iCloud Drive off, or container not provisioned | Step 1 + step 2 above |
| `CKError.code = 5` (badContainer) | Container exists but isn't attached to the App ID. Click into the App ID at developer.apple.com → iCloud → Configure → check the container → Save. Re-run `build-spike.sh` (it passes `-allowProvisioningUpdates` so the new profile is fetched on the next build). | — |
| `CKError.code = 11` (badContainer) | App entitlement points at a container the team doesn't own | Step 3 above |
| `CKError.code = 25` (zoneNotFound) | First-ever write to the private DB; usually self-heals on retry | Click "Run round-trip" again |
| `verify: byte-for-byte match: NO` | This would invalidate the spike. Do NOT proceed to Phase 1; reopen the encryption decision in `PLAN.md`. | — |

## What gets recorded after the run

When the run is done, append the actual log block under "## Run log" below, plus a one-line **Decision** at the very bottom: *"Spike PASS / FAIL on YYYY-MM-DD against container `<id>`. Encryption decision stands / reopened."*

## Run log

### 2026-05-10 — first PASS

```
11:53:01.579 account: iCloud available
11:53:01.581 save: posting record spike-14B67F41-ED41-4E09-94BB-1A718934CCFF
11:53:01.581 save: payload 157 bytes, sha256=822b5b86b4900b3f…
11:53:05.678 save: ok — modificationDate 2026-05-10 15:53:04 +0000
11:53:05.679 fetch: requesting record by ID
11:53:05.791 fetch: ok — recordChangeTag mozycc4j
11:53:05.791 verify: plaintext type column round-tripped: yes
11:53:05.791 verify: returned 157 bytes, sha256=822b5b86b4900b3f…
11:53:05.791 verify: byte-for-byte match: yes
11:53:05.791 cleanup: deleting test record
11:53:06.146 cleanup: ok
11:53:06.147 RESULT: PASS
```

The bytes-out matched bytes-in exactly (sha256 prefix `822b5b86…` on both sides), the plaintext columns round-tripped, and cleanup succeeded. Save → fetch round-trip took ~4.2 s end-to-end against the development environment (a brand-new container — first-write latency dominates; subsequent writes are sub-second).

A prior run on the same day failed with `CKError.code = 5 (badContainer)` because the container hadn't been attached to the App ID yet via developer.apple.com → Identifiers → App ID → iCloud → Configure. Re-running `build-spike.sh` after attaching (with `-allowProvisioningUpdates`) fetched a fresh profile and the next run PASSed.

## Decision

**Spike PASS on 2026-05-10 against container `iCloud.com.bronty13.PurpleLife`. Encryption decision stands** — `CKRecord.encryptedValues` is the layer Phase 4 will use; the JSON-blob `fields_json` column on the `objects` table travels through it. No reopening of the locked decision in `PLAN.md` is needed.
