# GlitchOS TV installer

GlitchOS TV installer 1.0.0 brings **GlitchOS TV Edition 1.3.1** to a compatible Android TV: a remote-friendly home screen with a liquid-glass appearance, a direct Home-button configuration, reversible app cleanup and an optional repair for a specific CHiQ AirPlay receiver.

The configured system is fully working for the functions tested on the owner's **CHiQ TV, tentatively identified as L40G7B**, with verified firmware model **AI PONT running Android 14**: launcher navigation, app launching, direct Home, inputs, settings, and iPhone mirroring with picture, sound and rotation, including after a TV reboot. The retail model has not been independently checked against the physical label. This is a report for that unit and firmware, not a claim that every TV or streaming app is supported. See [tested devices and exact validation scope](docs/TESTED-DEVICES.md).

That TV was configured and tested before these public installer scripts were packaged. The public installer is checked with automated mock-device tests and a read-only device dry run; a complete installation through the public script has not yet been repeated on a TV.

GlitchOS is an Android launcher and a set of configuration tools. It does not replace the TV firmware or require rooting the TV.

## What you get

- A native Java launcher with app artwork, favorites, local app search, a clock, and shortcuts to inputs and TV settings.
- Glass-style translucent panels, reflective edges, focus highlights and a teal/lavender background. These use cached gradients rather than real-time background blur.
- A direct Home-button setup that prevents Google TV from appearing before GlitchOS on the tested firmware.
- Optional, reversible disabling of seven selected packages. Existing entertainment apps stay installed.
- An optional local repair of the matching TV's own AirPlay receiver. It uses the original hardware decoder and does not add an ad-supported mirroring service.

The launcher has no Internet permission, advertisements, account or feed service. It uses Android SDK UI classes without a third-party UI framework. No comparative performance or memory benchmark is claimed.

## Compatibility

The launcher APK targets Android TV and requires Android 8.0/API 26 or newer. The complete installer requires **Android TV API 29 or newer and active Android user 0**. Device-specific Home priorities, input selectors and receiver services vary, so the tested Android 14 result does not establish compatibility with every Android TV.

The AirPlay repair is narrower: the verified original receiver is **CHAirPlay 2.0.20.33**, version code **2000033**, package `com.homwee.mmp.screenshare`, on the firmware recorded in [TESTED-DEVICES.md](docs/TESTED-DEVICES.md). An app version alone is not enough to establish compatibility; the original binary must match the repair's expected fingerprints.

No CHiQ/Changhong receiver APK, native library or decompiled vendor source is distributed here. The repair is generated locally from the owner's matching TV. Only the GlitchOS launcher APK is supplied in [`releases/`](releases/).

## Install on Windows

You need PowerShell, [official Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools) (`adb.exe`), the TV's network address and authorized ADB debugging on the TV. Keep the repository's directory structure intact. Replace the example paths and `TV_IP` below with your own values.

```powershell
$adb = 'C:\Android\platform-tools\adb.exe'
$tv = 'TV_IP:5555'
& $adb connect $tv
```

Accept the TV's debugging prompt if this computer is not already authorized. First inspect the proposed changes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -WhatIf
```

`-WhatIf` reads the device and reports the plan without changing the TV or creating a backup. To install the supplied launcher and configure direct Home, run without `-WhatIf`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb
```

Optional switches:

| Option | Purpose |
| --- | --- |
| `-Cleanup` | Apply the seven-package allowlist below. Canary WebView is skipped if it is active or the active provider cannot be identified. |
| `-AirPlayApk 'C:\local\GlitchOS-AirPlay.apk'` | Install a compatible repaired receiver that you built locally. See [AirPlay build instructions](docs/AIRPLAY.md). |
| `-AirPlayName 'GlitchOS TV'` | Set a sharing name when configuring the supported AirPlay receiver. |
| `-LauncherApk 'C:\local\launcher.apk'` | Use a different launcher APK instead of the supplied release. |
| `-BackupDirectory 'C:\private\tv-backups'` | Choose a private backup destination; the default is the repository's `backups/` folder. |

For example, after building the matching repair locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -Cleanup -AirPlayApk 'C:\local\GlitchOS-AirPlay.apk' -AirPlayName 'GlitchOS TV'
```

`-Device` is required. `-AdbPath` can be omitted when `adb` is on `PATH`. Keep the saved state file and backup directory private; they record device-specific values and are not for publication.

After installing or naming a repaired receiver, open GlitchOS's AirPlay control and turn it off, then on, to activate the selected receiver and sharing name.

## Restore or report a device

Use the state file printed by the installer to restore the captured configuration:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -StateFile 'C:\private\tv-backups\YOUR_STATE_FILE.json'
```

Restore returns the captured settings and package states. A repaired receiver newly added by this installer is disabled on restore so GlitchOS can use the original receiver again; its APK and data remain installed. The launcher remains installed as an app, and previously installed APK versions are not rolled back. Restoring the original receiver can restore its original pairing problem.

For a report that omits device identifiers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-TVReport.ps1 -Device $tv -AdbPath $adb -OutputFile '.\tv-report.json'
```

Read [PRIVACY.md](docs/PRIVACY.md) before sharing reports or backup files. See [NOTICE.md](NOTICE.md) for attribution and distribution details; no broad license grant has been selected for this initial release.

## Home behavior and cleanup

The direct Home configuration disables these installed packages for the selected Android user:

| Package | Effect |
| --- | --- |
| `com.google.android.apps.tv.launcherx` | Disables Google TV Home and its profile chooser. |
| `com.google.android.tungsten.setupwraith` | Disables Google TV setup/recovery and related setup/account flows. |

Restore the saved Google configuration before changing Google TV profiles, using setup/account flows, or resetting the TV. These packages stay installed. Firmware updates may enable them again.

The optional cleanup consists of seven packages:

| Package | What is disabled |
| --- | --- |
| `com.homwee.store` | CHiQ retail/demo mode; this is not Google Play Store. |
| `com.google.android.feedback` | Google feedback reporting. |
| `com.google.android.webview.canary` | The inactive Canary WebView provider; retain the active stable provider. |
| `com.google.android.syncadapters.calendar` | Calendar account synchronization. |
| `com.homwee.mmp.fileexplorer` | CHiQ's USB/media file browser. |
| `com.homwee.mmp.imageplayer` | CHiQ's photo viewer. |
| `com.homwee.help` | CHiQ's help app. |

On the tested TV, Netflix, Prime Video, YouTube, YouTube Music, Spotify, Crunchyroll, RTL+, IPTV, Roblox, GeForce NOW and Google Play Games were retained. Play Store, TV Settings, the stable WebView provider and input services were also retained. Retaining an app does not mean every app or protected video was playback-tested.

Disabling a preinstalled package does **not** remove its APK from the system partition or reclaim that APK's storage. Restore uses the saved previous state rather than assuming every package was originally enabled.

## AirPlay repair

The failing receiver advertised inconsistent pairing capabilities: its discovery records differed from its connection response. The resulting invalid video data caused both hardware and software decoder failures. Correcting the advertised capability restored mirroring; changing the decoder was unnecessary.

The repair changes exactly one ASCII byte in each of three native libraries, making the advertised capability `0x5A7FFFF7,0x1E` consistent with the receiver's response. It preserves the original authentication implementation, key derivation, hardware decoder and video settings.

The locally built package is `com.glitchos.airplayrepair`. It installs beside the original system app because the vendor's signing key is unavailable. The original receiver remains intact. GlitchOS prefers the repaired service, stops the original service to avoid duplicate receivers, and controls startup. Production builds contain no diagnostic test activity or added header logger.

To connect, show the GlitchOS home screen, enable AirPlay in its navigation bar, then use the iPhone's Control Center → Screen Mirroring. Both devices must be on the same network. The launcher displays the receiver's configured sharing name. Opening the manufacturer's sharing screen can change its service state; use GlitchOS's AirPlay toggle if the receiver needs restarting.

Successful screen mirroring does not establish Apple certification, AirPlay 2, HomeKit or DRM-protected content compatibility. The project is not affiliated with Apple, Google, CHiQ or Changhong.

## Build and release files

The launcher source and Windows build instructions are in [`launcher/`](launcher/README.md). Building requires JDK 17, Android SDK Platform 35 and Build-Tools 35.0.0. A local build generates its own signing key in an ignored folder; no private signing key is included in this repository.

The supplied release is [`GlitchOS-TV-Edition-1.3.1.apk`](releases/GlitchOS-TV-Edition-1.3.1.apk), version code 9. Its SHA-256 is:

```text
8b9de671dc1648afa1c8d49b58f792574fd2ec23e39eb4afb488469e0e6c4ce1
```

[`releases/SHA256SUMS`](releases/SHA256SUMS) records the same checksum. See [CHANGELOG.md](CHANGELOG.md) for version history.

## Check the distribution

These checks use local files and a simulated ADB device. They do not contact or change a TV:

```powershell
.\tests\Test-Release.ps1
.\scripts\tests\Test-Installer.ps1
.\tests\Test-AirPlayPatch.ps1
```

The GitHub Actions workflow runs these checks on Windows. The firmware-derived receiver build is tested locally because its original APK is not distributed in this repository.
