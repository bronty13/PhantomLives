#!/bin/bash
# Build, package, sign, and stage a Sparkle release of PurpleDedup. Steps:
#
#   1. Run `./build-app.sh` with the public Sparkle EdDSA key embedded in the
#      Info.plist (so the SHIPPED build can verify future updates).
#   2. ditto -c -k --keepParent → PurpleDedup-<version>.zip
#   3. Sign the zip with Sparkle's `sign_update`, which reads the private key
#      from Keychain (per generate_keys' default install).
#   4. Pretty-print the appcast snippet to copy/paste into appcast.xml.
#   5. Upload the zip to a GitHub Release tagged `purplededup-v<version>`.
#
# One-time setup before first release — see RELEASING.md.
#
# Required env vars:
#   SPARKLE_PUBLIC_KEY   The base64 public key, output of `generate_keys -p`.
#                        Stored in your shell rc; build-app.sh embeds it in
#                        Info.plist.
#
# Optional:
#   GITHUB_REPO          Defaults to bronty13/PhantomLives.
#   NOTARIZE_PROFILE     If set, build-app.sh notarizes + staples the bundle
#                        before zipping.
#
# Output:
#   ~/Downloads/PurpleDedup release/PurpleDedup-<version>.zip
#   ~/Downloads/PurpleDedup release/appcast-snippet.xml

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${SPARKLE_PUBLIC_KEY:-}" ] || [ "${SPARKLE_PUBLIC_KEY}" = "PLACEHOLDER_RUN_generate_keys_AND_SET_SPARKLE_PUBLIC_KEY" ]; then
    cat >&2 <<'EOF'
FATAL: SPARKLE_PUBLIC_KEY is unset (or still the placeholder).

One-time setup:
  1. Locate Sparkle's bin tools:
       SPARKLE_BIN="$(find ~/Documents/GitHub/PhantomLives/PurpleDedup/.build/artifacts/sparkle/Sparkle/bin -type d | head -1)"
       export PATH="$SPARKLE_BIN:$PATH"
  2. Generate the EdDSA keypair (private to Keychain, public printed):
       generate_keys
  3. Export the public key in this shell, and add it to your ~/.zshrc:
       export SPARKLE_PUBLIC_KEY="<the long base64 string from step 2>"
  4. Re-run this script.
EOF
    exit 1
fi

GITHUB_REPO="${GITHUB_REPO:-bronty13/PhantomLives}"

# Match build-app.sh's version derivation so the appcast number agrees with
# what Info.plist says.
COMMIT_COUNT="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
SHORT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
SHORT_VERSION="${SHORT_VERSION:-1.0.${COMMIT_COUNT}}"
BUILD_NUMBER="${BUILD_NUMBER:-${COMMIT_COUNT}.${SHORT_SHA}}"

OUT_DIR="$HOME/Downloads/PurpleDedup release"
mkdir -p "$OUT_DIR"
ZIP_NAME="PurpleDedup-${SHORT_VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

# Build with the real public key embedded (build-app.sh reads SPARKLE_PUBLIC_KEY).
SHORT_VERSION="$SHORT_VERSION" BUILD_NUMBER="$BUILD_NUMBER" \
    SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
    ./build-app.sh

# Zip the bundle. ditto -c -k --keepParent preserves codesign-friendly
# attributes; plain `zip` strips xattrs and breaks the signature.
rm -f "$ZIP_PATH"
ditto -c -k --keepParent PurpleDedup.app "$ZIP_PATH"
echo "Wrote $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# Sparkle's sign_update reads the private key from Keychain. Output is a
# `sparkle:edSignature="..." length="..."` fragment — exactly what goes in
# the <enclosure> of the appcast item.
SPARKLE_BIN="$(find .build/artifacts/sparkle/Sparkle/bin -type d -maxdepth 1 | head -1)"
if [ ! -x "$SPARKLE_BIN/sign_update" ]; then
    echo "FATAL: sign_update not found at $SPARKLE_BIN. Run 'swift package resolve' first." >&2
    exit 1
fi
SIGN_FRAGMENT="$("$SPARKLE_BIN/sign_update" "$ZIP_PATH")"
echo "Signed: $SIGN_FRAGMENT"

# Build the appcast snippet. The download URL is constructed against a GitHub
# release we'll create below — adjust if you host elsewhere.
RELEASE_TAG="purplededup-v${SHORT_VERSION}"
DOWNLOAD_URL="https://github.com/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${ZIP_NAME}"
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"

SNIPPET_PATH="$OUT_DIR/appcast-snippet.xml"
cat > "$SNIPPET_PATH" <<EOF
        <item>
            <title>PurpleDedup ${SHORT_VERSION}</title>
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
echo "Wrote $SNIPPET_PATH"

cat <<EOF

NEXT STEPS — finalize this release:

  1. Paste the snippet ($SNIPPET_PATH) into appcast.xml as the FIRST <item>:

       \$ \$EDITOR appcast.xml
       (insert the snippet's <item>...</item> block right after the <channel>
        descriptive header, BEFORE any older <item> entries)

  2. Create the GitHub release and upload the zip:

       \$ gh release create $RELEASE_TAG \\
             --title "PurpleDedup ${SHORT_VERSION}" \\
             --notes "See CHANGELOG.md" \\
             "$ZIP_PATH"

  3. Commit + push appcast.xml:

       \$ git add PurpleDedup/appcast.xml
       \$ git commit -m "PurpleDedup ${SHORT_VERSION}: appcast"
       \$ git push origin main

The next time existing users launch the app (or up to 24h later), Sparkle
fetches the updated appcast, sees the new <item>, verifies the EdDSA
signature, and offers the update.
EOF
