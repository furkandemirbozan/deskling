#!/bin/zsh
# Deskling.app paketini derler.
set -euo pipefail
cd "$(dirname "$0")"

APP="Deskling.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -framework AppKit -framework SwiftUI -framework QuartzCore -framework Metal -framework CoreServices -framework PDFKit -framework ImageIO -framework AVFoundation -framework CoreMedia -framework Carbon -framework IOKit -framework UserNotifications -framework CoreAudio \
  Sources/*.swift Sources/BlackHole/*.swift Sources/DevCenter/*.swift Sources/Clipboard/*.swift Sources/Pomodoro/*.swift Sources/Island/*.swift Sources/Disk/*.swift Sources/Keys/*.swift -o "$APP/Contents/MacOS/Deskling"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Deskling</string>
  <key>CFBundleDisplayName</key><string>Deskling</string>
  <key>CFBundleIdentifier</key><string>local.deskling.app</string>
  <key>CFBundleExecutable</key><string>Deskling</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSDesktopFolderUsageDescription</key><string>Robot, masaüstündeki ekran görüntülerini bulmak için bu izne ihtiyaç duyar.</string>
  <key>NSAppleEventsUsageDescription</key><string>Robot, masaüstü simgelerinin konumunu Finder'dan öğrenir ve çarptığı simgeleri yana iter. Dinamik ada, Müzik, Spotify ve tarayıcıdaki müzik sekmelerinde çalan parçayı gösterir ve denetler.</string>
</dict></plist>
PLIST

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$APP/Contents/MacOS/Deskling" --export-icons "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Hazır: $APP"
