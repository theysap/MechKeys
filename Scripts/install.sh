#!/bin/bash
#
# Installs MechKeys into /Applications.
#
#   curl -fsSL https://theysap.com/install/mechkeys | bash
#
# theysap.com serves a copy of this file. This one, in the application's own
# repository, is the original:
#   https://github.com/theysap/MechKeys/blob/master/Scripts/install.sh
#
# Everything lives inside main(), which is called on the very last line: a
# download that gets truncated halfway then runs nothing at all, rather than
# half an install.
#
# Pin a version with MECHKEYS_VERSION, and skip the launch at the end with
# MECHKEYS_NO_LAUNCH=1.

set -euo pipefail

REPO="theysap/MechKeys"
APP_NAME="MechKeys"
MIN_MACOS=26

GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }
die() { echo "${RED}==>${RESET} $*" >&2; exit 1; }

cleanup() {
    if [ -n "${MOUNT:-}" ] && [ -d "${MOUNT}" ]; then
        hdiutil detach "${MOUNT}" -quiet 2>/dev/null || true
    fi
    if [ -n "${TMP:-}" ]; then
        rm -rf "${TMP}"
    fi
}

# The tag of the latest release, without asking api.github.com. That endpoint
# is rate limited to 60 requests an hour per address, which a shared office IP
# can get through. The redirect on /releases/latest is not limited at all.
latest_version() {
    local url tag
    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/${REPO}/releases/latest")" \
        || die "Could not reach GitHub."
    tag="${url##*/}"
    case "${tag}" in
        v[0-9]*) printf '%s' "${tag#v}" ;;
        *) die "Could not work out the latest release (got '${tag}')." ;;
    esac
}

main() {
    [ "$(uname -s)" = "Darwin" ] || die "MechKeys is a macOS application."

    # The published build is arm64 only.
    [ "$(uname -m)" = "arm64" ] ||
        die "MechKeys needs Apple silicon; this Mac reports $(uname -m)."

    local macos
    macos="$(sw_vers -productVersion)"
    [ "${macos%%.*}" -ge "${MIN_MACOS}" ] ||
        die "MechKeys needs macOS ${MIN_MACOS} or later; this is ${macos}."

    # /Applications is group-writable by admin users. Anyone else gets the
    # per-user equivalent rather than a sudo prompt they cannot answer: when
    # the script arrives down a pipe, stdin is the pipe, not the terminal.
    local dest
    if [ -w "/Applications" ]; then
        dest="/Applications"
    else
        dest="${HOME}/Applications"
        mkdir -p "${dest}"
    fi

    local version
    version="${MECHKEYS_VERSION:-$(latest_version)}"

    TMP="$(mktemp -d)"
    MOUNT=""
    trap cleanup EXIT

    local base dmg
    base="https://github.com/${REPO}/releases/download/v${version}"
    dmg="${TMP}/${APP_NAME}-${version}.dmg"

    step "Downloading ${APP_NAME} ${version}"
    curl -fL --progress-bar -o "${dmg}" "${base}/${APP_NAME}-${version}.dmg" ||
        die "No disk image published for version ${version}."

    # Catches a download that was truncated or mangled in transit. It is not a
    # defence against a compromised release: the sums are published alongside
    # the image, by the same hand.
    step "Verifying"
    curl -fsSL -o "${TMP}/SHA256SUMS.txt" "${base}/SHA256SUMS.txt" ||
        die "Could not fetch the checksums."

    local expected actual
    expected="$(awk -v f="${APP_NAME}-${version}.dmg" '$2 == f { print $1 }' \
        "${TMP}/SHA256SUMS.txt")"
    actual="$(shasum -a 256 "${dmg}" | awk '{ print $1 }')"
    [ -n "${expected}" ] || die "No checksum published for ${APP_NAME}-${version}.dmg."
    [ "${expected}" = "${actual}" ] || die "Checksum mismatch, not installing.
    expected ${expected}
      actual ${actual}"

    MOUNT="${TMP}/mnt"
    hdiutil attach -nobrowse -readonly -quiet -mountpoint "${MOUNT}" "${dmg}" \
        2>/dev/null || die "Could not mount the disk image."
    [ -d "${MOUNT}/${APP_NAME}.app" ] || die "The disk image has no ${APP_NAME}.app in it."

    # Replacing the bundle underneath a running process leaves it running the
    # old code, with an event tap belonging to a binary that is gone.
    if pgrep -x "${APP_NAME}" > /dev/null 2>&1; then
        step "Quitting the running copy"
        pkill -x "${APP_NAME}" 2>/dev/null || true
        local i
        for i in 1 2 3 4 5; do
            pgrep -x "${APP_NAME}" > /dev/null 2>&1 || break
            sleep 1
        done
    fi

    step "Installing to ${dest}"
    rm -rf "${dest}/${APP_NAME}.app"
    # ditto rather than cp -R: it carries the bundle's extended attributes and
    # its signature across intact.
    ditto "${MOUNT}/${APP_NAME}.app" "${dest}/${APP_NAME}.app"

    step "Installed ${dest}/${APP_NAME}.app"

    if [ -z "${MECHKEYS_NO_LAUNCH:-}" ]; then
        open "${dest}/${APP_NAME}.app"
        echo "    It lives in the menu bar. macOS will ask for Accessibility"
        echo "    permission — MechKeys needs it to know that a key was pressed,"
        echo "    and never records what you type."
    fi
}

main "$@"
