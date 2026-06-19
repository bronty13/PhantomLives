#!/bin/bash
# Formal release process for PurpleDiary. Run from EITHER dev machine (Vortex or
# MB14) — it is machine-independent: it uses whatever Developer ID Application
# certificate and notarytool keychain profile that machine has set up locally
# (those live in each Mac's login Keychain and are NOT synced).
#
# PurpleDiary is a NO-NETWORK app: it has no in-app updater, no Sparkle, no
# appcast, no telemetry (see HANDOFF.md §6 and Docs/SECURITY.md — this is a hard
# product constraint). A "release" is therefore deliberately *passive*: a
# notarized, stapled .dmg attached to a tagged GitHub release. Users download and
# update by re-downloading. The app itself never phones home — nothing here adds
# network code to PurpleDiary; the only thing that touches the network is THIS
# script (the notarization round-trip + `gh`), running on your dev Mac.
#
# What this script does:
#   1. Pre-flight: Developer ID cert present, notary profile present, gh authed,
#      on `main`, the PurpleDiary subtree clean, HEAD pushed.
#   2. Builds PurpleDiary.app via build-app.sh --no-install (Developer ID sign +
#      hardened runtime + secure timestamp; no /Applications touch, no focus-steal).
#   3. Notarizes + staples the .app, then PROVES it (stapler validate + a
#      Gatekeeper `spctl` assessment) — a broken notarization fails loudly.
#   4. Builds a drag-to-Applications .dmg from the stapled app, signs it,
#      notarizes + staples the DMG, and proves THAT too. Two notarization passes
#      so the app is Gatekeeper-clean OFFLINE even after the user drags it out of
#      the DMG (see the comment at step 4).
#   5. Tags the commit `purplediary-v<version>` and creates a GitHub release with
#      `gh`, uploading the DMG and pulling notes from CHANGELOG.md.
#
# Version is git-derived (1.0.<repo-commit-count>) — identical to build-app.sh —
# so there is no manual version bump; the release pins to whatever commit you run
# it on. Cut a release only from a committed, pushed state.
#
# IMPORTANT — Keychain access: run this with the Bash sandbox DISABLED. The
# sandbox can't read the login Keychain, which makes notarytool/codesign report a
# false "profile not stored" / "no identity found". (Repo memory:
# feedback-release-sandbox-keychain.)
#
# Required (one-time per machine — see RELEASING.md):
#   NOTARIZE_PROFILE   notarytool keychain-profile name. Defaults to the shared
#                      "PurpleDedup-Notary" (one profile across all PhantomLives
#                      apps); override via env if you named it something else.
#                      Set up with `xcrun notarytool store-credentials`.
#
# Optional:
#   GITHUB_REPO          Defaults to bronty13/PhantomLives.
#   ALLOW_DIRTY=1        Skip the clean-tree / pushed checks (NOT recommended; a
#                        release should be reproducible from origin).
#   ALLOW_UNNOTARIZED=1  Proceed even if no notary profile is found. The DMG will
#                        trip Gatekeeper on clean Macs. For emergencies only.
#
# Output:
#   ~/Downloads/PurpleDiary release/PurpleDiary-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP="PurpleDiary"
GITHUB_REPO="${GITHUB_REPO:-bronty13/PhantomLives}"
NOTARIZE_PROFILE="${NOTARIZE_PROFILE:-PurpleDedup-Notary}"

die() { echo "FATAL: $*" >&2; exit 1; }
note() { echo "  • $*"; }

# ---------------------------------------------------------------------------
# 1. Pre-flight
# ---------------------------------------------------------------------------
echo "== Pre-flight =="

# 1a. Developer ID Application cert. Without it build-app.sh falls back to ad-hoc
# signing and notary rejects the bundle — there is no point cutting a release.
DEVID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -E '"Developer ID Application:' \
    | head -1 | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')"
[ -n "$DEVID" ] || die "no Developer ID Application certificate in the login keychain.
       \`security find-identity -v -p codesigning\` must list one.
       (If it IS installed but this fails, you're probably running under the Bash
       sandbox — disable it; the sandbox can't read the login Keychain.)
       See RELEASING.md → one-time setup."
note "signing identity: $DEVID"

# 1b. Notary profile must exist (unless explicitly overridden). Probe it with a
# cheap `notarytool history` call — it fails fast if the profile is missing.
if xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" >/dev/null 2>&1; then
    note "notary profile: $NOTARIZE_PROFILE ✓"
elif [ "${ALLOW_UNNOTARIZED:-0}" = "1" ]; then
    echo "  ! notary profile '$NOTARIZE_PROFILE' not found — ALLOW_UNNOTARIZED=1, continuing."
    echo "    The resulting DMG WILL trip Gatekeeper on clean Macs."
    NOTARIZE_PROFILE=""
else
    die "notarytool profile '$NOTARIZE_PROFILE' not found on this machine.
       This is a per-machine, one-time setup (it lives in the login Keychain,
       which doesn't sync between Vortex and MB14):

         xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" \\
             --apple-id <your-apple-id-email> \\
             --team-id  SRKV8T38CD \\
             --password <app-specific-password from appleid.apple.com>

       Full walkthrough in RELEASING.md. (Emergency escape: ALLOW_UNNOTARIZED=1.)
       (If the profile IS stored but this fails, disable the Bash sandbox — it
       can't read the login Keychain.)"
fi

# 1c. gh authenticated.
gh auth status >/dev/null 2>&1 || die "GitHub CLI not authenticated. Run \`gh auth login\`."
note "gh authenticated ✓"

# 1d. On main, clean, pushed — a release must be reproducible from origin.
# "Clean" is scoped to the PurpleDiary subtree (cwd): this is a polyglot
# monorepo, so untracked/modified files in *sibling* projects are normal and
# don't affect a PurpleDiary build's reproducibility.
if [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    [ "$BRANCH" = "main" ] || die "not on main (on '$BRANCH'). Releases are cut from main. (ALLOW_DIRTY=1 to override.)"
    [ -z "$(git status --porcelain -- .)" ] || die "PurpleDiary has uncommitted changes:
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
RELEASE_TAG="purplediary-v${SHORT_VERSION}"

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
DMG_NAME="${APP}-${SHORT_VERSION}.dmg"
DMG_PATH="$OUT_DIR/$DMG_NAME"

# ---------------------------------------------------------------------------
# 3. Build (Developer ID sign + hardened runtime + timestamp), no install
# ---------------------------------------------------------------------------
echo
echo "== Build =="
SHORT_VERSION="$SHORT_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    ./build-app.sh --no-install
[ -d "$APP.app" ] || die "build-app.sh did not produce ./$APP.app"

# Confirm build-app.sh actually used the Developer ID (not ad-hoc) — ad-hoc can't
# be notarized, so catch it now rather than after a wasted notary round-trip.
if [ -n "${NOTARIZE_PROFILE:-}" ]; then
    codesign -dvv "$APP.app" 2>&1 | grep -q "Authority=Developer ID Application" \
        || die "$APP.app is not Developer-ID-signed (ad-hoc?). Notarization would fail.
       Ensure the Developer ID cert is in the login Keychain and re-run."
fi

# ---------------------------------------------------------------------------
# 4. Notarize + staple the APP, then prove it.
# ---------------------------------------------------------------------------
# Why notarize the app AND (below) the DMG: stapling writes the notarization
# ticket INTO the bundle so first launch works OFFLINE. You can only staple a
# writable bundle — once the app is sealed in the read-only DMG it's too late. So
# we staple the app here, build the DMG from the stapled app, then staple the DMG
# too. Result: the DMG opens clean, and the app stays clean even after the user
# drags it out — no "developer cannot be verified" prompt, online or off.
echo
echo "== Notarize app =="
NOTARIZED="no"
if [ -n "$NOTARIZE_PROFILE" ]; then
    APP_ZIP="$(mktemp -d)/$APP.zip"
    ditto -c -k --keepParent "$APP.app" "$APP_ZIP"
    echo "  Submitting $APP.app to Apple notary (this can take a few minutes)…"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARIZE_PROFILE" --wait \
        | tee /tmp/purplediary-notarize-app.log | sed 's/^/      /'
    grep -q "status: Accepted" /tmp/purplediary-notarize-app.log \
        || die "app notarization was not Accepted. Inspect /tmp/purplediary-notarize-app.log;
       \`xcrun notarytool log <submission-id> --keychain-profile $NOTARIZE_PROFILE\` shows why."
    rm -rf "$(dirname "$APP_ZIP")"
    xcrun stapler staple "$APP.app" >/dev/null \
        || die "stapler staple failed on $APP.app despite an Accepted notarization."
    xcrun stapler validate "$APP.app" >/dev/null 2>&1 \
        || die "stapler validate failed — $APP.app is not stapled."
    note "app notarized + stapled ✓"
    if spctl -a -vvv -t exec "$APP.app" 2>&1 | grep -q 'accepted'; then
        note "spctl exec assessment: accepted ✓"
        NOTARIZED="yes"
    else
        echo "  ! spctl did not report 'accepted' for the app — proceeding, but inspect:"
        spctl -a -vvv -t exec "$APP.app" 2>&1 | sed 's/^/      /' || true
    fi
fi

# ---------------------------------------------------------------------------
# 5. Build the DMG (drag-to-/Applications layout), sign it.
# ---------------------------------------------------------------------------
echo
echo "== Package DMG =="
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)/dmg"
mkdir -p "$STAGING"
# ditto preserves the (now-stapled) signature; a plain cp can drop xattrs.
ditto "$APP.app" "$STAGING/$APP.app"
ln -s /Applications "$STAGING/Applications"   # the drag target
hdiutil create \
    -volname "$APP $SHORT_VERSION" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -format UDZO \
    -ov "$DMG_PATH" >/dev/null
rm -rf "$(dirname "$STAGING")"
# Sign the DMG container so the staple attaches to signed code.
codesign --sign "$DEVID" --timestamp --force "$DMG_PATH" \
    || die "codesign failed on the DMG."
echo "  Wrote $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

# ---------------------------------------------------------------------------
# 6. Notarize + staple the DMG, then prove it.
# ---------------------------------------------------------------------------
if [ -n "$NOTARIZE_PROFILE" ]; then
    echo
    echo "== Notarize DMG =="
    echo "  Submitting $DMG_NAME to Apple notary…"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARIZE_PROFILE" --wait \
        | tee /tmp/purplediary-notarize-dmg.log | sed 's/^/      /'
    grep -q "status: Accepted" /tmp/purplediary-notarize-dmg.log \
        || die "DMG notarization was not Accepted. Inspect /tmp/purplediary-notarize-dmg.log."
    xcrun stapler staple "$DMG_PATH" >/dev/null \
        || die "stapler staple failed on the DMG despite an Accepted notarization."
    xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1 \
        || die "stapler validate failed — the DMG is not stapled."
    note "DMG notarized + stapled ✓"
    # Gatekeeper assessment for a DMG uses the -t open / primary-signature context.
    if spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" 2>&1 | grep -q 'accepted'; then
        note "spctl open assessment: accepted ✓"
    else
        echo "  ! spctl did not report 'accepted' for the DMG — inspect:"
        spctl -a -vvv -t open --context context:primary-signature "$DMG_PATH" 2>&1 | sed 's/^/      /' || true
    fi
fi

# ---------------------------------------------------------------------------
# 7. Tag + GitHub release
# ---------------------------------------------------------------------------
echo
echo "== GitHub release =="
# Pull the CHANGELOG section for the notes: prefer a heading naming this exact
# version; otherwise fall back to "[Unreleased]"; otherwise a generic pointer.
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
    printf '%s\n' "$APP $SHORT_VERSION" "" "See CHANGELOG.md for details." > "$NOTES_FILE"
    note "no matching CHANGELOG section — using generic notes"
fi
{
    printf '\n\n---\n'
    printf '**Install:** open the DMG, drag **%s** to Applications.\n\n' "$APP"
    if [ "$NOTARIZED" = yes ]; then
        printf 'Notarized by Apple — opens on any Mac with no Gatekeeper prompt. '
        printf 'PurpleDiary is a **no-network** app: there is no in-app updater, so '
        printf 'to update, download the latest DMG here and re-drag it over the old app.\n'
    else
        printf '⚠️ NOT notarized — on first launch, right-click the app → **Open**.\n'
    fi
} >> "$NOTES_FILE"

gh release create "$RELEASE_TAG" \
    --repo "$GITHUB_REPO" \
    --title "$APP $SHORT_VERSION" \
    --notes-file "$NOTES_FILE" \
    --target "$(git rev-parse HEAD)" \
    "$DMG_PATH#$DMG_NAME"
rm -f "$NOTES_FILE"

echo
echo "== Done =="
echo "  Release:   https://github.com/$GITHUB_REPO/releases/tag/$RELEASE_TAG"
echo "  Artifact:  $DMG_PATH"
echo "  Notarized: $NOTARIZED"
if [ "$NOTARIZED" = "yes" ]; then
    echo "  ↳ Anyone can download the DMG and open it on a clean Mac — no Gatekeeper prompt."
else
    echo "  ↳ Direct downloaders must right-click → Open the first time (not notarized)."
fi
echo "  No auto-update by design — PurpleDiary makes no network requests; users re-download to update."
