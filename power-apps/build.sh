#!/bin/bash
# Builds four tiny apps (Lock, Sleep, Restart, Shut Down) that MTMR's dock can pin.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:-$HOME/Applications/MTMR Power}"
mkdir -p "$OUT"
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

mk() { # name bundle-id icon script
  app="$OUT/$1.app"; mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$1</string><key>CFBundleDisplayName</key><string>$1</string>
<key>CFBundleIdentifier</key><string>$2</string><key>CFBundleExecutable</key><string>run</string>
<key>CFBundleIconFile</key><string>icon</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string><key>LSUIElement</key><true/>
</dict></plist>
PLIST
  printf '#!/bin/bash\n%s\n' "$4" > "$app/Contents/MacOS/run"; chmod +x "$app/Contents/MacOS/run"
  is="$(mktemp -d)/icon.iconset"; mkdir -p "$is"
  for s in 16 32 64 128 256 512; do
    sips -z $s $s "$HERE/icons/$3.png" --out "$is/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$HERE/icons/$3.png" --out "$is/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$is" -o "$app/Contents/Resources/icon.icns"
  "$LS" -f "$app"
}
CONFIRM='r=$(/usr/bin/osascript -e '"'"'button returned of (display dialog "%s this Mac?" buttons {"Cancel","%s"} default button "Cancel" with icon caution giving up after 15)'"'"'); [ "$r" = "%s" ] && /usr/bin/osascript -e '"'"'tell application "System Events" to %s'"'"
mk "Lock"      com.mtmrsetup.power.lock     pw_lock    '/usr/bin/pmset displaysleepnow'
mk "Sleep"     com.mtmrsetup.power.sleep    pw_sleep   '/usr/bin/pmset sleepnow'
mk "Restart"   com.mtmrsetup.power.restart  pw_restart "$(printf "$CONFIRM" "Restart" "Restart" "Restart" "restart")"
mk "Shut Down" com.mtmrsetup.power.shutdown pw_power   "$(printf "$CONFIRM" "Shut down" "Shut Down" "Shut Down" "shut down")"
echo "Built power apps in: $OUT"
