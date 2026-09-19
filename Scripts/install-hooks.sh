#!/bin/bash
#
# Points git at the hooks kept in the repository, so they are versioned along
# with everything else instead of living only in one working copy.

set -euo pipefail

cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
chmod +x .githooks/*

echo "Hooks installed:"
for hook in .githooks/*; do
    echo "  $(basename "${hook}")"
done
echo
echo "Skip them for a single commit with: git commit --no-verify"
