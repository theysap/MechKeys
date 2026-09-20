#!/bin/bash
#
# Regenerates Scripts/dmg/DS_Store, the committed window layout for the disk
# image.
#
# Run this only when the layout or the background changes, and only on a Mac
# with a Finder — it drives Finder through Apple events and will ask for
# automation permission the first time. The result is committed precisely so
# that make-dmg.sh, and the build machine running it, never have to do any of
# this.
#
#   swift Scripts/make-dmg-background.swift
#   (cd Scripts/dmg && tiffutil -cathidpicheck background.png background@2x.png -out background.tiff)
#   ./Scripts/build-app.sh
#   ./Scripts/make-dmg-layout.sh

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MechKeys"
APP="dist/${APP_NAME}.app"
# Must match the volume name make-dmg.sh uses: the background is referenced
# by an alias that embeds it.
VOLUME="${APP_NAME}"
MOUNT="/Volumes/${VOLUME}"
IMAGE="dist/layout-scratch.dmg"

GREEN=$'\033[0;32m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }

if [ ! -d "${APP}" ]; then
    echo "${APP} not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi
if [ ! -f Scripts/dmg/background.tiff ]; then
    echo "Scripts/dmg/background.tiff not found. Render it first:" >&2
    echo "  swift Scripts/make-dmg-background.swift" >&2
    exit 1
fi

STAGING="$(mktemp -d)"
cleanup() {
    hdiutil detach "${MOUNT}" -quiet 2> /dev/null || true
    rm -rf "${STAGING}" "${IMAGE}"
}
trap cleanup EXIT

step "Staging"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
mkdir "${STAGING}/.background"
cp Scripts/dmg/background.tiff "${STAGING}/.background/"

step "Creating a writable image to arrange"
rm -f "${IMAGE}"
# Writable, and deliberately roomy: Finder needs space to write the layout.
hdiutil create -srcfolder "${STAGING}" -volname "${VOLUME}" -format UDRW \
    -fs HFS+ -size 64m -ov "${IMAGE}" > /dev/null

hdiutil attach "${IMAGE}" -mountpoint "${MOUNT}" -nobrowse > /dev/null

step "Arranging the window (Finder will ask for permission the first time)"
osascript Scripts/dmg/layout.applescript "${VOLUME}"

# Finder writes the layout lazily; give it a moment to land on disk.
sync
sleep 2

if [ ! -f "${MOUNT}/.DS_Store" ]; then
    echo "Finder did not write a .DS_Store. Was automation permission refused?" >&2
    exit 1
fi

cp "${MOUNT}/.DS_Store" Scripts/dmg/DS_Store
step "Wrote Scripts/dmg/DS_Store ($(du -h Scripts/dmg/DS_Store | awk '{print $1}'))"
echo "    Commit it. make-dmg.sh copies it into every image from now on."
