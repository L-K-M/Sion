#!/usr/bin/env bash
# Verify Sion and package the native Linux application as a .deb.
# Usage: scripts/build-linux.sh [--clean] [--run] [--install]
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly BUILD_ROOT="$REPOSITORY_ROOT/build/linux"
readonly STAGE_ROOT="$BUILD_ROOT/root"
readonly HOST_LINUX="Linux"

clean_requested=0
run_requested=0
install_requested=0

for argument in "$@"; do
  case "$argument" in
    --clean) clean_requested=1 ;;
    --run) run_requested=1 ;;
    --install) install_requested=1 ;;
    -h|--help) sed -n '2,3s/^# //p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $argument" >&2; exit 2 ;;
  esac
done

if [[ "$(uname -s)" != "$HOST_LINUX" ]]; then
  echo "Linux packaging requires Linux; scripts/build.sh builds the macOS app." >&2
  exit 1
fi

cd "$REPOSITORY_ROOT"

if ((clean_requested)); then
  swift package clean
  rm -rf -- "$BUILD_ROOT"
fi

# GTK tests skip themselves without a display; CI runs them under xvfb-run.
swift test

"$SCRIPT_DIR/make-deb.sh"

if ((install_requested)); then
  package_path="$(ls -1 "$BUILD_ROOT"/sion_*.deb | head -n 1)"
  if [[ "$(id -u)" == "0" ]]; then
    dpkg -i "$package_path"
  else
    sudo dpkg -i "$package_path"
  fi
fi

if ((run_requested)); then
  SION_RESOURCE_ROOT="$STAGE_ROOT/usr/share/sion" "$STAGE_ROOT/usr/bin/sion" &
fi
