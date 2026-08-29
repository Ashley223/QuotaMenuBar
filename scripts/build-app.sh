#!/bin/bash
# Build QuotaMenuBar.app (Release) from source into ./dist/.
# Requires Xcode (full IDE, not just Command Line Tools) for the macOS SDK.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! xcodebuild -version >/dev/null 2>&1; then
    echo "xcodebuild not found. Install Xcode from the App Store, then:" >&2
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
    exit 1
fi

echo "Building (Release)…"
rm -rf build dist
xcodebuild -project QuotaMenuBar.xcodeproj -scheme QuotaMenuBar \
    -configuration Release -derivedDataPath build \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    build

APP="build/Build/Products/Release/QuotaMenuBar.app"
mkdir -p dist
cp -R "$APP" dist/
# ad-hoc sign so it runs locally without a paid Developer ID
codesign --force --deep --sign - dist/QuotaMenuBar.app
( cd dist && zip -qry QuotaMenuBar.app.zip QuotaMenuBar.app )

echo
echo "Built: $ROOT/dist/QuotaMenuBar.app"
echo "Zip:   $ROOT/dist/QuotaMenuBar.app.zip"
echo
echo "This build is ad-hoc signed (no paid Apple Developer ID). On another Mac,"
echo "after downloading, clear the quarantine flag once:"
echo "  xattr -dr com.apple.quarantine /Applications/QuotaMenuBar.app"
