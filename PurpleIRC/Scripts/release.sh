#!/bin/bash
# Formal release process for PurpleIRC. Run this from EITHER dev machine
# (Vortex or MB14) — it is machine-independent: it uses whatever Developer ID
# Application certificate and notarytool keychain profile that machine has set
# up locally (those live in each Mac's login Keychain and are NOT synced).
#
# PurpleIRC has no in-app auto-updater, so a "release" is simply:
#   a notarized + stapled .app, zipped, attached to a tagged GitHub release.
# Notarization is what lets someone download the zip on a clean Mac and open
# it without the "developer cannot be verified" Gatekeeper dialog.
#
# What this script does:
#   1. Pre-flight: clean working tree, on `main`, fully pushed, gh authed,
#      Developer ID cert present, notary profile present.
#   2. Builds PurpleIRC.app via build-app.sh with NOTARIZE_PROFILE set
#      (Developer ID sign + hardened runtime + timestamp + notarize + staple),
#      WITHOUT touching /Applications or stealing focus (--no-install).
#   3. Proves the result: `stapler validate` + a Gatekeeper assessment
#      (`spctl -a`), so a broken notarization fails the release loudly.
#   4. Zips the bundle → ~/Downloads/PurpleIRC release/PurpleIRC-<version>.zip
#      (ditto -c -k --keepParent, which preserves the signature).
#   5. Tags the commit `purpleirc-v<version>` and creates a GitHub release with
#      `gh`, uploading the zip and pulling notes from the CHANGELOG.
#
# Version is git-derived (1.0.<repo-commit-count>) — same derivation as
# build-app.sh — so there is no manual version bump; the release pins to
# whatever commit you run it on. Cut a release only from a committed, pushed
# state.
#
# Required (one-time per machine — see RELEASING.md):
#   NOTARIZE_PROFILE   notarytool keychain-profile name. Defaults to
#                      "PurpleIRC-Notary"; override via env if you named it
#                      something else. Set up with `xcrun notarytool
#                      store-credentials`.
#
# Optional:
#   GITHUB_REPO        Defaults to bronty13/PhantomLives.
#   ALLOW_DIRTY=1      Skip the clean-tree / pushed checks (NOT recommended;
#                      a release should be reproducible from origin).
#   ALLOW_UNNOTARIZED=1  Proceed even if no notary profile is found. The zip
#                      will trip Gatekeeper on clean Macs. For emergencies only.
#
# Output:
#   ~/Downloads/PurpleIRC release/PurpleIRC-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."

APP="PurpleIRC"
GITHUB_REPO="${GITHUB_REPO:-bronty13/PhantomLives}"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-PurpleIRC-Notary}"

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

# 1d. On main, clean, pushed — a release must be reproducible from origin.
if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    [ "$BRANCH" = "main" ] || die "not on main (on '$BRANCH'). Releases are cut from main. (ALLOW_DIRTY=1 to override.)"
    [ -z "$(git status --porcelain)" ] || die "working tree is dirty. Commit or stash first. (ALLOW_DIRTY=1 to override.)"
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
RELEASE_TAG="purpleirc-v${SHORT_VERSION}"

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
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP.app" "$ZIP_PATH"
echo "  Wrote $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

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
    printf '%s\n' "PurpleIRC $SHORT_VERSION" "" "See CHANGELOG.md for details." > "$NOTES_FILE"
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

echo
echo "== Done =="
echo "  Release:   https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
echo "  Artifact:  $ZIP_PATH"
echo "  Notarized: $NOTARIZED"
if [ "$NOTARIZED" = "yes" ]; then
    echo "  ↳ Anyone can download the zip and open it on a clean Mac — no Gatekeeper prompt."
else
    echo "  ↳ Downloaders must right-click → Open the first time (not notarized)."
fi
