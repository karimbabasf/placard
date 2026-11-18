#!/bin/sh
# Builds Placard.app into build/ and, with --install, copies it to ~/Applications.
set -e
cd "$(dirname "$0")"
APP=build/Placard.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
  -framework AppKit -framework Carbon -framework ServiceManagement \
  Sources/*.swift -o "$APP/Contents/MacOS/Placard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
codesign --force --sign - "$APP" >/dev/null
echo "built $APP"
if [ "$1" = "--install" ]; then
  pkill -x Placard 2>/dev/null || true
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Placard.app"
  cp -R "$APP" "$HOME/Applications/Placard.app"
  install -m 755 bin/placard "$HOME/.local/bin/placard"
  open "$HOME/Applications/Placard.app"
  echo "installed ~/Applications/Placard.app and ~/.local/bin/placard"
fi
