#!/bin/bash
#
# Creates the self-signed identity that every MechKeys release is signed with,
# and prints the two GitHub secrets the release workflow needs.
#
# Why this exists
# ---------------
#
# macOS keys the Accessibility grant to the application's code signature. The
# in-app updater replaces the bundle in place, so unless every release carries
# the *same* signature, an update silently costs the user their permission:
# MechKeys stays switched on in System Settings while the new copy — a
# different application, as far as TCC is concerned — is refused.
#
# An ad-hoc signature changes with every build, so it fails that test outright.
# A stable certificate passes it, and a self-signed one is enough: TCC compares
# the leaf certificate, and does not care who issued it.
#
# What this does NOT fix is Gatekeeper. A self-signed release is still an
# "unidentified developer" on first download, and the user has to open it from
# the Finder's context menu once. Only a Developer ID with notarisation removes
# that, and `build-app.sh` prefers one whenever DEVELOPER_ID_APPLICATION is set.
#
# Run once, then keep the output:
#   ./Scripts/make-release-certificate.sh

set -euo pipefail

cd "$(dirname "$0")/.."

NAME="${RELEASE_IDENTITY_NAME:-MechKeys Release}"
# Twenty years. Re-issuing this certificate means a new leaf, which means every
# existing user has to grant Accessibility again — so it should outlive the
# project rather than the other way round.
DAYS=7300
OUT_DIR="${1:-dist/signing}"

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }
note() { echo "${YELLOW}    $*${RESET}"; }
die() { echo "${RED}==>${RESET} $*" >&2; exit 1; }

PASSWORD="$(openssl rand -base64 24 | tr -d '\n/+=' | head -c 24)"
[ -n "${PASSWORD}" ] || die "Could not generate a passphrase."

mkdir -p "${OUT_DIR}"
chmod 700 "${OUT_DIR}"
P12="${OUT_DIR}/mechkeys-release.p12"

if [ -e "${P12}" ]; then
    die "${P12} already exists. Move it aside if you really mean to re-issue."
fi

step "Generating a self-signed code-signing certificate"
note "common name: ${NAME}"
# codeSigning in extendedKeyUsage is what makes codesign willing to use it.
openssl req -x509 -newkey rsa:2048 -sha256 -days "${DAYS}" -nodes \
    -keyout "${OUT_DIR}/key.pem" -out "${OUT_DIR}/cert.pem" \
    -subj "/CN=${NAME}/O=MechKeys/C=US" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2> /dev/null \
    || die "openssl could not generate the certificate."

step "Packaging the identity"
openssl pkcs12 -export -legacy \
    -out "${P12}" \
    -inkey "${OUT_DIR}/key.pem" -in "${OUT_DIR}/cert.pem" \
    -name "${NAME}" -passout "pass:${PASSWORD}" 2> /dev/null \
    || die "openssl could not package the identity."

rm -f "${OUT_DIR}/key.pem"
chmod 600 "${P12}"

FINGERPRINT="$(openssl x509 -in "${OUT_DIR}/cert.pem" -noout -fingerprint -sha1 \
    | cut -d= -f2)"

echo
step "Done"
echo
echo "Add these three repository secrets at"
echo "  https://github.com/theysap/MechKeys/settings/secrets/actions"
echo
echo "${GREEN}SELF_SIGNED_IDENTITY${RESET}"
echo "${NAME}"
echo
echo "${GREEN}SELF_SIGNED_CERTIFICATE_PASSWORD${RESET}"
echo "${PASSWORD}"
echo
echo "${GREEN}SELF_SIGNED_CERTIFICATE_P12${RESET}"
base64 < "${P12}" | tr -d '\n'
echo
echo
note "leaf SHA-1: ${FINGERPRINT}"
note "This is the identity the Accessibility grant is pinned to."
echo
note "${P12} and ${OUT_DIR}/cert.pem are the only copies of this identity."
note "Back them up somewhere private. ${OUT_DIR} is gitignored."
note "Losing them means re-issuing, and every user re-granting Accessibility."
