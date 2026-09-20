#!/bin/bash
#
# Builds MechKeys.app into dist/.
#
# The bundle is assembled by hand rather than by Xcode: the project is a Swift
# package, and the one thing the app needs at runtime beyond its binary — the
# sound library — is copied into Contents/Resources here. Everything the app
# needs to run ships inside the bundle; the only thing it ever downloads is a
# newer copy of itself, and only when the user asks for one.
#
# Signing, in order of preference:
#   DEVELOPER_ID_APPLICATION  a real Developer ID. Notarisable, no Gatekeeper
#                             wall, and stable across releases.
#   SIGNING_IDENTITY          any other identity already in a keychain. The
#                             release workflow sets this to the self-signed
#                             release certificate.
#   "MechKeys Development"    a local identity, if Scripts/make-dev-certificate.sh
#                             has been run.
#   ad-hoc                    the fallback, and the one that breaks the
#                             Accessibility grant on every rebuild. See below.

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
# The recordings are MIT licensed by their author; the notice travels with
# them, inside the bundle. See assets/LICENSES.md.
cp Resources/LICENSE-sounds.txt "${RESOURCES}/LICENSE-sounds.txt"

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
DEV_CERT="MechKeys Development"
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    IDENTITY="${DEVELOPER_ID_APPLICATION}"
    # Notarisation refuses anything without a secure timestamp. An ad-hoc
    # signature cannot carry one at all.
    TIMESTAMP="--timestamp"
    note "identity: ${IDENTITY} (Developer ID)"
elif [ -n "${SIGNING_IDENTITY:-}" ]; then
    # The self-signed release identity, imported into a throwaway keychain by
    # the release workflow. codesign is happy to use a certificate whose root
    # nothing trusts — the signature it produces is still stable, which is the
    # property the Accessibility grant and therefore the updater depend on.
    # Gatekeeper is a separate problem and this does not solve it.
    IDENTITY="${SIGNING_IDENTITY}"
    TIMESTAMP="--timestamp=none"
    note "identity: ${IDENTITY} (self-signed release)"
elif security find-identity -p codesigning 2> /dev/null | grep -q "${DEV_CERT}"; then
    # A stable local identity, so the Accessibility grant survives a rebuild.
    # See Scripts/make-dev-certificate.sh for why that matters.
    #
    # Deliberately not `-v`. That lists *valid* identities only, and a
    # self-signed certificate is never valid — nothing trusts its root. It
    # signs regardless, which is all this needs; trusting it would mean
    # putting a self-signed root into the System keychain for no gain.
    IDENTITY="${DEV_CERT}"
    TIMESTAMP="--timestamp=none"
    note "identity: ${DEV_CERT} (local development)"
else
    IDENTITY="-"
    TIMESTAMP="--timestamp=none"
    note "ad-hoc (set DEVELOPER_ID_APPLICATION, or run Scripts/make-dev-certificate.sh)"
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
# and the permission has to be granted again — the switch stays on in System
# Settings, pointing at a build that no longer exists. Any stable identity
# avoids this, because the designated requirement then names the certificate
# rather than the binary's hash:
#
#   ad-hoc:  identifier "com.mechkeys.app" and cdhash H"…"   ← new every build
#   signed:  identifier "com.mechkeys.app" and certificate root = H"…"
#
# That difference is also what makes the in-app updater safe to ship: it
# replaces the bundle in place, and only the second form survives it.
if [ "${IDENTITY}" = "-" ]; then
    note "ad-hoc signed: Accessibility permission will NOT survive a rebuild,"
    note "and would not survive an in-app update either."
    note "run ./Scripts/make-dev-certificate.sh once to fix that locally."
fi

step "Built ${APP}"
du -sh "${APP}" | awk '{print "    size: " $1}'
