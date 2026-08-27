#!/usr/bin/env bash
# Builds verified, unsigned Thalyx packages for the current macOS or Linux host.
# Installs the lockfile, runs the local CI gate, packages every configured format,
# and rejects missing artifacts. --clean removes only out/ and release/ first.
#
# Usage: scripts/build.sh [--clean] [--run] [--check]
# Requirements: Node.js 24+, npm 11+; Linux needs xz-utils, binutils, and rpm.
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
cd "$ROOT"

readonly ACTION_BUILD="build"
readonly ACTION_CHECK="check"
readonly CLEAN_KEEP="keep"
readonly CLEAN_REMOVE="remove"
readonly RUN_PREVIEW="preview"
readonly RUN_SKIP="skip"
readonly HOST_MACOS="Darwin"
readonly HOST_LINUX="Linux"
readonly MIN_NODE_MAJOR=24
readonly MIN_NODE_MINOR=0
readonly MIN_NPM_MAJOR=11
readonly BUILD_OUTPUT="$ROOT/out"
readonly PACKAGE_OUTPUT="$ROOT/release"

usage() {
  awk 'NR == 1 && /^#!/ { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$SELF"
}

die() {
  echo "!! $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

require_version() {
  local name="$1"
  local actual="${2#v}"
  local minimum_major="$3"
  local minimum_minor="$4"
  local actual_major
  local actual_minor
  local _actual_patch

  IFS=. read -r actual_major actual_minor _actual_patch <<<"$actual"
  [[ "$actual_major" =~ ^[0-9]+$ && "$actual_minor" =~ ^[0-9]+$ ]] || \
    die "could not parse $name version $actual"

  if ((actual_major > minimum_major)); then return; fi
  if ((actual_major == minimum_major && actual_minor >= minimum_minor)); then return; fi

  die "$name $minimum_major.$minimum_minor+ is required; found $actual"
}

action="$ACTION_BUILD"
clean_policy="$CLEAN_KEEP"
run_policy="$RUN_SKIP"

for argument in "$@"; do
  case "$argument" in
    --clean) clean_policy="$CLEAN_REMOVE" ;;
    --run) run_policy="$RUN_PREVIEW" ;;
    --check) action="$ACTION_CHECK" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "!! unknown argument: $argument" >&2; usage >&2; exit 2 ;;
  esac
done

host="$(uname -s)"
case "$host" in
  "$HOST_MACOS"|"$HOST_LINUX") ;;
  *) die "unsupported host: $host" ;;
esac

require_command node
require_command npm
if [[ "$host" == "$HOST_LINUX" ]]; then
  require_command xz
  require_command ar
  require_command rpmbuild
fi

require_version "Node.js" "$(node --version)" "$MIN_NODE_MAJOR" "$MIN_NODE_MINOR"
require_version "npm" "$(npm --version)" "$MIN_NPM_MAJOR" 0

package_version="$(node -p "require('./package.json').version")"
lock_version="$(node -p "require('./package-lock.json').version")"
lock_root_version="$(node -p "require('./package-lock.json').packages[''].version")"
[[ "$package_version" == "$lock_version" && "$package_version" == "$lock_root_version" ]] || \
  die "package.json and package-lock.json versions differ"

if [[ "$action" == "$ACTION_CHECK" ]]; then
  echo "==> config"
  echo "-- host:     $host"
  echo "-- version:  $package_version"
  echo "-- install:  npm ci"
  echo "-- verify:   npm run check"
  echo "-- package:  npm run package"
  echo "-- output:   $PACKAGE_OUTPUT"
  exit 0
fi

if [[ "$clean_policy" == "$CLEAN_REMOVE" ]]; then
  echo "==> clean"
  rm -rf -- "$BUILD_OUTPUT" "$PACKAGE_OUTPUT"
fi

echo "==> install locked dependencies"
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm ci

echo "==> verify"
npm run check

# Remove old final files so stale artifacts cannot satisfy the post-build gate.
rm -f -- \
  "$PACKAGE_OUTPUT"/*.dmg "$PACKAGE_OUTPUT"/*.dmg.blockmap \
  "$PACKAGE_OUTPUT"/*.zip "$PACKAGE_OUTPUT"/*.zip.blockmap \
  "$PACKAGE_OUTPUT"/*.AppImage "$PACKAGE_OUTPUT"/*.AppImage.blockmap \
  "$PACKAGE_OUTPUT"/*.deb "$PACKAGE_OUTPUT"/*.rpm \
  "$PACKAGE_OUTPUT"/latest-mac.yml "$PACKAGE_OUTPUT"/latest-linux.yml

echo "==> package"
CSC_IDENTITY_AUTO_DISCOVERY="${CSC_IDENTITY_AUTO_DISCOVERY:-false}" npm run package

shopt -s nullglob
if [[ "$host" == "$HOST_MACOS" ]]; then
  artifacts=("$PACKAGE_OUTPUT"/*.dmg)
  ((${#artifacts[@]} >= 2)) || die "expected x64 and arm64 DMGs"

  packages=("$PACKAGE_OUTPUT"/*.zip)
  ((${#packages[@]} >= 2)) || die "expected x64 and arm64 ZIPs"
else
  artifacts=("$PACKAGE_OUTPUT"/*.AppImage)
  ((${#artifacts[@]} >= 1)) || die "expected an AppImage"

  packages=("$PACKAGE_OUTPUT"/*.deb)
  ((${#packages[@]} >= 1)) || die "expected a deb package"

  packages=("$PACKAGE_OUTPUT"/*.rpm)
  ((${#packages[@]} >= 1)) || die "expected an rpm package"
fi

all_artifacts=(
  "$PACKAGE_OUTPUT"/*.dmg
  "$PACKAGE_OUTPUT"/*.zip
  "$PACKAGE_OUTPUT"/*.AppImage
  "$PACKAGE_OUTPUT"/*.deb
  "$PACKAGE_OUTPUT"/*.rpm
)
shopt -u nullglob

for artifact in "${all_artifacts[@]}"; do
  [[ -s "$artifact" ]] || die "empty artifact: $artifact"
  echo "-- ${artifact#"$ROOT"/}"
done

if [[ "$run_policy" == "$RUN_PREVIEW" ]]; then
  exec npm run preview
fi

if [[ "$host" == "$HOST_MACOS" ]] && command -v open >/dev/null 2>&1; then
  open -R "${all_artifacts[0]}"
fi

echo "==> done"
