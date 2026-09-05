#!/usr/bin/env bash
# Assemble build/linux/root and package it as build/linux/sion_<version>_<arch>.deb.
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly BUILD_ROOT="$REPOSITORY_ROOT/build/linux"
readonly STAGE="$BUILD_ROOT/root"
readonly INFO_PLIST="$REPOSITORY_ROOT/Resources/Info.plist"
readonly HELP_SOURCE="$REPOSITORY_ROOT/Resources/Sion.help/Contents/Resources/en.lproj/index.html"
readonly PACKAGING="$REPOSITORY_ROOT/packaging/linux"
readonly PACKAGE_NAME="sion"
readonly APP_ID="ch.lkmc.Sion"
readonly HOST_LINUX="Linux"
readonly VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
readonly MAINTAINER="${SION_DEB_MAINTAINER:-L-K-M <noreply@github.com>}"

if [[ "$(uname -s)" != "$HOST_LINUX" ]]; then
  echo "Debian packaging requires Linux." >&2
  exit 1
fi

for tool in swift dpkg-deb dpkg strip gzip readelf ldconfig; do
  if ! command -v "$tool" >/dev/null; then
    echo "Missing tool: $tool" >&2
    exit 1
  fi
done

# The macOS Info.plist is the single source of the version; both applications
# stamp the same number into the archives they write.
plist_string() {
  awk -v key="<key>$1</key>" '
    found && /<string>/ { gsub(/.*<string>|<\/string>.*/, ""); print; exit }
    index($0, key) { found = 1 }
  ' "$INFO_PLIST"
}

version="$(plist_string CFBundleShortVersionString)"
if [[ ! "$version" =~ $VERSION_PATTERN ]]; then
  echo "CFBundleShortVersionString must use X.Y.Z; found '$version'." >&2
  exit 1
fi
architecture="$(dpkg --print-architecture)"

cd "$REPOSITORY_ROOT"
swift build -c release --product sion --static-swift-stdlib
swift build -c release --product sion-icon-tool --static-swift-stdlib
binary_dir="$(swift build -c release --show-bin-path)"

rm -rf -- "$STAGE"
mkdir -p "$STAGE/DEBIAN"

install -D -m 0755 "$binary_dir/sion" "$STAGE/usr/bin/sion"
strip --strip-unneeded "$STAGE/usr/bin/sion"

"$binary_dir/sion-icon-tool" "$STAGE/usr/share/icons"
find "$STAGE/usr/share/icons" -type f -exec chmod 0644 {} +

install -D -m 0644 "$PACKAGING/$APP_ID.desktop" "$STAGE/usr/share/applications/$APP_ID.desktop"
install -D -m 0644 "$PACKAGING/$APP_ID.xml" "$STAGE/usr/share/mime/packages/$APP_ID.xml"
install -D -m 0644 "$PACKAGING/$APP_ID.metainfo.xml" \
  "$STAGE/usr/share/metainfo/$APP_ID.metainfo.xml"
install -D -m 0644 "$INFO_PLIST" "$STAGE/usr/share/sion/Info.plist"
install -D -m 0644 "$PACKAGING/copyright" "$STAGE/usr/share/doc/$PACKAGE_NAME/copyright"

# The help book is shared with macOS; only platform words and system fonts change.
mkdir -p "$STAGE/usr/share/sion/help"
sed \
  -e '/name="AppleTitle"/d' \
  -e 's/<kbd>Command-/<kbd>Ctrl-/g' \
  -e 's/from the Finder/from your file manager/g' \
  -e 's/font: -apple-system-body;/font: 1rem system-ui, sans-serif;/' \
  -e 's/font: -apple-system-title1;/font: 700 1.75rem system-ui, sans-serif;/' \
  -e 's/font: -apple-system-headline;/font: 600 1.1rem system-ui, sans-serif;/' \
  "$HELP_SOURCE" > "$STAGE/usr/share/sion/help/index.html"
chmod 0644 "$STAGE/usr/share/sion/help/index.html"
if grep -q 'Command-\|Finder\|-apple-system' "$STAGE/usr/share/sion/help/index.html"; then
  echo "The Linux help copy still contains macOS-only wording." >&2
  exit 1
fi

mkdir -p "$STAGE/usr/share/man/man1"
gzip -9n -c "$PACKAGING/sion.1" > "$STAGE/usr/share/man/man1/sion.1.gz"
chmod 0644 "$STAGE/usr/share/man/man1/sion.1.gz"

release_date="$(git -C "$REPOSITORY_ROOT" log -1 --format=%cD 2>/dev/null || date -R)"
{
  echo "$PACKAGE_NAME ($version) unstable; urgency=medium"
  echo
  echo "  * Sion $version."
  echo
  echo " -- $MAINTAINER  $release_date"
} | gzip -9n > "$STAGE/usr/share/doc/$PACKAGE_NAME/changelog.gz"
chmod 0644 "$STAGE/usr/share/doc/$PACKAGE_NAME/changelog.gz"

# Runtime dependencies come from the linked libraries on this machine, the way
# dpkg-shlibdeps derives them, plus the loaders the canvas needs for pasted
# SVG and the minimum toolkit versions the code calls into.
needed_packages=()
while read -r library; do
  path="$(ldconfig -p | awk -v name="$library" '$1 == name { print $NF; exit }')"
  if [[ -z "$path" ]]; then
    echo "Cannot locate $library on this machine." >&2
    exit 1
  fi
  package="$(dpkg -S "$(readlink -f "$path")" | head -n 1 | cut -d: -f1)"
  if [[ -z "$package" ]]; then
    echo "No Debian package owns $path." >&2
    exit 1
  fi
  case "$package" in
    libgtk-4-1) package="libgtk-4-1 (>= 4.10)" ;;
    libadwaita-1-0) package="libadwaita-1-0 (>= 1.5)" ;;
  esac
  needed_packages+=("$package")
done < <(readelf -d "$STAGE/usr/bin/sion" | awk '/NEEDED/ { gsub(/[\[\]]/, "", $5); print $5 }')
needed_packages+=("librsvg2-common" "shared-mime-info" "hicolor-icon-theme")
depends="$(printf '%s\n' "${needed_packages[@]}" | sort -u | paste -sd, - | sed 's/,/, /g')"

installed_size="$(du -sk --exclude=DEBIAN "$STAGE" | cut -f1)"

cat > "$STAGE/DEBIAN/control" <<CONTROL
Package: $PACKAGE_NAME
Version: $version
Section: graphics
Priority: optional
Architecture: $architecture
Maintainer: $MAINTAINER
Installed-Size: $installed_size
Depends: $depends
Recommends: webp-pixbuf-loader
Homepage: https://github.com/L-K-M/Sion
Description: native diagramming and digital illustration
 Sion opens directly onto a canvas. Shapes get useful typography, shadows,
 and connection magnets by default. Connection points are directly editable,
 and connectors preview their routed path before placement.
 .
 Drawings are .sion archives containing the editable scene, original assets,
 standalone SVG, Mermaid, and retained history, shared with the macOS
 application.
CONTROL

find "$STAGE" -type d -exec chmod 0755 {} +

package_path="$BUILD_ROOT/${PACKAGE_NAME}_${version}_${architecture}.deb"
rm -f -- "$package_path"
dpkg-deb --root-owner-group -b "$STAGE" "$package_path" >/dev/null

if command -v lintian >/dev/null; then
  lintian --fail-on error "$package_path"
fi

echo "$package_path"
