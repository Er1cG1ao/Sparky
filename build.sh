#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP=/tmp/sparky-build/Sparky.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/swift-cache
/usr/bin/swiftc -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path build/swift-cache -O -framework AppKit -framework WebKit -framework SwiftUI -framework ServiceManagement Sources/*.swift -o "$APP/Contents/MacOS/Sparky"
cp Resources/* "$APP/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Sparky</string>
<key>CFBundleIdentifier</key><string>local.giao.spark.webkit.prototype</string>
<key>CFBundleIconFile</key><string>Sparky</string>
<key>CFBundleName</key><string>Sparky</string>
<key>CFBundleDisplayName</key><string>Sparky</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.4</string>
<key>CFBundleVersion</key><string>34</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP"
print "$APP"
