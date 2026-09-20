#!/bin/bash
#
# Creates a self-signed code-signing certificate for local development, so that
# Accessibility permission survives a rebuild.
#
# The problem this solves:
#
#   macOS keys the Accessibility grant to the application's code signature. An
#   ad-hoc signature (`codesign -s -`) is different in every build, so every
#   rebuild looks like a brand new application to TCC. The switch stays on in
#   System Settings, pointing at a build that no longer exists, while the one
#   you just built is refused — with no error anywhere, because as far as macOS
#   is concerned it was never granted anything.
#
#   A certificate is stable. Sign with the same one every time and the grant
#   keeps matching, so permission is granted once and then left alone.
#
# No password needed, and nothing is added to the System trust store. An
# earlier version of this script did `sudo security add-trusted-cert`, on the
# assumption that codesign would refuse an untrusted certificate. It does not:
# it signs perfectly happily, `codesign --verify --deep --strict` passes, and
# the designated requirement comes out as
#
#   identifier "com.mechkeys.app" and certificate root = H"…"
#
# which is exactly what the Accessibility grant is keyed to. Trust only
# decides whether `security find-identity -v` lists the identity, and putting
# a self-signed root into the System keychain is not a small thing to do for
# cosmetics. `build-app.sh` looks the identity up without `-v` for the same
# reason.
#
# This is for development only. Distribution needs a real Developer ID, which
# `build-app.sh` uses instead whenever DEVELOPER_ID_APPLICATION is set.
#
# Run once:
#   ./Scripts/make-dev-certificate.sh

set -euo pipefail

NAME="MechKeys Development"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
RED=$'\033[0;31m'
RESET=$'\033[0m'
step() { echo "${GREEN}==>${RESET} $*"; }
note() { echo "${YELLOW}    $*${RESET}"; }
die() { echo "${RED}==>${RESET} $*" >&2; exit 1; }

if security find-certificate -c "${NAME}" "${KEYCHAIN}" > /dev/null 2>&1; then
    step "'${NAME}' already exists"
    note "Delete it from Keychain Access to start over."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

# A real passphrase, thrown away at the end of this script.
#
# Not an empty one, which is the obvious thing to reach for and does not work:
# OpenSSL and Apple's Security framework disagree about how an empty PKCS#12
# password is encoded before the MAC is computed — an empty byte string on one
# side, the two-byte UTF-16 terminator on the other. `security import` then
# fails with "MAC verification failed during PKCS12 import (wrong password?)",
# which points at exactly the wrong thing. Any non-empty password sidesteps it.
PASSPHRASE="$(openssl rand -base64 18 | tr -d '\n/+=')"
[ -n "${PASSPHRASE}" ] || die "Could not generate a passphrase."

step "Generating a self-signed code-signing certificate"
# codeSigning in extendedKeyUsage is what makes codesign willing to use it.
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" \
    -subj "/CN=${NAME}/O=MechKeys/C=US" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2> /dev/null \
    || die "openssl could not generate the certificate."

openssl pkcs12 -export -legacy \
    -out "${TMP}/identity.p12" \
    -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
    -name "${NAME}" -passout "pass:${PASSPHRASE}" 2> /dev/null \
    || die "openssl could not package the identity."

step "Importing into the login keychain"
# -A lets any tool use the key without a prompt per build. That is a deliberate
# trade for a throwaway local signing key, and not something to do with a
# Developer ID.
security import "${TMP}/identity.p12" -k "${KEYCHAIN}" -P "${PASSPHRASE}" -A \
    || die "Could not import the identity into the keychain."

echo
# Deliberately not `-v`: that lists valid identities only, and a self-signed
# certificate whose root nothing trusts is never valid. It is still perfectly
# usable for signing — see the note at the top.
if security find-identity -p codesigning | grep -q "${NAME}"; then
    step "Ready"
    echo "    ./Scripts/build-app.sh now signs with '${NAME}'."
    echo "    Grant Accessibility permission once; it will survive rebuilds."
    echo
    note "'CSSMERR_TP_NOT_TRUSTED' beside it is expected and does not matter."
else
    die "The identity did not land in the keychain."
fi
