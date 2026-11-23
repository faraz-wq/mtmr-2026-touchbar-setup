#!/bin/bash
# Installs the MTMR 2026 Touch Bar setup: helpers, Modbar app, power apps and items.json.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
MTMR_DIR="$HOME/Library/Application Support/MTMR"
MODBAR_APP="/Applications/MTMR Modbar.app"
mkdir -p "$MTMR_DIR"

echo "==> Building helpers"
for h in seekbar volhud; do swiftc -O "$ROOT/$h/main.swift" -o "$MTMR_DIR/$h"; done

echo "==> Building Modbar.app"
swiftc -O "$ROOT/modbar/main.swift" -o "$ROOT/modbar/modbar"
pkill -x modbar 2>/dev/null || true; sleep 1
mkdir -p "$MODBAR_APP/Contents/MacOS"
cp "$ROOT/modbar/modbar" "$MODBAR_APP/Contents/MacOS/modbar"
cat > "$MODBAR_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MTMR Modbar</string><key>CFBundleIdentifier</key><string>com.mtmrsetup.modbar</string>
<key>CFBundleExecutable</key><string>modbar</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string><key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Toggle dark mode from the Touch Bar.</string>
</dict></plist>
PLIST
if security find-identity -v -p codesigning | grep -q "Modbar Local"; then
  codesign --force --sign "Modbar Local" --identifier com.mtmrsetup.modbar "$MODBAR_APP"
else
  echo "   (no 'Modbar Local' certificate: run scripts/make-cert.sh so macOS keeps Modbar's permissions)"
  codesign --force --sign - --identifier com.mtmrsetup.modbar "$MODBAR_APP"
fi

echo "==> Building power apps"
"$ROOT/power-apps/build.sh"

echo "==> Installing config"
if [ -f "$MTMR_DIR/items.json" ]; then cp "$MTMR_DIR/items.json" "$MTMR_DIR/items.json.backup-$(date +%Y%m%d-%H%M%S)"; fi
sed "s#__MTMR_DIR__#$MTMR_DIR#g" "$ROOT/config/items.json" > "$MTMR_DIR/items.json"

echo "==> Pinning power apps in the MTMR dock"
defaults write com.mtmr-designer.mtmr2026 com.toxblh.mtmr.dock.persistent -array \
  com.mtmrsetup.power.lock com.mtmrsetup.power.sleep com.mtmrsetup.power.restart com.mtmrsetup.power.shutdown

echo "==> Adding Modbar to login items"
osascript -e 'tell application "System Events" to if not (exists login item "MTMR Modbar") then make login item at end with properties {path:"/Applications/MTMR Modbar.app", hidden:true, name:"MTMR Modbar"}' || echo "   (could not add the login item; add it in System Settings > General > Login Items)"

open "$MODBAR_APP"
echo
echo "Done. Quit and reopen MTMR 2026, then grant Modbar its permissions (see README)."
