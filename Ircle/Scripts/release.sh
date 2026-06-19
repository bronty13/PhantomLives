#!/bin/bash
# Formal release process for Ircle. Run this from EITHER dev machine
# (Vortex or MB14) — it is machine-independent: it uses whatever Developer ID
# Application certificate and notarytool keychain profile that machine has set
# up locally (those live in each Mac's login Keychain and are NOT synced).
#
# Ircle auto-updates via Sparkle 2. A "release" is a notarized + stapled
# .app, zipped, EdDSA-signed, attached to a tagged GitHub release, and announced
# in appcast.xml — which is what makes existing installs offer the update. The
# zip is also independently usable: notarization lets someone download it on a
# clean Mac and open it without the "developer cannot be verified" dialog.
#
# What this script does:
#   1. Pre-flight: clean working tree, on `main`, fully pushed, gh authed,
#      Developer ID cert present, notary profile present, SPARKLE_PUBLIC_KEY set.
#   2. Builds Ircle.app via build-app.sh with NOTARIZE_PROFILE +
#      SPARKLE_PUBLIC_KEY set (Developer ID sign + hardened runtime + timestamp
#      + notarize + staple, public update key embedded), WITHOUT touching
#      /Applications or stealing focus (--no-install).
#   3. Proves the result: `stapler validate` + a Gatekeeper assessment
#      (`spctl -a`), so a broken notarization fails the release loudly.
#   4. Zips the bundle → ~/Downloads/Ircle release/Ircle-<version>.zip
#      (ditto -c -k --keepParent, which preserves the signature) and EdDSA-signs
#      it with Sparkle's `sign_update` (private key read from the Keychain).
#   5. Tags the commit `ircle-v<version>` and creates a GitHub release with
#      `gh`, uploading the zip and pulling notes from the CHANGELOG.
#   6. Prepends a new <item> to appcast.xml and commits + pushes it, so the
#      update goes live the moment the push lands.
#
# Version is git-derived (1.0.<repo-commit-count>) — same derivation as
# build-app.sh — so there is no manual version bump; the release pins to
# whatever commit you run it on. Cut a release only from a committed, pushed
# state.
#
# Required (one-time per machine — see RELEASING.md):
#   NOTARIZE_PROFILE   notarytool keychain-profile name. Defaults to
#                      "PurpleDedup-Notary"; override via env if you named it
#                      something else. Set up with `xcrun notarytool
#                      store-credentials`.
#   SPARKLE_PUBLIC_KEY The EdDSA public key (output of Sparkle's `generate_keys`),
#                      exported in your shell rc. build-app.sh embeds it; the
#                      matching PRIVATE key must be in this Mac's Keychain so
#                      `sign_update` can sign the zip. Both Macs share ONE
#                      keypair — see RELEASING.md (export/import).
#
# Optional:
#   GITHUB_REPO        Defaults to bronty13/PhantomLives.
#   ALLOW_DIRTY=1      Skip the clean-tree / pushed checks (NOT recommended;
#                      a release should be reproducible from origin).
#   ALLOW_UNNOTARIZED=1  Proceed even if no notary profile is found. The zip
#                      will trip Gatekeeper on clean Macs. For emergencies only.
#
# Output:
#   ~/Downloads/Ircle release/Ircle-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP="Ircle"
GITHUB_REPO="${GITHUB_REPO:-bronty13/PhantomLives}"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-PurpleDedup-Notary}"

die() { echo "FATAL: $*" >&2; exit 1; }
note() { echo "  • $*"; }

# ---------------------------------------------------------------------------
# 1. Pre-flight
# ---------------------------------------------------------------------------
echo "== Pre-flight =="

# 1a. Developer ID Application cert. Without it the bundle is ad-hoc-signed
# and notary rejects it — there is no point cutting a release.
DEVID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '"Developer ID Application:' \
    | head -1 | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')"
[ -n "$DEVID" ] || die "no Developer ID Application certificate in the login keychain.
       \`security find-identity -v -p codesigning\` must list one.
       See RELEASING.md → one-time setup."
note "signing identity: $DEVID"

# 1b. Notary profile must exist (unless explicitly overridden). Probe it with a
# cheap `notarytool history` call — it fails fast if the profile is missing.
if xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" >/dev/null 2>&1; then
    note "notary profile: $NOTARIZE_PROFILE ✓"
elif [ "${ALLOW_UNNOTARIZED:-0}" = "1" ]; then
    echo "  ! notary profile '$NOTARIZE_PROFILE' not found — ALLOW_UNNOTARIZED=1, continuing."
    echo "    The resulting zip WILL trip Gatekeeper on clean Macs."
    NOTARIZE_PROFILE=""
else
    die "notarytool profile '$NOTARIZE_PROFILE' not found on this machine.
       This is a per-machine, one-time setup (it lives in the login Keychain,
       which doesn't sync between Vortex and MB14):

         xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" \\
             --apple-id <your-apple-id-email> \\
             --team-id  SRKV8T38CD \\
             --password <app-specific-password from appleid.apple.com>

       Full walkthrough in RELEASING.md. (Emergency escape: ALLOW_UNNOTARIZED=1.)"
fi

# 1c. gh authenticated.
gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run \`gh auth login\`."
note "gh authenticated ✓"

# 1e. Sparkle EdDSA public key set (build-app.sh embeds it) and the sign_update
# tool present. The matching private key must be in the Keychain — that's
# verified for real when sign_update runs (step 5b); a missing/placeholder
# public key is caught here before we spend a notarization round-trip.
if [ -z "${SPARKLE_PUBLIC_KEY:-}" ] || [ "${SPARKLE_PUBLIC_KEY}" = "PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY" ]; then
    die "SPARKLE_PUBLIC_KEY is unset (or still the placeholder). Auto-updates need
       the EdDSA keypair. One-time setup (see RELEASING.md):
         SPARKLE_BIN=\"\$(find .build/artifacts/sparkle/Sparkle/bin -maxdepth 1 -type d | head -1)\"
         \"\$SPARKLE_BIN/generate_keys\"          # private→Keychain, prints public
         export SPARKLE_PUBLIC_KEY=\"<public key>\"  # add to ~/.zshrc
       On the SECOND Mac, import the SAME private key (generate_keys -x / -f)."
fi
SPARKLE_BIN="$(find .build/artifacts/sparkle/Sparkle/bin -maxdepth 1 -type d 2>/dev/null | head -1)"
[ -x "$SPARKLE_BIN/sign_update" ] || die "Sparkle's sign_update not found under
       .build/artifacts. Run \`swift package resolve\` first."
# The private key in THIS Mac's Keychain must be the same keypair as
# SPARKLE_PUBLIC_KEY, or the published zip gets signed with a key the
# installed apps don't trust and every update fails with "improperly
# signed" — sign_update succeeding is NOT proof of the right key.
# (Incident: the 1.0.764 appcast item was signed with a stray local key
# and had to be pulled from the feed, 2026-06-09.)
KEYCHAIN_PUB="$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null || true)"
if [ "$KEYCHAIN_PUB" != "$SPARKLE_PUBLIC_KEY" ]; then
    die "Sparkle key mismatch — the Keychain's private key does not match
       SPARKLE_PUBLIC_KEY, so installed apps would reject the update as
       improperly signed.
         Keychain public half:  ${KEYCHAIN_PUB:-<none — no key in Keychain>}
         SPARKLE_PUBLIC_KEY:    $SPARKLE_PUBLIC_KEY
       Import the canonical private key from the Mac that has it:
         on that Mac:  \"\$SPARKLE_BIN/generate_keys\" -x /tmp/sparkle_key.pem
         on this Mac:  \"\$SPARKLE_BIN/generate_keys\" -f /tmp/sparkle_key.pem
       See RELEASING.md → 'Both Macs must hold the SAME key'."
fi
note "Sparkle public key set; Keychain private key matches ✓"

# 1d. On main, clean, pushed — a release must be reproducible from origin.
# "Clean" is scoped to the Ircle subtree (cwd): this is a polyglot monorepo,
# so untracked/modified files in *sibling* projects (stray DBs, nested repos,
# scratch scripts) are normal and don't affect a Ircle build's
# reproducibility. Tracked-or-untracked changes *inside Ircle/* still block.
if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    [ "$BRANCH" = "main" ] || die "not on main (on '$BRANCH'). Releases are cut from main. (ALLOW_DIRTY=1 to override.)"
    [ -z "$(git status --porcelain -- .)" ] || die "Ircle has uncommitted changes:
$(git status --short -- . | sed 's/^/         /')
       Commit or stash them first. (ALLOW_DIRTY=1 to override.)"
    git fetch origin main --quiet
    LOCAL="$(git rev-parse @)"; REMOTE="$(git rev-parse @{u} 2>/dev/null || echo none)"
    [ "$LOCAL" = "$REMOTE" ] || die "HEAD is not pushed to origin/main (local $LOCAL ≠ remote $REMOTE).
       Push first so the release tag points at a commit on origin. (ALLOW_DIRTY=1 to override.)"
    note "on main, clean, pushed ✓"
else
    echo "  ! ALLOW_DIRTY=1 — skipping clean-tree / pushed checks (release may not be reproducible)."
fi

# ---------------------------------------------------------------------------
# 2. Version (git-derived, identical to build-app.sh)
# ---------------------------------------------------------------------------
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"
RELEASE_TAG="ircle-v${SHORT_VERSION}"

echo
echo "== Releasing $APP $SHORT_VERSION (build $BUILD_NUMBER, tag $RELEASE_TAG) =="

# Refuse to clobber an existing release/tag — version is the commit count, so
# re-running on the same commit would collide.
if git rev-parse -q --verify "refs/tags/$RELEASE_TAG" >/dev/null \
   || gh release view "$RELEASE_TAG" --repo "$GITHUB_REPO" >/dev/null 2>&1; then
    die "release/tag $RELEASE_TAG already exists. Make a new commit (which bumps the
       version) before cutting another release, or delete the existing one first."
fi

OUT_DIR="$HOME/Downloads/$APP release"
mkdir -p "$OUT_DIR"
ZIP_NAME="${APP}-${SHORT_VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

# ---------------------------------------------------------------------------
# 3. Build + notarize + staple (no install, no focus-steal)
# ---------------------------------------------------------------------------
echo
echo "== Build + notarize =="
SHORT_VERSION="$SHORT_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    CODESIGN_IDENTITY="$DEVID" \
    NOTARIZE_PROFILE="$NOTARIZE_PROFILE" \
    SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
    ./build-app.sh --no-install

# ---------------------------------------------------------------------------
# 4. Prove it — stapled ticket + Gatekeeper assessment
# ---------------------------------------------------------------------------
echo
echo "== Verify =="
NOTARIZED="no"
if [ -n "$NOTARIZE_PROFILE" ]; then
    xcrun stapler validate "$APP.app" >/dev/null 2>&1 \
        || die "stapler validate failed — the bundle is NOT notarized/stapled.
       Inspect /tmp/notarize.plist (and /tmp/notarize.log) for the verdict."
    note "stapler validate ✓"
    # Gatekeeper would accept this for execution on a clean Mac.
    if spctl -a -vvv -t exec "$APP.app" 2>&1 | grep -q 'accepted'; then
        note "spctl assessment: accepted ✓"
        NOTARIZED="yes"
    else
        echo "  ! spctl did not report 'accepted' — proceeding, but inspect:"
        spctl -a -vvv -t exec "$APP.app" 2>&1 | sed 's/^/      /' || true
    fi
fi

# ---------------------------------------------------------------------------
# 5. Zip (ditto preserves the signature; plain `zip` would break it)
# ---------------------------------------------------------------------------
echo
echo "== Package =="
# Strip extended attributes BEFORE zipping, and zip with --norsrc --noextattr.
# Why: codesign leaves a `com.apple.provenance` xattr on every bundle file. A
# plain `ditto -c -k` stores those xattrs as AppleDouble (`._name`) entries in
# the zip. macOS's own extractors (ditto / Archive Utility) merge and remove
# them, but `unzip` and various third-party/browser extractors DON'T — they drop
# `._Autoupdate`, `._Sparkle`, … into Sparkle.framework's root, which Gatekeeper
# then rejects as "unsealed contents present in the root directory of an embedded
# framework" (the malware/"cannot verify" prompt). Stripping xattrs first makes
# the zip carry no AppleDouble at all, so EVERY extractor yields a clean,
# Gatekeeper-valid bundle. The notarization staple is NOT an xattr and survives.
# (Incident: Ircle 1.0.979 — first release tripped this on a fresh Mac.)
rm -f "$ZIP_PATH"
CLEAN_APP_DIR="$(mktemp -d)/$APP.app"
ditto --noextattr --norsrc "$APP.app" "$CLEAN_APP_DIR"
xattr -cr "$CLEAN_APP_DIR" 2>/dev/null || true
ditto -c -k --keepParent --norsrc --noextattr "$CLEAN_APP_DIR" "$ZIP_PATH"
rm -rf "$(dirname "$CLEAN_APP_DIR")"
echo "  Wrote $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# 5a. Extractor-agnostic gate: a release zip is only good if a NON-Apple
# extractor also yields a Gatekeeper-valid bundle. Extract with `unzip` (the
# extractor most likely to leave AppleDouble detritus) and assert no `._*` files
# landed in the framework, the staple still validates, and strict codesign
# passes. This is the exact failure mode that shipped in 1.0.979 — fail the
# release loudly here rather than ship another bundle that trips Gatekeeper.
echo "  Verifying the zip survives a non-Apple extractor (unzip)…"
GATE_DIR="$(mktemp -d)"
( cd "$GATE_DIR" && unzip -q "$ZIP_PATH" ) || die "could not unzip the release zip for verification."
GATE_APP="$GATE_DIR/$APP.app"
GATE_DETRITUS="$(find "$GATE_APP/Contents/Frameworks" -name '._*' 2>/dev/null | wc -l | tr -d ' ')"
[ "$GATE_DETRITUS" = "0" ] || die "release zip leaves $GATE_DETRITUS AppleDouble (._*) file(s) in Frameworks/
       after a plain unzip — Gatekeeper will reject this on a clean Mac. The
       xattr-strip step above did not fully clean the bundle."
xcrun stapler validate "$GATE_APP" >/dev/null 2>&1 \
    || die "release zip fails stapler validate after unzip — notarization ticket missing."
codesign --verify --deep --strict "$GATE_APP" 2>/tmp/gate-codesign.err \
    || die "release zip fails strict codesign after unzip:
$(sed 's/^/         /' /tmp/gate-codesign.err)
       This is the 'unsealed contents in embedded framework' failure. Do not ship."
rm -rf "$GATE_DIR"
note "extractor-agnostic gate passed (unzip → no ._* detritus, stapled, strict-valid) ✓"

# 5b. EdDSA-sign the zip. `sign_update` reads the private key from the Keychain
# and prints the `sparkle:edSignature="…" length="…"` fragment that goes in the
# appcast <enclosure>. A failure here means the private key isn't on this Mac.
SIGN_FRAGMENT="$("$SPARKLE_BIN/sign_update" "$ZIP_PATH" 2>/tmp/sign_update.err)" \
    || die "sign_update failed — the EdDSA PRIVATE key isn't in this Mac's Keychain.
       $(cat /tmp/sign_update.err 2>/dev/null)
       The public key is set but the private half lives in the Keychain and
       doesn't sync between Macs. Import it (generate_keys -f) — see RELEASING.md."
note "EdDSA-signed: $SIGN_FRAGMENT"

# ---------------------------------------------------------------------------
# 6. Tag + GitHub release
# ---------------------------------------------------------------------------
echo
echo "== GitHub release =="
# Pull the CHANGELOG section for the release notes. Prefer a heading that names
# this exact version; otherwise fall back to the "[Unreleased]" section (where
# work sits until it's tagged), then to a generic pointer. `awk` prints from
# the matching `## ` heading up to (but not including) the next `## `.
extract_section() {  # $1 = needle to match in a `## ` heading
    awk -v needle="$1" '
        /^## / { if (grab) exit; if (index($0, needle)) { grab=1; print; next } }
        grab { print }
    ' CHANGELOG.md
}
NOTES_FILE="$(mktemp)"
if extract_section "$SHORT_VERSION" > "$NOTES_FILE" && [ -s "$NOTES_FILE" ]; then
    note "release notes pulled from CHANGELOG.md heading matching $SHORT_VERSION"
elif extract_section "[Unreleased]" > "$NOTES_FILE" && [ -s "$NOTES_FILE" ]; then
    note "release notes pulled from CHANGELOG.md [Unreleased] section"
    echo "    (tip: rename '## [Unreleased]' to '## [$SHORT_VERSION]' in CHANGELOG.md to pin it)"
else
    printf '%s\n' "Ircle $SHORT_VERSION" "" "See CHANGELOG.md for details." > "$NOTES_FILE"
    note "no matching CHANGELOG section — using generic notes"
fi
printf '\n\n---\nNotarized: %s — %s\n' "$NOTARIZED" \
    "$([ "$NOTARIZED" = yes ] && echo 'Gatekeeper-clean, opens on any Mac' \
        || echo 'NOT notarized — right-click → Open on first launch')" >> "$NOTES_FILE"

gh release create "$RELEASE_TAG" \
    --repo "$GITHUB_REPO" \
    --title "$APP $SHORT_VERSION" \
    --notes-file "$NOTES_FILE" \
    --target "$(git rev-parse HEAD)" \
    "$ZIP_PATH#$ZIP_NAME"
rm -f "$NOTES_FILE"

# ---------------------------------------------------------------------------
# 7. Announce in appcast.xml — prepend the <item>, commit, push
# ---------------------------------------------------------------------------
echo
echo "== Appcast =="
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${ZIP_NAME}"
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
ITEM_FILE="$(mktemp)"
# sparkle:version carries the build number (commit count + sha) for diagnostics;
# Sparkle compares the leading numeric component, so 1.0.<count> ordering holds.
cat > "$ITEM_FILE" <<EOF
        <item>
            <title>$APP $SHORT_VERSION</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[See CHANGELOG.md for details.]]></description>
            <enclosure
                url="${DOWNLOAD_URL}"
                ${SIGN_FRAGMENT}
                type="application/octet-stream" />
        </item>
EOF
# Insert as the FIRST <item> (newest-first). If no items exist yet, insert just
# before </channel>. awk emits the new item at whichever marker comes first.
awk -v itemfile="$ITEM_FILE" '
    function emit() { while ((getline line < itemfile) > 0) print line; close(itemfile); done=1 }
    /^[[:space:]]*<item>/ && !done { emit() }
    /<\/channel>/ && !done       { emit() }
    { print }
' appcast.xml > appcast.xml.new && mv appcast.xml.new appcast.xml
rm -f "$ITEM_FILE"
# Validate XML before committing — a malformed feed breaks Sparkle for everyone.
xmllint --noout appcast.xml 2>/dev/null || die "appcast.xml is malformed after insert — NOT committing. Inspect it by hand."
note "prepended <item> for $SHORT_VERSION to appcast.xml ✓"

git add appcast.xml
git commit -q -m "$APP $SHORT_VERSION: appcast"
git push -q origin main
note "appcast committed + pushed — update is live"

echo
echo "== Done =="
echo "  Release:   https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
echo "  Artifact:  $ZIP_PATH"
echo "  Notarized: $NOTARIZED"
echo "  Auto-update: live — existing installs see $SHORT_VERSION on next launch (or within 24h)."
if [ "$NOTARIZED" = "yes" ]; then
    echo "  ↳ Anyone can also download the zip and open it on a clean Mac — no Gatekeeper prompt."
else
    echo "  ↳ Direct downloaders must right-click → Open the first time (not notarized)."
fi
