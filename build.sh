#!/bin/zsh
# Robo Süpürge.app paketini derler.
set -euo pipefail
cd "$(dirname "$0")"

APP="Robo Süpürge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework QuartzCore -framework Metal -framework CoreServices -framework PDFKit -framework ImageIO -framework AVFoundation -framework CoreMedia -framework Carbon \
  Sources/*.swift Sources/BlackHole/*.swift Sources/DevCenter/*.swift Sources/Clipboard/*.swift -o "$APP/Contents/MacOS/RoboSupurge"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Robo Süpürge</string>
  <key>CFBundleDisplayName</key><string>Robo Süpürge</string>
  <key>CFBundleIdentifier</key><string>local.robosupurge.app</string>
  <key>CFBundleExecutable</key><string>RoboSupurge</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>Robot, masaüstündeki ekran görüntülerini bulmak için bu izne ihtiyaç duyar.</string>
  <key>NSAppleEventsUsageDescription</key><string>Robot, masaüstü simgelerinin konumunu Finder'dan öğrenir ve çarptığı simgeleri yana iter.</string>
</dict></plist>
PLIST

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$APP/Contents/MacOS/RoboSupurge" --export-icons "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Hazır: $APP"
