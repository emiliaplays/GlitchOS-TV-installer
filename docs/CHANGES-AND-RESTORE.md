# What changes, and how to undo it

GlitchOS installs an Android launcher and changes selected settings. It does not replace the TV's operating system, root the device or perform a factory reset.

Every applied installation saves a private JSON state file before changing the TV. The installer prints its full path after **`Restore backup:`**. A `-WhatIf` preview does not create that file or change the TV.

## Default installation: launcher and Home

The default command installs `com.glitchos.tv`, makes it the Home app for Android user 0, and disables these packages when they are present:

| Package | What it does | Effect of disabling it |
| --- | --- | --- |
| `com.google.android.apps.tv.launcherx` | Google TV Home and its profile chooser. | Home can open GlitchOS directly on the tested firmware without Google TV appearing first. The Google TV profile chooser is unavailable. |
| `com.google.android.tungsten.setupwraith` | Google TV setup/recovery and related account/setup flows. | Those Google TV setup features are unavailable until restored. |

Both packages stay installed, and their previous enabled states are saved. Disabling them does not delete Google accounts. Restore the saved configuration before changing Google TV profiles, using its setup/account flows or resetting the TV.

The installer also removes only known GlitchOS and Projectivy Home-redirect accessibility entries, if present, because direct Home no longer needs them. Other accessibility services are retained. Their previous settings are saved for restoration.

It verifies that GlitchOS launches before disabling the Home packages, then verifies that Android resolves Home to GlitchOS. If installation fails, it attempts to restore the captured configuration.

## Optional cleanup

Adding `-Cleanup` enables this fixed seven-package list. The installer does not search for additional apps to disable.

| Package | App or feature | Effect |
| --- | --- | --- |
| `com.homwee.store` | CHiQ retail/demo mode. | Stops that demo app. Despite its name, this is not Google Play Store. |
| `com.google.android.feedback` | Google Feedback. | Disables that feedback-reporting app. |
| `com.google.android.webview.canary` | Canary WebView provider. | Disables the inactive Canary provider. It is skipped if active, or if the active provider cannot be identified. |
| `com.google.android.syncadapters.calendar` | Calendar synchronization. | Stops that calendar account-sync adapter. |
| `com.homwee.mmp.fileexplorer` | CHiQ USB/media file browser. | Removes that browser from use; restore it if you need its USB-browsing interface. |
| `com.homwee.mmp.imageplayer` | CHiQ photo viewer. | Disables that viewer. |
| `com.homwee.help` | CHiQ Help. | Disables the manufacturer's help app. |

Missing packages are skipped. Packages already disabled are not newly enabled by cleanup. The saved state records the actual previous state, so restoration does not simply turn every app on.

On the tested TV, Netflix, Prime Video, YouTube, YouTube Music, Spotify, Crunchyroll, RTL+, IPTV, Roblox, GeForce NOW and Google Play Games were retained. Play Store, TV Settings, the active stable WebView provider and input services were retained too. This is not a playback test of every entertainment app.

**Disabling a system app does not remove its APK or reclaim the storage occupied by that APK.** This cleanup does not delete app data.

## Optional AirPlay changes

`-AirPlayApk` installs a locally built, compatible repair as `com.glitchos.airplayrepair`. The original `com.homwee.mmp.screenshare` system app is not overwritten or uninstalled. The repair is specific to matching CHiQ receiver binaries; see [AIRPLAY.md](AIRPLAY.md).

GlitchOS prefers the repaired receiver when it is enabled and stops the original service to avoid duplicate receivers. `-AirPlayName` changes the firmware's sharing-name setting and saves its old value. After installation or renaming, toggle AirPlay off and on in GlitchOS to activate the selection and name.

The final repair contains no added diagnostic test screen or header logger. It does not leave an ad blocker, DNS change or global software-decoder override on the TV.

## What the backup contains

The state file records the device identity, previous Home role, relevant package enabled states, relevant accessibility settings, previous AirPlay name and the changes attempted by that installation. It belongs to that TV; restore checks its identity before applying it.

The default location is the project's `backups` folder. You can choose another location with `-BackupDirectory` on the installation command. Keep the file private and keep an extra copy somewhere safe. Do not publish it or edit its contents to make it apply to another TV. See [PRIVACY.md](PRIVACY.md).

If you run the installer again, the new backup captures the configuration at the start of that later run. To undo your first setup, retain the backup from that first run rather than assuming the newest file represents the original TV configuration.

To undo several installation runs, restore them in reverse order: the newest run first, then the earlier runs you want to undo. For example, undo a later AirPlay installation with its own backup before restoring the original launcher installation. An early backup cannot undo additions made by a later run that it never recorded.

Restore writes the saved values of those tracked settings. If you change the same Home, accessibility or sharing-name settings later, restoring an older backup can replace those later changes.

## Restore your previous configuration

Reconnect ADB first. If you closed PowerShell, reopen it and set the same paths used in the [installation guide](GETTING-STARTED.md):

```powershell
$repo = 'C:\GlitchOS\GlitchOS-TV-installer'
$adb = 'C:\GlitchOS\platform-tools\adb.exe'
Set-Location -LiteralPath $repo
$tv = Read-Host 'Enter this TV connection address (IP:port), or its USB serial'
```

For a network connection, reconnect using its current connection address:

```powershell
& $adb connect $tv
& $adb devices
```

For an already connected USB device, skip `connect` and check `devices`. Wireless pairing may need repeating if its authorization was removed. Continue when the TV is listed as `device`.

Paste the exact state-file path printed during the installation you want to undo. Enter the path without adding quotation marks at the prompt:

```powershell
$stateFile = Read-Host 'Paste the full Restore backup JSON path saved during installation'
```

Preview the restore:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -StateFile $stateFile -WhatIf
```

Apply it:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -StateFile $stateFile
```

For PowerShell 7, you can replace `powershell.exe` with `pwsh`. If restore rejects the backup as belonging to another TV, use the correct backup; do not bypass the identity check.

## What restore does and does not do

| Restore does | Restore does not |
| --- | --- |
| Return changed package enabled states to their saved values. | Downgrade apps to previous APK versions. |
| Restore the saved Home role and affected accessibility settings. | Uninstall the GlitchOS launcher; it remains available as an app. |
| Restore the previous sharing name when the installer changed it. | Restore older app data, favorites, accounts or files from a full-device backup. |
| Disable a repaired receiver newly added by that installation, so GlitchOS can fall back to the original receiver. Its APK/data remain installed. | Replace the TV firmware, factory-reset it or remove system APKs. |
| Restore the saved enabled state of a previously installed launcher or repaired receiver when the installer changed it. | Roll back TV changes outside the captured configuration. |

Returning to the original AirPlay receiver may also return its original pairing problem. Restore is an undo path, not another repair for that receiver.

If ADB disconnects during installation, automatic restoration may be incomplete. Reconnect to the same TV and run restore with its saved state file. Keep the backup even after a successful restore in case you need to inspect what was changed.


## Now Playing and existing installations

See [Now Playing setup and updating](NOW-PLAYING.md). For an existing working installation, update the signed launcher APK with `adb install -r` instead of rerunning cleanup/Home configuration. Media access is optional: explain Android notification-listener access, honor existing authorization, and use the documented component-specific grant only when wanted. Keep a record of whether it was already enabled. Installer backups/restore do not capture this separate grant; revoke it separately only if this setup added it. Do not promise controls for apps without an active media session or for native AirPlay mirroring.
