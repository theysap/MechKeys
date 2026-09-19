#!/bin/bash
#
# Packages dist/MechKeys.app into a disk image.
#
# The window is deliberately plain: the app and a link to /Applications. No
# background picture, because arranging one means driving Finder through Apple
# events, which asks for automation permission and has no chance of working on
# a build machine.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MechKeys"
VERSION="$(cat VERSION)"
DIST="dist"
APP="${DIST}/${APP_NAME}.app"
DMG="${DIST}/${APP_NAME}-${VERSION}.dmg"

GREEN=$'\033[0;32m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }

if [ ! -d "${APP}" ]; then
    echo "${APP} not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

step "Staging ${APP_NAME} ${VERSION}"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

step "Creating disk image"
rm -f "${DMG}"
# ULFO is LZFSE-compressed. `hdiutil create` warns that it is deprecated in
# favour of `diskutil image create from`, but diskutil's copy silently drops
# the window layout, so this stays until it does not.
hdiutil create \
    -srcfolder "${STAGING}" \
    -volname "${APP_NAME}" \
    -format ULFO \
    -ov "${DMG}" 2>&1 | grep -v "deprecated" || true

if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    step "Signing disk image"
    codesign --force --timestamp --sign "${DEVELOPER_ID_APPLICATION}" "${DMG}"
fi

# Notarisation is what stops Gatekeeper refusing the app on someone else's
# Mac. Without it, every download is met with "Apple could not verify MechKeys
# is free of malware", and the only way past is Privacy & Security → Open
# Anyway. It needs a paid Developer ID; the build works without one and simply
# skips this.
#
# Provide either a stored profile:
#   xcrun notarytool store-credentials mechkeys --apple-id … --team-id … --password …
#   NOTARY_KEYCHAIN_PROFILE=mechkeys ./Scripts/make-dmg.sh
# or the three values directly, which is what CI does:
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD  (an app-specific password)
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ] || [ -n "${NOTARY_APPLE_ID:-}" ]; then
    step "Notarising (this waits on Apple, usually a few minutes)"

    if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
        xcrun notarytool submit "${DMG}" \
            --keychain-profile "${NOTARY_KEYCHAIN_PROFILE}" --wait
    else
        xcrun notarytool submit "${DMG}" \
            --apple-id "${NOTARY_APPLE_ID}" \
            --team-id "${NOTARY_TEAM_ID}" \
            --password "${NOTARY_PASSWORD}" --wait
    fi

    # Stapling puts the ticket inside the image, so it opens on a Mac that is
    # offline as well as on one that is not.
    step "Stapling"
    xcrun stapler staple "${DMG}"
    xcrun stapler validate "${DMG}"
elif [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
    echo "    not notarised: Gatekeeper will refuse this on first launch."
    echo "    See the Distribution section of docs/TECHNICAL.md."
fi

step "Verifying"
hdiutil imageinfo "${DMG}" > /dev/null || {
    echo "Disk image did not verify." >&2
    exit 1
}

step "Built ${DMG}"
du -h "${DMG}" | awk '{print "    size: " $1}'
shasum -a 256 "${DMG}" | awk '{print "    sha256: " $1}'
