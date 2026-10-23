#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' /tmp/sparky-build/Sparky.app/Contents/Info.plist)
mkdir -p dist
STAGING=$(mktemp -d /tmp/sparky-dmg.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
ditto /tmp/sparky-build/Sparky.app "$STAGING/Sparky.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/安装说明.txt" <<'TEXT'
将 Sparky.app 拖入 Applications（应用程序），再从应用程序中打开。
升级时先退出旧版，避免同时运行 Spark / Sparky。
Apple Silicon Mac，macOS 14 或更新版本。
本测试版使用本地签名，未经过 Apple 公证；如被系统拦截，可在“隐私与安全性”中允许该应用。
TEXT
hdiutil create -volname Sparky -srcfolder "$STAGING" -ov -format UDZO "dist/Sparky-${VERSION}-mac-arm64.dmg"
