#!/usr/bin/env bash
# Cuts a release: bumps package.json + package-lock.json, updates the README
# version marker, commits, tags "v<version>", and with --push pushes the commit
# and tag. CI then verifies, packages, and creates a draft GitHub Release.
#
# Usage: scripts/release.sh [X.Y.Z] [--push]
# Shared engine: https://github.com/L-K-M/release-tool
set -euo pipefail

export RELEASE_APP_NAME="Thalyx"
export RELEASE_KIND="npm"
export RELEASE_CI_NOTE="CI (release.yml) will verify, package macOS and Linux installers, and create the draft GitHub Release for <tag>."
export RELEASE_INVOKED_AS="scripts/release.sh"

BIN="${LKM_RELEASE_BIN:-lkm-release}"
command -v "$BIN" >/dev/null 2>&1 || {
  echo "error: lkm-release not found — clone https://github.com/L-K-M/release-tool and run ./install.sh" >&2
  exit 1
}
exec "$BIN" "$@"
