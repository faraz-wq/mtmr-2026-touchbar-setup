# MTMR 2026 Touch Bar setup

A Touch Bar setup for the MTMR 2026 app (a modern build of My TouchBar My Rules, bundle ID `com.mtmr-designer.mtmr2026`) on macOS 26 (Tahoe), plus three small helper programs that add things MTMR can't do on its own.

Built and used on a MacBook Pro with a Touch Bar running macOS 26. It uses private macOS APIs in a few places (see [Limits](#limits)), so expect it to need attention after macOS updates.

## What you get

**Main bar (MTMR config, `config/items.json`)**
- App dock (collapsed list, and an expanded "All" view)
- Lock / Sleep / Restart / Shut Down pinned in the dock as tiny apps (Restart and Shut Down ask for confirmation)
- Centered now-playing item for **YouTube and YouTube Music in Brave or Chrome**, with a text progress line
- Previous / next, volume and brightness buttons with custom SF Symbol icons

**`seekbar/`**: tap the now-playing item to get a real draggable seek slider (system-modal Touch Bar). Long-press plays/pauses.

**`volhud/`**: changes volume or brightness instantly and shows a small Liquid Glass overlay at the top right. Repeated presses update in place without blinking.

**`modbar/` (MTMR Modbar.app)**: a background app that shows a different Touch Bar while you hold a single modifier key (after about 0.35 s):

| Hold | Shows |
|---|---|
| Control | Your Spaces with the icons of the apps in each; tap to switch |
| Command | Screenshot buttons (area / screen / window, all copied to the clipboard, plus the Screenshot toolbar for recording) and a scrollable clipboard history (text and images); tap to paste |
| Option | Window quarters, Wi-Fi toggle, Dark mode toggle |

## Requirements
- A Mac with a Touch Bar, macOS 26
- MTMR 2026 installed in `/Applications`
- Xcode command line tools (`xcode-select --install`) for `swiftc`

## Install

```bash
git clone https://github.com/faraz-wq/mtmr-2026-touchbar-setup.git
cd mtmr-2026-touchbar-setup
./scripts/make-cert.sh   # optional but recommended, see "Permissions"
./install.sh
```

`install.sh` builds the helpers, installs Modbar to `/Applications`, builds the power apps, backs up your existing `items.json`, installs this one, and pins the power apps in the MTMR dock. Then quit and reopen MTMR 2026.

Don't run `install.sh` on top of a config you care about without reading it first. It overwrites `items.json` (a timestamped backup is kept).

## Permissions

Grant these in System Settings → Privacy & Security:

| Permission | App | Needed for |
|---|---|---|
| Accessibility | MTMR Modbar | Window quarters, auto-paste from clipboard history |
| Screen & System Audio Recording | MTMR Modbar | Screenshot buttons |
| Automation (System Events) | MTMR Modbar | Dark mode toggle (asked on first use) |

macOS ties these grants to the app's code signature. An ad-hoc signature changes on every rebuild, which silently drops the grants. `scripts/make-cert.sh` creates a local self-signed code-signing certificate ("Modbar Local") in your login keychain so the grants survive rebuilds. It asks for your password to trust the certificate.

If Modbar doesn't appear in the Accessibility list, quit System Settings, then drag the app from `/Applications` into the list instead of using the `+` button.

## Troubleshooting MTMR 2026

- **MTMR 2026 keeps asking for Accessibility** even though it's switched on. Check `codesign --verify --deep --strict "/Applications/MTMR 2026.app"`. If it says "not signed at all", the bundled `Sparkle.framework` may have lost its symlinks (copied without preserving them). Restore `Versions/Current -> B` and the top-level symlinks, then re-sign with `codesign --force --deep --sign - --identifier com.mtmr-designer.mtmr2026 "/Applications/MTMR 2026.app"`, reset its permission with `tccutil reset Accessibility com.mtmr-designer.mtmr2026`, and grant it again.
- **The built-in MTMR volume/brightness buttons do nothing.** They send media keys, which need that Accessibility grant. This setup avoids them: volume uses CoreAudio and brightness uses DisplayServices, both through `volhud`.
- **`killall TouchBarServer` finds nothing.** It runs as root: `sudo pkill TouchBarServer`. MTMR may crash when it restarts; relaunch it.

## Limits
- Now playing only reads YouTube / YouTube Music tabs in Brave or Chrome. Chrome/Brave need View → Developer → Allow JavaScript from Apple Events.
- The progress line is text. MTMR 2026 can't set font size or draw two rows.
- Spaces, brightness and the modal Touch Bars use private APIs (SkyLight, DisplayServices, `presentSystemModalTouchBar`) and may break on macOS updates.
- Spaces switching works on the main display only.
- Clipboard history is in memory only, text and images, max 30 items, and clears when Modbar restarts. Items marked concealed or transient (password managers) are skipped.
- Modbar does not start at login. Add it under System Settings → General → Login Items.

## Layout

```
config/items.json      MTMR config (paths use __MTMR_DIR__, filled in by install.sh)
seekbar/               draggable seek slider
volhud/                volume/brightness + overlay
modbar/                modifier-key Touch Bars
power-apps/            Lock / Sleep / Restart / Shut Down apps for the dock
scripts/make-cert.sh   local code-signing certificate
install.sh
```

## License
MIT
