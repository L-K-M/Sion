#!/usr/bin/env bash
# Builds verified, unsigned Thalyx packages for the current macOS or Linux host.
# Installs the lockfile, runs the local CI gate, packages every configured format,
# and rejects missing artifacts. --install copies the native macOS app to
# /Applications/Thalyx.app. --clean removes only out/ and release/ first.
#
# Usage: scripts/build.sh [--clean] [--run] [--install] [--check]
# Requirements: Node.js 24+, npm 11+; Linux needs xz-utils, binutils, and rpm.
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"
cd "$ROOT"

readonly ACTION_BUILD="build"
readonly ACTION_CHECK="check"
readonly CLEAN_KEEP="keep"
readonly CLEAN_REMOVE="remove"
readonly INSTALL_COPY="copy"
readonly INSTALL_SKIP="skip"
readonly RUN_PREVIEW="preview"
readonly RUN_SKIP="skip"
readonly HOST_MACOS="Darwin"
readonly HOST_LINUX="Linux"
readonly MAC_ARCH_ARM64="arm64"
readonly MAC_ARCH_X64="x86_64"
readonly MIN_NODE_MAJOR=24
readonly MIN_NODE_MINOR=0
readonly MIN_NPM_MAJOR=11
readonly BUILD_OUTPUT="$ROOT/out"
readonly PACKAGE_OUTPUT="$ROOT/release"
readonly PRODUCT_NAME="Thalyx"
readonly INSTALL_TARGET="/Applications/${PRODUCT_NAME}.app"
readonly MAC_OUTPUT_ARM64="$PACKAGE_OUTPUT/mac-arm64"
readonly MAC_OUTPUT_X64="$PACKAGE_OUTPUT/mac"
readonly MAC_APP_ARM64="$MAC_OUTPUT_ARM64/${PRODUCT_NAME}.app"
readonly MAC_APP_X64="$MAC_OUTPUT_X64/${PRODUCT_NAME}.app"

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

native_macos_app() {
  local architecture
  architecture="$(uname -m)"

  case "$architecture" in
    "$MAC_ARCH_ARM64") echo "$MAC_APP_ARM64" ;;
    "$MAC_ARCH_X64") echo "$MAC_APP_X64" ;;
    *) die "unsupported macOS architecture: $architecture" ;;
  esac
}

install_macos_app() {
  local source_app
  source_app="$(native_macos_app)"
  [[ -d "$source_app" ]] || die "missing native app: $source_app"

  require_command ditto
  echo "==> install"
  rm -rf -- "$INSTALL_TARGET"
  ditto "$source_app" "$INSTALL_TARGET"
  [[ -d "$INSTALL_TARGET" ]] || die "install failed: $INSTALL_TARGET"
  echo "-- $INSTALL_TARGET"
}

action="$ACTION_BUILD"
clean_policy="$CLEAN_KEEP"
install_policy="$INSTALL_SKIP"
run_policy="$RUN_SKIP"

for argument in "$@"; do
  case "$argument" in
    --clean) clean_policy="$CLEAN_REMOVE" ;;
    --run) run_policy="$RUN_PREVIEW" ;;
    --install) install_policy="$INSTALL_COPY" ;;
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

if [[ "$install_policy" == "$INSTALL_COPY" && "$host" != "$HOST_MACOS" ]]; then
  die "--install is available only on macOS"
fi

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
  if [[ "$install_policy" == "$INSTALL_COPY" ]]; then
    echo "-- install:  $(native_macos_app) -> $INSTALL_TARGET"
  fi
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

if [[ "$install_policy" == "$INSTALL_COPY" ]]; then
  rm -rf -- "$MAC_OUTPUT_ARM64" "$MAC_OUTPUT_X64"
fi

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

reveal_target="${all_artifacts[0]}"
if [[ "$install_policy" == "$INSTALL_COPY" ]]; then
  install_macos_app
  reveal_target="$INSTALL_TARGET"
fi

if [[ "$run_policy" == "$RUN_PREVIEW" ]]; then
  if [[ "$install_policy" == "$INSTALL_COPY" ]]; then
    require_command open
    exec open "$INSTALL_TARGET"
  fi

  exec npm run preview
fi

if [[ "$host" == "$HOST_MACOS" ]] && command -v open >/dev/null 2>&1; then
  open -R "$reveal_target"
fi

echo "==> done"
