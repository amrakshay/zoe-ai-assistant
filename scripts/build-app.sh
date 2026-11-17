#!/bin/sh
# Builds dist/Zoe.app (release) and signs it.
#   Version:  CFBundleShortVersionString from version.txt (managed by release-please);
#             CFBundleVersion from $ZOE_BUILD_NUMBER, else the git commit count.
#   Core:     the Python core's source goes into Contents/Resources/core; on launch, core/launch.sh syncs its
#             environment with uv into ~/Library/Application Support/Zoe/core-venv (so the cask needs uv).
#   Signing:  ad-hoc by default (releases are free and not notarized). Set $ZOE_SIGN_IDENTITY to a local
#             self-signed code-signing identity to keep Microphone and Accessibility grants across rebuilds.
set -eu
cd "$(dirname "$0")/.."
swift build -c release --product Zoe
VERSION=$(tr -d '[:space:]' < version.txt)
BUILD=${ZOE_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
APP=dist/Zoe.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/core"
cp .build/release/Zoe "$APP/Contents/MacOS/Zoe"

# The core: source, lock file and launcher only (no venv, tests or caches).
cp core/pyproject.toml core/uv.lock core/launch.sh "$APP/Contents/Resources/core/"
rsync -a --exclude '__pycache__' --exclude '*.pyc' core/src "$APP/Contents/Resources/core/"

# App icon (generated once, then reused).
if [ ! -f Resources/AppIcon.icns ]; then
  ICONSET=.build/AppIcon.iconset
  rm -rf "$ICONSET"
  mkdir -p Resources
  swift scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>io.github.amrakshay.zoe</string>
  <key>CFBundleName</key><string>Zoe</string>
  <key>CFBundleDisplayName</key><string>Zoe</string>
  <key>CFBundleExecutable</key><string>Zoe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Akshay Rahatwal · MIT License</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Zoe listens only while you hold the talk key or are in a conversation. Audio stays on this Mac and is never stored.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Zoe shows live captions of what you say, recognised on this Mac.</string>
</dict>
</plist>
PLIST
IDENTITY="${ZOE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
echo "Built $APP $VERSION ($BUILD), signed with: $IDENTITY"
ls -lh "$APP/Contents/MacOS/Zoe" | awk '{print "binary size:", $5}'
