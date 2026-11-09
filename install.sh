#!/bin/bash
# Builds PDFReader.app from source and installs it into /Applications.
# Usage:  bash install.sh            (build + install + launch)
#         bash install.sh --build    (build only, into ./build)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="PDFReader"
APP="build/${APP_NAME}.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if ! command -v swiftc >/dev/null 2>&1; then
    echo "Swift compiler not found. Install Apple's Command Line Tools first:"
    echo "    xcode-select --install"
    echo "then run this script again."
    exit 1
fi

echo "==> Building ${APP_NAME}..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
swiftc -O -swift-version 5 \
    -target "$(uname -m)-apple-macos12.0" \
    -module-name "${APP_NAME}" \
    -framework AppKit -framework PDFKit -framework QuickLookThumbnailing -framework UniformTypeIdentifiers \
    Sources/*.swift \
    -o "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"
cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${APP}/Contents/PkgInfo"
codesign --force --sign - "${APP}" >/dev/null
echo "    Built ${APP}"

if [[ "${1:-}" == "--build" ]]; then exit 0; fi

DEST="/Applications"
if [[ ! -w "${DEST}" ]]; then DEST="$HOME/Applications"; mkdir -p "${DEST}"; fi

echo "==> Installing to ${DEST}/${APP_NAME}.app..."
osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
rm -rf "${DEST}/${APP_NAME}.app"
cp -R "${APP}" "${DEST}/"
"${LSREGISTER}" -f "${DEST}/${APP_NAME}.app" || true
# Only the installed copy should be registered. Other copies with the same bundle id
# (the ./build copy, old copies in the Trash) can be picked to open PDFs instead, and
# when that copy is rebuilt or gone, macOS falls back to Preview. The build copy is only
# an intermediate here, so remove it (macOS would register it again if it stayed).
"${LSREGISTER}" -u "${APP}" >/dev/null 2>&1 || true
rm -rf "${APP}"
"${LSREGISTER}" -u "$HOME/.Trash/${APP_NAME}.app" >/dev/null 2>&1 || true

echo "==> Launching ${APP_NAME}..."
open "${DEST}/${APP_NAME}.app"
echo
echo "Done. On first launch PDFReader will offer to become your default PDF app."
echo "(You can also do it any time from the PDFReader menu > Make PDFReader the Default PDF App.)"
