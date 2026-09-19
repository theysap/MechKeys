#!/bin/bash
#
# Builds MechKeys.app into dist/.
#
# The bundle is assembled by hand rather than by Xcode: the project is a Swift
# package, and the one thing the app needs at runtime beyond its binary — the
# sound library — is copied into Contents/Resources here. Everything ships
# inside the bundle; the app never downloads anything.
#
# Signing:
#   Set DEVELOPER_ID_APPLICATION to a Developer ID identity to sign properly.
#   Without it the bundle is signed ad-hoc, which runs, but see the note on
#   Accessibility permission below.

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MechKeys"
BUNDLE_ID="com.mechkeys.app"
VERSION="$(cat VERSION)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
CONFIGURATION="${CONFIGURATION:-release}"
MIN_MACOS="26.0"

DIST="dist"
APP="${DIST}/${APP_NAME}.app"
CONTENTS="${APP}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }
note() { echo "${YELLOW}    $*${RESET}"; }

# The sample library is generated, not committed as a binary blob nobody can
# review. Regenerate it if it is missing, so a fresh clone builds in one step.
if [ ! -f "Resources/Sounds/manifest.json" ]; then
    step "Generating sound library"
    python3 Tools/generate_sounds.py
fi

step "Building ${APP_NAME} ${VERSION} (build ${BUILD_NUMBER}, ${CONFIGURATION})"
swift build -c "${CONFIGURATION}" 2>&1 | grep -vE "ld: warning: search path" || true

BUILD_DIR="$(swift build -c "${CONFIGURATION}" --show-bin-path)"

if [ ! -x "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "Build did not produce ${BUILD_DIR}/${APP_NAME}" >&2
    exit 1
fi

step "Assembling bundle"
rm -rf "${APP}"
mkdir -p "${MACOS_DIR}" "${RESOURCES}"

cp "${BUILD_DIR}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

# The whole sound library, bundled. SoundLibrary looks here first.
step "Bundling sounds"
cp -R "Resources/Sounds" "${RESOURCES}/Sounds"
SAMPLE_COUNT="$(find "${RESOURCES}/Sounds" -name '*.wav' | wc -l | tr -d ' ')"
note "${SAMPLE_COUNT} samples"

step "Rendering icon"
ICONSET_DIR="$(mktemp -d)"
ICONSET="${ICONSET_DIR}/${APP_NAME}.iconset"
mkdir -p "${ICONSET}"
swift Scripts/make-icon.swift "${ICONSET}" > /dev/null
iconutil -c icns "${ICONSET}" -o "${RESOURCES}/AppIcon.icns"
rm -rf "${ICONSET_DIR}"

cp LICENSE "${RESOURCES}/LICENSE.txt"

step "Writing Info.plist"
cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <!-- Menu bar only: no Dock icon, no app switcher entry. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>MIT licensed. See LICENSE.</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

plutil -lint "${CONTENTS}/Info.plist" > /dev/null

printf 'APPL????' > "${CONTENTS}/PkgInfo"

step "Signing"
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    IDENTITY="${DEVELOPER_ID_APPLICATION}"
    # Notarisation refuses anything without a secure timestamp. An ad-hoc
    # signature cannot carry one at all.
    TIMESTAMP="--timestamp"
    note "identity: ${IDENTITY}"
else
    IDENTITY="-"
    TIMESTAMP="--timestamp=none"
    note "ad-hoc (set DEVELOPER_ID_APPLICATION to sign for distribution)"
fi

# No entitlements file and, in particular, no App Sandbox: a sandboxed process
# is not allowed to create a CGEventTap at all, so sandboxing the app would
# mean it could never hear a keystroke. The hardened runtime is on, which is
# what notarisation requires and what the event tap is happy with.
codesign --force ${TIMESTAMP} --options runtime --sign "${IDENTITY}" "${MACOS_DIR}/${APP_NAME}"
codesign --force ${TIMESTAMP} --options runtime --sign "${IDENTITY}" "${APP}"
codesign --verify --deep --strict "${APP}"

# macOS keys the Accessibility grant to the code signature. An ad-hoc signature
# changes on every build, so every rebuild looks like a different application
# and the permission has to be granted again. A Developer ID identity is stable
# and does not have this problem.
if [ "${IDENTITY}" = "-" ]; then
    note "ad-hoc signed: macOS will ask for Accessibility permission again after each rebuild."
fi

step "Built ${APP}"
du -sh "${APP}" | awk '{print "    size: " $1}'
