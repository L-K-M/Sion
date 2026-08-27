#!/usr/bin/env bash
# Assemble and ad-hoc sign build/Sion.app.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly APP_ROOT="$REPOSITORY_ROOT/build/Sion.app"
readonly CONTENTS="$APP_ROOT/Contents"
readonly MACOS_DIR="$CONTENTS/MacOS"
readonly RESOURCES_DIR="$CONTENTS/Resources"
readonly HOST_MACOS="Darwin"

if [[ "$(uname -s)" != "$HOST_MACOS" ]]; then
  echo "App packaging requires macOS." >&2
  exit 1
fi

cd "$REPOSITORY_ROOT"
swift build -c release --product Sion
binary_dir="$(swift build -c release --show-bin-path)"

rm -rf -- "$APP_ROOT"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$binary_dir/Sion" "$MACOS_DIR/Sion"
cp "$REPOSITORY_ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$REPOSITORY_ROOT/LICENSE" "$RESOURCES_DIR/LICENSE.txt"
swift "$REPOSITORY_ROOT/scripts/generate-icons.swift" "$RESOURCES_DIR"

codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP_ROOT"
codesign --verify --deep --strict "$APP_ROOT"

echo "$APP_ROOT"
