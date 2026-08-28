#!/usr/bin/env bash
# Assemble and ad-hoc sign build/Sion.app.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly APP_ROOT="$REPOSITORY_ROOT/build/Sion.app"
readonly CONTENTS="$APP_ROOT/Contents"
readonly MACOS_DIR="$CONTENTS/MacOS"
readonly RESOURCES_DIR="$CONTENTS/Resources"
readonly HELP_BOOK_NAME="Sion.help"
readonly HELP_BOOK_SOURCE="$REPOSITORY_ROOT/Resources/$HELP_BOOK_NAME"
readonly HELP_BOOK_ROOT="$RESOURCES_DIR/$HELP_BOOK_NAME"
readonly HELP_BOOK_INFO="$HELP_BOOK_ROOT/Contents/Info.plist"
readonly HELP_LOCALIZATION="en.lproj"
readonly HELP_LOCALIZED_RESOURCES="$HELP_BOOK_ROOT/Contents/Resources/$HELP_LOCALIZATION"
readonly HELP_INDEX_NAME="Sion.helpindex"
readonly HELP_INDEX_PATH="$HELP_LOCALIZED_RESOURCES/$HELP_INDEX_NAME"
readonly HELP_INDEXER="/usr/bin/hiutil"
readonly PLIST_BUDDY="/usr/libexec/PlistBuddy"
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

# Index a fresh bundled copy so source control never carries generated data.
ditto "$HELP_BOOK_SOURCE" "$HELP_BOOK_ROOT"
app_version="$($PLIST_BUDDY -c 'Print :CFBundleShortVersionString' "$CONTENTS/Info.plist")"
app_build="$($PLIST_BUDDY -c 'Print :CFBundleVersion' "$CONTENTS/Info.plist")"
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $app_version" "$HELP_BOOK_INFO"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $app_build" "$HELP_BOOK_INFO"
"$HELP_INDEXER" -Caf "$HELP_INDEX_PATH" "$HELP_LOCALIZED_RESOURCES"

app_help_folder="$($PLIST_BUDDY -c 'Print :CFBundleHelpBookFolder' "$CONTENTS/Info.plist")"
app_help_name="$($PLIST_BUDDY -c 'Print :CFBundleHelpBookName' "$CONTENTS/Info.plist")"
book_identifier="$($PLIST_BUDDY -c 'Print :CFBundleIdentifier' "$HELP_BOOK_INFO")"
book_access_path="$($PLIST_BUDDY -c 'Print :HPDBookAccessPath' "$HELP_BOOK_INFO")"

[[ "$app_help_folder" == "$HELP_BOOK_NAME" ]]
[[ "$app_help_name" == "$book_identifier" ]]
[[ -f "$HELP_LOCALIZED_RESOURCES/$book_access_path" ]]
[[ -s "$HELP_INDEX_PATH" ]]

codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP_ROOT"
codesign --verify --deep --strict "$APP_ROOT"

echo "$APP_ROOT"
