#!/bin/bash
#
# prepare-release.sh — Zip, sign, and prepare a Jukebox release
#
# Usage:
#   ./scripts/prepare-release.sh /path/to/Jukebox.app
#
# This script will:
#   1. Read the version from the app bundle
#   2. Create a signed zip archive
#   3. Update docs/appcast.xml with the correct GitHub Releases URL
#   4. Upload the zip to the GitHub release
#   5. Commit and push the updated appcast
#
# Prerequisites:
#   - Sparkle signing key in Keychain (set up via generate_keys)
#   - gh CLI authenticated
#   - App already archived and exported from Xcode

set -euo pipefail

REPO="jaydenk/Jukebox"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPCAST_PATH="$REPO_DIR/docs/appcast.xml"
MIN_SYSTEM_VERSION="13.0"

# Find Sparkle tools in DerivedData
SPARKLE_BIN=$(find ~/Library/Developer/Xcode/DerivedData -path "*/sparkle/Sparkle/bin/sign_update" -print -quit 2>/dev/null)
if [ -z "$SPARKLE_BIN" ]; then
    echo "Error: Could not find Sparkle sign_update in DerivedData."
    echo "Build the project in Xcode first so Sparkle SPM package is resolved."
    exit 1
fi
SIGN_UPDATE="$SPARKLE_BIN"

# Validate input
if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/Jukebox.app"
    exit 1
fi

APP_PATH="$1"
if [ ! -d "$APP_PATH" ]; then
    echo "Error: $APP_PATH does not exist or is not a directory."
    exit 1
fi

# Read version from app bundle
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")

if [ -z "$VERSION" ]; then
    echo "Error: Could not read version from $APP_PATH"
    exit 1
fi

echo "==> Preparing release v$VERSION (build $BUILD)"

# Create zip
ZIP_NAME="Jukebox-$VERSION.zip"
ZIP_PATH="$REPO_DIR/$ZIP_NAME"

echo "==> Creating zip archive..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "    $ZIP_NAME ($ZIP_SIZE bytes)"

# Sign the zip
echo "==> Signing with Sparkle..."
SIGN_OUTPUT=$("$SIGN_UPDATE" "$ZIP_PATH")
# sign_update outputs: sparkle:edSignature="..." length="..."
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"//')

if [ -z "$ED_SIGNATURE" ]; then
    echo "Error: Failed to get EdDSA signature."
    echo "sign_update output: $SIGN_OUTPUT"
    exit 1
fi
echo "    Signature: ${ED_SIGNATURE:0:20}..."

# Build download URL (GitHub Releases, not GitHub Pages)
DOWNLOAD_URL="https://github.com/$REPO/releases/download/v$VERSION/$ZIP_NAME"
PUB_DATE=$(date -R)

# Generate appcast XML
echo "==> Updating appcast.xml..."
cat > "$APPCAST_PATH" << APPCAST_EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Jukebox</title>
        <item>
            <title>$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$VERSION</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL" length="$ZIP_SIZE" type="application/octet-stream" sparkle:edSignature="$ED_SIGNATURE"/>
        </item>
    </channel>
</rss>
APPCAST_EOF

echo "    Download URL: $DOWNLOAD_URL"

# Upload zip to GitHub release
echo "==> Uploading to GitHub release v$VERSION..."
if ! gh release view "v$VERSION" --repo "$REPO" &>/dev/null; then
    echo "Error: GitHub release v$VERSION does not exist."
    echo "Create it first: gh release create v$VERSION --repo $REPO --title 'v$VERSION'"
    rm "$ZIP_PATH"
    exit 1
fi

# Remove existing asset if re-running
gh release upload "v$VERSION" "$ZIP_PATH" --repo "$REPO" --clobber
echo "    Uploaded $ZIP_NAME"

# Clean up zip from repo root
rm "$ZIP_PATH"

# Commit and push appcast
echo "==> Committing and pushing appcast..."
cd "$REPO_DIR"
git add docs/appcast.xml
git commit -m "Update appcast for v$VERSION release"
# Push the CURRENT HEAD to main. `git push origin main` pushes the local 'main'
# ref (refs/heads/main), NOT the checked-out branch — so if this script is run from
# a feature/release branch, the commit just made is never pushed and the push
# silently no-ops ("Everything up-to-date", exit 0). HEAD:main always publishes this
# commit; a non-fast-forward is rejected loudly instead of dropped silently.
git push origin HEAD:main

# Confirm the appcast actually reached origin/main — a silent no-op or rejected push
# would otherwise leave GitHub Pages serving the previous version.
git fetch origin --quiet
if ! git show "origin/main:docs/appcast.xml" | grep -q "<sparkle:version>$VERSION<"; then
    echo "Error: appcast for v$VERSION did NOT reach origin/main — the update feed was not published." >&2
    echo "       Push it manually from the release commit: git push origin HEAD:main" >&2
    exit 1
fi
echo "    appcast for v$VERSION confirmed on origin/main"

echo ""
echo "==> Release v$VERSION complete!"
echo "    Appcast: https://jaydenk.github.io/Jukebox/appcast.xml"
echo "    Release: https://github.com/$REPO/releases/tag/v$VERSION"
