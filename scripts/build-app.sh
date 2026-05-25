#!/bin/bash
# Build ClaudeUsageBar.app (a menu-bar-only app) and install the claude-usage CLI.
#
# Usage: scripts/build-app.sh
# Output: build/ClaudeUsageBar.app  and  ~/.local/bin/claude-usage
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="3.0.0"
APP_NAME="ClaudeUsageBar"
BUNDLE_ID="ch.ggtn.claude-usage-bar"
APP_DIR="build/${APP_NAME}.app"
CLI_DEST="${HOME}/.local/bin"

echo "==> Building release binaries"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
# Bundle the CLI too, so the .app is self-contained.
cp "${BIN_DIR}/claude-usage" "${APP_DIR}/Contents/MacOS/claude-usage"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Usage</string>
    <key>CFBundleDisplayName</key><string>Claude Usage</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Sign with a stable Developer identity when one exists. This is what makes the
# Keychain "Always Allow" grant persist across rebuilds — an ad-hoc signature's
# identity changes every build, so macOS would re-prompt for consent every time.
echo "==> Code signing"
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -oE '[0-9A-F]{40}' | head -1)"
if [ -n "${IDENTITY}" ]; then
    codesign --force --sign "${IDENTITY}" "${APP_DIR}/Contents/MacOS/claude-usage"
    codesign --force --sign "${IDENTITY}" "${APP_DIR}"
    echo "   signed with identity ${IDENTITY}"
else
    codesign --force --deep --sign - "${APP_DIR}" >/dev/null 2>&1 || true
    echo "   no Developer identity found — ad-hoc signed (macOS will re-prompt for Keychain access after each rebuild)"
fi

echo "==> Installing claude-usage CLI to ${CLI_DEST}"
mkdir -p "${CLI_DEST}"
cp "${BIN_DIR}/claude-usage" "${CLI_DEST}/claude-usage"

cat <<DONE

Done.

  App:  ${APP_DIR}
  CLI:  ${CLI_DEST}/claude-usage

Next steps:
  1. Move the app into place and launch it:
       cp -R "${APP_DIR}" /Applications/ && open "/Applications/${APP_NAME}.app"
  2. (Recommended) Wire up the free real-time feed via your status line.
     Add to ~/.claude/settings.json:
       "statusLine": { "type": "command", "command": "claude-usage statusline" }
  3. To launch at login: System Settings > General > Login Items > add the app.
DONE
