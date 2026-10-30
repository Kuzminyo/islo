#!/bin/bash
# Builds Islo.app into ./build.
#   ./build.sh          build for this Mac
#   ./build.sh install  also copy it to /Applications and launch
#   ./build.sh dist     universal (Apple Silicon + Intel) build, zipped into ./dist for sharing
set -euo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "dist" ]; then
    swift build -c release --arch arm64 --arch x86_64
    BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Islo"
else
    swift build -c release
    BINARY=.build/release/Islo
fi

if [ ! -f Resources/AppIcon.icns ]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    swift scripts/make-icon.swift "$ICONSET"
    iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi

APP=build/Islo.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "install" ]; then
    pkill -x Islo || true
    rm -rf /Applications/Islo.app
    cp -R "$APP" /Applications/
    open /Applications/Islo.app
    echo "Installed to /Applications/Islo.app"
fi

if [ "${1:-}" = "dist" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    rm -rf dist
    mkdir -p dist
    ditto -c -k --keepParent "$APP" "dist/Islo-$VERSION.zip"
    zip -qr "dist/Islo-$VERSION-source.zip" Package.swift build.sh README.md LICENSE .gitignore Sources Resources scripts
    echo "Packaged:"
    ls -lh dist
fi
