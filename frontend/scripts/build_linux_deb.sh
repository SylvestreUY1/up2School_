#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v dpkg-deb >/dev/null 2>&1; then
  echo "dpkg-deb est requis pour générer le paquet .deb."
  exit 1
fi

APP_NAME="up2school"
DISPLAY_NAME="UY1-Lib"
VERSION="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml | head -n1)"
ARCH="$(dpkg --print-architecture)"
BUILD_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
STAGING_ROOT="$ROOT_DIR/build/linux/deb-staging"
PACKAGE_DIR="$STAGING_ROOT/${APP_NAME}_${VERSION}_${ARCH}"
OUTPUT_DIR="$ROOT_DIR/build/linux/deb"
CONTROL_TEMPLATE="$ROOT_DIR/packaging/linux/control.in"
DESKTOP_FILE="$ROOT_DIR/packaging/linux/up2school.desktop"
ICON_SOURCE="$ROOT_DIR/assets/images/icon.png"

if [[ -z "$VERSION" ]]; then
  echo "Impossible de lire la version depuis pubspec.yaml."
  exit 1
fi

flutter build linux --release

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/DEBIAN"
mkdir -p "$PACKAGE_DIR/opt/$APP_NAME"
mkdir -p "$PACKAGE_DIR/usr/share/applications"
mkdir -p "$PACKAGE_DIR/usr/share/icons/hicolor/256x256/apps"

cp -R "$BUILD_DIR/." "$PACKAGE_DIR/opt/$APP_NAME/"
cp "$DESKTOP_FILE" "$PACKAGE_DIR/usr/share/applications/${APP_NAME}.desktop"
cp "$ICON_SOURCE" "$PACKAGE_DIR/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"

sed \
  -e "s/@VERSION@/$VERSION/g" \
  -e "s/@ARCH@/$ARCH/g" \
  "$CONTROL_TEMPLATE" > "$PACKAGE_DIR/DEBIAN/control"

chmod 0755 "$PACKAGE_DIR/opt/$APP_NAME/$APP_NAME"
chmod 0644 "$PACKAGE_DIR/usr/share/applications/${APP_NAME}.desktop"
chmod 0644 "$PACKAGE_DIR/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
chmod 0644 "$PACKAGE_DIR/DEBIAN/control"

mkdir -p "$OUTPUT_DIR"
dpkg-deb --build --root-owner-group "$PACKAGE_DIR" "$OUTPUT_DIR/${APP_NAME}_${VERSION}_${ARCH}.deb"

echo
echo "Paquet Debian généré : $OUTPUT_DIR/${APP_NAME}_${VERSION}_${ARCH}.deb"
echo "Nom affiché : $DISPLAY_NAME"
