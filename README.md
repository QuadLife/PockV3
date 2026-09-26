<p align="center"><b>Pock v3</b></p>
<p align="center">A maintained fork of <a href="https://github.com/konstantintuev/PockV2">PockV2</a> (Touch Bar widgets for macOS), with fixes for recent macOS versions.</p>

## What changed vs. PockV2

1. **Battery turns yellow in Low Power Mode** (économie d'énergie), like the macOS menu bar.
   The state is read through `pmset`, because the IOKit power source snapshot the system
   provides is throttled to ~30 seconds for data that does not fire a notification.
2. **Fixed the charging icon**: while plugged in, the battery now shows its real fill
   level with a lightning bolt, instead of an empty-looking battery.
3. **Now Playing widget works again on recent macOS** (tested on macOS 27). Apple's
   private `MediaRemote` framework no longer answers third-party apps on recent macOS
   versions, so Pock v3 reads Apple Music and Spotify metadata through AppleScript
   instead (title, artist, artwork, play/pause and track controls included).
4. **Tap the battery icon to toggle Low Power Mode** on/off.

## Installation

1. Download the latest build, move `PockV3.app` to your `Applications` folder and open it.
2. If macOS refuses to open the app (unsigned developer), right-click the app → **Open**,
   or run `xattr -d com.apple.quarantine /Applications/PockV3.app` in the Terminal.
3. If you don't see Pock in the Touch Bar, go to **System Settings → Keyboard** and set
   "Touch Bar shows: App Controls".
4. Grant the **Automation** permission for Music/Spotify when asked (Now Playing widget).

## Low Power Mode helper (tap to toggle)

Toggling Low Power Mode requires root privileges, so the first time you tap the battery
icon, macOS asks **once** for your admin password to install two tiny LaunchDaemons:

- `/Library/LaunchDaemons/ch.pock.lpm.on.plist`
- `/Library/LaunchDaemons/ch.pock.lpm.off.plist`

Each daemon watches a small marker file (`/private/var/tmp/pock.lpm.on` / `.off`). When
Pock writes to it, the daemon runs `pmset -a lowpowermode 1` (or `0`) as root. After that
one-time installation, toggling is instant and never asks for a password again.

To uninstall the helper:

```bash
sudo launchctl bootout system/ch.pock.lpm.on
sudo launchctl bootout system/ch.pock.lpm.off
sudo rm /Library/LaunchDaemons/ch.pock.lpm.on.plist /Library/LaunchDaemons/ch.pock.lpm.off.plist
sudo rm /private/var/tmp/pock.lpm.on /private/var/tmp/pock.lpm.off
```

## Build from source

```bash
git clone https://github.com/QuadLife/PockV3.git
cd PockV3
pod install
open PockV3.xcworkspace
```

Then build the `PockV3` scheme (deployment target: macOS 10.13+).

## Issue resolving

If some Control Center widgets (e.g. volume up/down) don't work, remove the app from
Accessibility and Screen Recording in System Settings and add it again. If it still
doesn't work, run `sudo tccutil reset All` in the Terminal, restart, then grant the
needed permissions again.

## Credits & license

Pock v3 is built on the work of many projects, all under the MIT license — see `LICENSE`:

- [Pock](https://github.com/pigigaldi/Pock) by Pierluigi Galdi (original project)
- [PockV2](https://github.com/konstantintuev/PockV2) by Konstantin Touev (direct ancestor)
- [Apple Juice](https://github.com/raphaelhanneken/apple-juice) by Raphael Hanneken (battery tools)
- [Music Bar](https://github.com/musa11971/Music-Bar) by Musa (iTunes Search API artwork)
- [Kawa](https://github.com/herrkaefer/kawa) by Hyunje Jun