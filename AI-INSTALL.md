# Give this file to your coding AI

This is a handoff guide for installing **GlitchOS TV Edition** from a Windows PC. Download this file and attach it to a coding AI that can use a local terminal on that PC. The PC must be able to reach your TV through Android Debug Bridge (ADB).

Copy this message with the file:

> Read AI-INSTALL.md and help me install GlitchOS TV on my TV. Inspect the current setup first, keep my entertainment apps, and use the project's installer and restore scripts. Ask for missing information and optional choices together. Save the original configuration locally, explain the concrete changes, then carry out the work I authorize without repeatedly asking for the same permission. Ask me to handle the TV's debugging prompt and any phone playback checks. Report what you actually verified and give me the restore command.

If your AI only provides chat, it can explain the steps or help you run the commands yourself. It cannot connect to your TV without terminal access on a computer that has ADB and an authorized connection. Do not describe suggested commands as completed work.

## Project and verified baseline

- Canonical repository: [emiliaplays/GlitchOS-TV-installer](https://github.com/emiliaplays/GlitchOS-TV-installer).
- Current guide: [AI-INSTALL.md on main](https://github.com/emiliaplays/GlitchOS-TV-installer/blob/main/AI-INSTALL.md).
- Download the [current main branch ZIP](https://github.com/emiliaplays/GlitchOS-TV-installer/archive/refs/heads/main.zip), then extract the complete folder. The v1.1.0 release ZIP also includes this guide and the Now Playing documentation.
- Installer release baseline: **1.1.0**. Supplied launcher: **1.4.0**, version code **10**, package `com.glitchos.tv`.
- Supplied APK: `releases/GlitchOS-TV-Edition-1.4.0.apk`.
- Launcher SHA-256: `0f21602dc6b2abcde436253f89a0a01d22933ad27f0d5472eb880f89ad5a3ff8`.

GlitchOS is a launcher and configuration tools, not a replacement operating system. The complete installer requires **Android TV API 29 or newer, with user 0 active**. The standalone APK's minimum API 26 does not lower the installer's requirements. This does not install on Samsung Tizen, LG webOS or Roku.

The working reference setup was a CHiQ TV with firmware model **AI PONT, Android 14**; its retail model was tentatively identified as L40G7B. Read the physical label if the retail model matters. Other models are not proven compatible merely because they run Android. The public scripts have mock-device tests and a read-only TV dry run; the full public installer has not yet been run end-to-end on a TV. The reference TV was configured and playback-tested before these scripts were packaged.

## Instructions for the AI: inspect before changing anything

Read `README.md`, `docs/TESTED-DEVICES.md`, and the scripts in the downloaded project. For AirPlay, also read `docs/AIRPLAY.md`. Use the checked project scripts; do not replace them with a generic debloat list or improvised package removal commands.

1. Establish the user's TV brand/model, Android version, PC operating system and selected ADB device. Use connected-device facts where available; ask only for missing information. Do not choose an arbitrary device when several are connected.
2. Determine whether GlitchOS or the repaired AirPlay receiver is already installed, which app is Home, which packages are disabled, and whether earlier restore backups and signing keys exist. Inspect first; do not reinstall a working setup just because this guide was supplied. Keep the earliest baseline backup and label any later snapshot as a snapshot of the current configuration. Never overwrite an original backup or invent original enabled states.
3. Collect optional choices that the user has not already specified: seven-package cleanup, compatible AirPlay repair, and sharing-name changes. If no optional features are wanted, install only the launcher/direct Home configuration. Keep every entertainment app unless the user separately requests otherwise.
4. Explain the planned changes using the actual TV: launcher install/update/retention, exact packages to disable, accessibility entries affected, optional receiver/name changes, and private backup destination. Reuse authorization already given in the conversation. Once the concrete work is authorized, proceed; do not add another confirmation loop. A new destructive action outside that scope requires a separate decision.

Before the plan is agreed, use only local file checks and read-only TV inspection. Do not disable packages, change Home, enable services, change DNS, or alter decoder settings during discovery.

## Obtain the project and connect ADB

Use the current main ZIP above, or clone into a new folder:

```powershell
git clone https://github.com/emiliaplays/GlitchOS-TV-installer.git
Set-Location -LiteralPath '.\GlitchOS-TV-installer'
```

If an existing checkout has local changes, preserve them; use a separate folder instead of overwriting it. Keep the repository's directory structure intact. Download ADB only from [official Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools). Replace all placeholder paths and addresses below with this user's values:

```powershell
$adb = 'C:\PATH\TO\platform-tools\adb.exe'
$tv = 'TV_IP:ADB_PORT'
$backupDirectory = 'C:\PRIVATE\TV-BACKUPS'
& $adb connect $tv
& $adb devices -l
& $adb -s $tv get-state
```

The user may need to enable Developer options/debugging on the TV and physically accept its authorization prompt. Guide them using their TV's menu labels. Do not claim that approval happened until ADB reports `device`. If the TV uses wireless-debugging pairing, use its displayed pairing address/port and interactive `adb pair` first; its connection port can differ. Do not guess the port or ask the user to publish pairing codes. A USB ADB serial can also be supplied as `-Device`.

Read the device without changing it:

```powershell
& $adb -s $tv shell getprop ro.product.manufacturer
& $adb -s $tv shell getprop ro.product.model
& $adb -s $tv shell getprop ro.build.version.release
& $adb -s $tv shell getprop ro.build.version.sdk
& $adb -s $tv shell am get-current-user
& $adb -s $tv shell pm list features
& $adb -s $tv shell cmd role get-role-holders --user 0 android.app.role.HOME
& $adb -s $tv shell pm list packages --user 0
& $adb -s $tv shell pm list packages -d --user 0
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-TVReport.ps1 -Device $tv -AdbPath $adb -OutputFile '.\tv-report.json'
```

Verify the downloaded launcher locally, in a normal PowerShell session:

```powershell
$expected = '0f21602dc6b2abcde436253f89a0a01d22933ad27f0d5472eb880f89ad5a3ff8'
$actual = (Get-FileHash -LiteralPath '.\releases\GlitchOS-TV-Edition-1.4.0.apk' -Algorithm SHA256).Hash
if ($actual.ToLowerInvariant() -ne $expected) { throw 'Launcher checksum mismatch; stop before installing.' }
```

Compare with `releases/SHA256SUMS`. If a future project version differs from this guide, identify and verify that version's published files before proceeding; do not silently accept a different hash. Do not uninstall an existing app or clear its data merely to work around a signing-certificate mismatch. Updating an existing locally built app requires its original signing key.

## Understand the options

The **default install** installs the launcher and configures direct Home. After verifying the launcher installs, receives the Home role and opens explicitly, it disables these packages when present:

| Package | Consequence |
| --- | --- |
| `com.google.android.apps.tv.launcherx` | Google TV Home and its profile chooser are disabled. |
| `com.google.android.tungsten.setupwraith` | Google TV setup/recovery and related setup/account flows are disabled. |

Restore the saved Google configuration before using those profile/setup flows or resetting the TV. The installer removes only enabled GlitchOS/Projectivy Home-redirect accessibility entries; it preserves unrelated services such as Button Mapper. It does not enable a new accessibility service. Some firmware forces Google's Home priority until its package is disabled; the installer verifies direct Home afterward and attempts rollback if that fails.

**Optional `-Cleanup`** disables only the following installed packages. It skips Canary if Canary is the active WebView provider or the active provider cannot be verified.

| Package | Function that will be disabled |
| --- | --- |
| `com.homwee.store` | CHiQ retail/demo mode, not Google Play Store. |
| `com.google.android.feedback` | Google feedback reporting. |
| `com.google.android.webview.canary` | Inactive Canary WebView. |
| `com.google.android.syncadapters.calendar` | Calendar account synchronization. |
| `com.homwee.mmp.fileexplorer` | CHiQ USB/media file browser. |
| `com.homwee.mmp.imageplayer` | CHiQ photo viewer. |
| `com.homwee.help` | CHiQ help app. |

These are choices with functional tradeoffs, not a universal list of useless apps. Keep streaming/music/gaming apps, Play Store, TV Settings, the active WebView provider and input services. Disabling system packages does not remove their APKs or reclaim their APK storage.

## Optional AirPlay: require the exact original receiver

This is a repair for **CHAirPlay 2.0.20.33**, version code **2000033**, package `com.homwee.mmp.screenshare`. The original APK must have SHA-256:

```text
6eae95d1f517b6f9f1beb903cd9d896b3106d58cdf077757cae6d8901a1077ec
```

A matching app version or TV brand alone is insufficient. Use `scripts/Build-AirPlayRepair.ps1`, which checks the original and exact patch fingerprints. If they do not match, stop the AirPlay branch and report it as unsupported; the launcher installation can still proceed within the user's chosen scope. Never remove checksum checks or guess patch offsets.

The receiver APK is **not included in the public download**. Build from the owner's TV using the complete recipe in `docs/AIRPLAY.md`. The validated toolchain uses Java 17, Android Build-Tools 35.0.0, the official Apktool 3.0.3 JAR, and a local signing key. The required Apktool SHA-256 is `dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423`.

Create a key only if the user does not already have the key required to update their receiver. Let keytool/apksigner prompt securely; do not put passwords in chat, command arguments, public logs or Git. Example, after replacing tool paths:

```powershell
New-Item -ItemType Directory -Force .\local | Out-Null
& 'C:\PATH\TO\jdk-17\bin\keytool.exe' -genkeypair -keystore .\local\airplay-repair.p12 -storetype PKCS12 -alias airplay-repair -keyalg RSA -keysize 3072 -validity 3650 -dname 'CN=Local GlitchOS AirPlay'

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-AirPlayRepair.ps1 -Device $tv -AdbPath $adb -JavaPath 'C:\PATH\TO\jdk-17\bin\java.exe' -ApktoolJar 'C:\PATH\TO\apktool_3.0.3.jar' -BuildToolsPath 'C:\PATH\TO\Android\Sdk\build-tools\35.0.0' -KeyStore '.\local\airplay-repair.p12' -KeyAlias 'airplay-repair'
```

The build reads the original APK from the selected TV and produces an aligned, signed APK and audits locally. It does not install or disable anything. Use the exact output APK path it prints with `-AirPlayApk`. Final APK hashes vary with local signing; the builder verifies the fixed patched file hashes and APK structure.

Keep the original receiver intact. The clone is `com.glitchos.airplayrepair`, installed beside it. The repair corrects three advertised capability bytes; it does not bypass authentication or alter cryptographic routines, session keys, decoders or video dimensions. Do not add experimental decoder overrides, DNS filters or another mirroring app as part of this installation. Keep OEM APKs/libraries, extracted sources, generated receiver APKs, signing keys and build artifacts local; do not redistribute them through the public repository.

## Preview and apply the chosen installation

Run from the repository root. Choose the exact options first, and use the same options for preview and installation. The following commands show the default launcher/direct Home plan:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -BackupDirectory $backupDirectory -WhatIf

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -BackupDirectory $backupDirectory
```

`-WhatIf` reads the TV but makes no TV changes and creates no backup. Before the actual run, present its concrete plan and resolve any unanswered choices. Do not request another approval if the user already authorized that plan.

Only when selected, append these options to **both** commands above:

- `-Cleanup` for the seven-package cleanup.
- `-AirPlayApk 'C:\PATH\TO\LOCAL\GlitchOS-AirPlay.apk'` for the compatible locally built repair.
- `-AirPlayName 'GlitchOS TV'` to change the supported receiver's saved sharing name. Omit it to preserve the current name.

Run one actual installation with the chosen options, not separate default and full installations. Record the exact timestamped state file printed as `Restore backup:`. The installer captures device identity, original Home/accessibility/package states and the previous sharing name before changing the TV. Protect this file and preserve older baseline backups. It attempts to restore configuration on failure; inspect the result instead of assuming rollback succeeded.

After an AirPlay install/name change, use GlitchOS's AirPlay menu to turn it off and on. The name setting applies to the firmware's receiver naming. Connect the phone while GlitchOS is visible; the activity-launch allowance is scoped to the visible launcher.

## Verify, then report honestly

Check the actual Home resolver and installed/disabled package lists against the initial inspection:

```powershell
& $adb -s $tv shell cmd package resolve-activity --brief --user 0 -a android.intent.action.MAIN -c android.intent.category.HOME
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-TVReport.ps1 -Device $tv -AdbPath $adb -OutputFile '.\tv-report-after.json'
```

Home should resolve to `com.glitchos.tv/.MainActivity` or its fully qualified equivalent. Check that apps the user wanted to keep remain installed and enabled. Ask the user to press Home on the remote, confirm the screen, and try their important apps, inputs and settings. Do not report every app as playback-tested simply because it is installed.

For AirPlay, ask the user to put the iPhone/iPad on the same local network, open Control Center → Screen Mirroring and select the configured TV name. They must confirm picture, sound, rotation and whether the connection stays active. Network discovery or a running service alone does not prove playback. Test reboot persistence only when the user has authorized a reboot; then recheck Home and the selected receiver.

Finish with the installed versions, verified Home behavior, exact newly changed package states, AirPlay outcome or pending user check, backup path, and restore command. Distinguish previously disabled apps from new cleanup. Do not invent successful phone tests, universal TV compatibility, performance gains, reclaimed storage, TV-wide privacy/ad blocking, Apple certification, AirPlay 2, HomeKit or protected-content compatibility.

## Restore

Use a state file from this TV and the point in time the user intends to restore. For the original pre-GlitchOS setup, retain and select the original baseline, not a later reinstall snapshot. Device identity is checked even if the network address has changed.

If several runs made changes, undo them in reverse chronological order before restoring the original baseline. A baseline from before the first run cannot undo additions made by a later run that it did not record. For example, restore a later AirPlay run using its own backup, then restore the earlier launcher run.

```powershell
$stateFile = 'C:\PRIVATE\TV-BACKUPS\THE_SAVED_STATE_FILE.json'
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -StateFile $stateFile -WhatIf
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -StateFile $stateFile
```

Restore returns captured Home, selected package states, changed accessibility settings and the prior sharing name. It restores preexisting launcher/repair enabled states. A newly added repaired receiver is stopped and disabled, retaining its APK/data so the original receiver can be selected again. The launcher remains installed as an app unless it was previously installed in a disabled state, which is restored. App versions and app data are not rolled back. Restoring the original receiver can bring back its original pairing problem.

If ADB disconnects or automatic restore is incomplete, retain the backup, reconnect to the same TV, and use the restore script. Do not factory-reset, remove unrelated packages or guess prior states to conceal a failed installation. Keep device backups and signing keys private; review `docs/PRIVACY.md` before sharing any diagnostic report.


## Now Playing and existing installations

See [Now Playing setup and updating](docs/NOW-PLAYING.md). For an existing working installation, update the signed launcher APK with `adb install -r` instead of rerunning cleanup/Home configuration. Media access is optional: explain Android notification-listener access, honor existing authorization, and use the documented component-specific grant only when wanted. Keep a record of whether it was already enabled. Installer backups/restore do not capture this separate grant; revoke it separately only if this setup added it. Do not promise controls for apps without an active media session or for native AirPlay mirroring.
