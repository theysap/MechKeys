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
    -name "${NAME}" -passout pass: 2> /dev/null \
    || die "openssl could not package the identity."

step "Importing into the login keychain"
# -A lets any tool use the key without a prompt per build. That is a deliberate
# trade for a throwaway local signing key, and not something to do with a
# Developer ID.
security import "${TMP}/identity.p12" -k "${KEYCHAIN}" -P "" -A \
    || die "Could not import the identity into the keychain."

step "Trusting it for code signing"
note "macOS will ask for your password: it is changing keychain trust settings."
# Without trust, codesign reports the identity as invalid and refuses it.
if ! sudo security add-trusted-cert -d -r trustRoot \
    -p codeSign -k /Library/Keychains/System.keychain "${TMP}/cert.pem" 2> /dev/null; then
    note "Could not set trust automatically."
    note "Open Keychain Access, find '${NAME}', and set Code Signing to Always Trust."
fi

echo
if security find-identity -v -p codesigning | grep -q "${NAME}"; then
    step "Ready"
    echo "    ./Scripts/build-app.sh now signs with '${NAME}'."
    echo "    Grant Accessibility permission once; it will survive rebuilds."
else
    note "The identity is installed but not yet reported as valid."
    note "Set Code Signing to Always Trust for '${NAME}' in Keychain Access."
fi
