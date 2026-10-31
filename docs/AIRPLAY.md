# Optional AirPlay repair for a supported CHiQ TV

## Quick summary

**You do not need this repair to install or use the GlitchOS launcher.** For the normal installation, use [Getting started](GETTING-STARTED.md).

This extra guide fixes one tested CHiQ receiver that connected to a phone and then failed or disconnected. You will copy the original receiver from your own TV, build a repaired copy on Windows, and install that copy alongside GlitchOS. The repository does not include a downloadable CHiQ receiver APK.

## Do I need this?

- If AirPlay already works, skip this guide.
- If your TV has the built-in CHiQ receiver and mirroring fails after connecting, this repair may apply. The builder checks the exact original APK before making changes.
- If the TV has no matching receiver, this guide does not add universal AirPlay support. A model name, Android version or similar symptom alone is not enough.

The tested original is **CHAirPlay 2.0.20.33** on a CHiQ Google TV running **Android 14**. The owner confirmed picture, sound, rotation and operation after a reboot. Other receiver builds are rejected by checksum, even if they display the same app version. Keep that check enabled.

## 1. Connect the TV and open the project folder

First follow [Getting started](GETTING-STARTED.md) to extract the project, download ADB, enable the debugging option your TV provides and authorize your computer. Its connection instructions distinguish wireless pairing from network debugging; do not assume that every TV uses port `5555`.

Open PowerShell in the extracted project folder, the one containing `scripts`, `releases` and `README.md`. Windows PowerShell 5.1 and PowerShell 7 are supported. In the same window, set these values to your actual paths and the authorized device address/serial shown by `adb devices`:

```powershell
$repo = 'C:\GlitchOS\GlitchOS-TV-installer'
Set-Location -LiteralPath $repo
$adb = 'C:\GlitchOS\platform-tools\adb.exe'
$tv = Read-Host 'Enter your authorized TV address:port or device serial'
& $adb devices
```

Continue when your selected TV is listed with status `device`. For `unauthorized`, `offline` or a missing TV, return to the [connection checks](GETTING-STARTED.md#check-the-connection).

## 2. Download the build tools and set their paths

The builder needs these additional tools on your **computer**, not on the TV. It does not download them automatically.

| Tool | What to get | Path used by the script |
| --- | --- | --- |
| Java 17 JDK | For example, [Eclipse Temurin JDK 17 for Windows](https://adoptium.net/temurin/releases/?version=17&os=windows&arch=x64&package=jdk). Choose the JDK package so it includes `keytool.exe`. | The full path to `bin\java.exe`. |
| Apktool | Download `apktool_3.0.3.jar` from the [official 3.0.3 release](https://github.com/iBotPeaches/Apktool/releases/tag/v3.0.3). | The full path to that JAR file. |
| Android SDK Build Tools | Install **35.0.0**, the tested version, through Android Studio's SDK Manager or the [official SDK package tools](https://developer.android.com/tools/sdkmanager). See [Build Tools documentation](https://developer.android.com/tools/releases/build-tools). | The version folder containing `aapt2.exe`, `zipalign.exe` and `lib\apksigner.jar`. |

Adjust these example paths to where you installed or extracted the tools. The Java installation folder may include a longer version number.

```powershell
$java = 'C:\Tools\jdk-17\bin\java.exe'
$apktool = 'C:\Tools\apktool_3.0.3.jar'
$buildTools = 'C:\Android\Sdk\build-tools\35.0.0'
$keytool = Join-Path (Split-Path $java -Parent) 'keytool.exe'
& $java -version
```

The last command should report Java 17. The builder verifies Apktool's checksum and the original TV APK automatically; the exact accepted hashes are listed [below](#checksums-build-records-and-automation).

## 3. Create and keep your signing key

Android requires an APK to be signed. Your **keystore** is a local file holding the signing key for your repaired receiver. Create it once, then keep the file, its password and the alias `airplay-repair` for later updates.

If you already created and used a key for this receiver, reuse it and skip key generation. A differently signed APK cannot update the installed repair in place.

```powershell
New-Item -ItemType Directory -Force .\local | Out-Null
& $keytool -genkeypair `
  -keystore .\local\airplay-repair.p12 -storetype PKCS12 `
  -alias airplay-repair -keyalg RSA -keysize 3072 -validity 3650 `
  -dname 'CN=Local GlitchOS AirPlay'
```

Enter and confirm a password when prompted. Password characters may not appear as you type. Keep a private backup of `local\airplay-repair.p12` and the password; do not put the password in a command or upload the key to GitHub. The build will ask for the password again when signing.

## 4. Build the repaired receiver

Run this from the same PowerShell window and project folder. It copies the installed original receiver from your selected TV, checks it, and builds the repair locally:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-AirPlayRepair.ps1 `
  -Device $tv -AdbPath $adb `
  -JavaPath $java `
  -ApktoolJar $apktool `
  -BuildToolsPath $buildTools `
  -KeyStore .\local\airplay-repair.p12 `
  -KeyAlias airplay-repair
```

`-ExecutionPolicy Bypass` applies to this PowerShell process; it avoids changing your computer's permanent execution-policy setting. The builder only reads the TV: it does not install apps, start or stop the receiver, or change TV settings. `-DeviceSerial` is also accepted as an alias for `-Device`.

If you already have the original APK in `local\CHAirPlay.apk`, use this command **instead**:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build-AirPlayRepair.ps1 `
  -OriginalApk .\local\CHAirPlay.apk `
  -JavaPath $java `
  -ApktoolJar $apktool `
  -BuildToolsPath $buildTools `
  -KeyStore .\local\airplay-repair.p12 `
  -KeyAlias airplay-repair
```

Allow the build to finish and enter your keystore password when prompted. Success ends with **`Built and verified:`** followed by the full path to `GlitchOS-AirPlay.apk`. Copy that path for the next step. The APK has not been installed yet.

If the script says **Unsupported original APK SHA256**, stop this repair path. Your receiver binary does not match the tested build. Do not remove the checksum check or change byte offsets to force it through.

## 5. Preview, then install with GlitchOS

Paste the full APK path printed by the builder, without adding surrounding quote characters:

```powershell
$airPlayApk = Read-Host 'Paste the full GlitchOS-AirPlay.apk path printed by the build'

# Preview only: inspect the planned changes.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 `
  -Device $tv -AdbPath $adb -AirPlayApk $airPlayApk -WhatIf

# Apply the same setup.
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 `
  -Device $tv -AdbPath $adb -AirPlayApk $airPlayApk
```

This is the normal GlitchOS installer with the AirPlay option: it also installs the launcher, makes it Home and disables the selected Google TV Home/setup packages. Read [the changes and restore guide](CHANGES-AND-RESTORE.md) before applying it. Keep the full path printed after **`Restore backup:`**; each installer run creates a new configuration backup.

To also change the sharing name on the supported CHiQ firmware, add **`-AirPlayName 'GlitchOS TV'` to both the preview and apply commands**. This naming option uses the firmware's sharing-name setting; it is not a universal TV rename feature. Omitting it retains the current name.

## 6. Activate and check mirroring

Open the **AirPlay** menu in GlitchOS and toggle AirPlay **off, then on** to activate the repaired receiver and any new name. Keep GlitchOS visible while connecting from your phone's **Screen Mirroring** menu. Check that the picture stays connected, sound plays and rotation works.

The original system receiver stays installed. If you need to undo configuration changes, follow [Changes and restore](CHANGES-AND-RESTORE.md#restore-your-previous-configuration) with your saved backup. Restore is a configuration rollback, not a backup of previous APK versions or app data; the guide explains how the optional repair is handled.

## Technical details

This repository contains the patch and build recipe, not the OEM APK, decompiled source or native libraries. The build reads your original APK, creates a separate package named `com.glitchos.airplayrepair`, and signs it with your own local key. It makes the built-in receiver advertise a pairing mode its code already supports.

### Checksums, build records and automation

The required Apktool 3.0.3 JAR SHA256 is:

```text
dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423
```

The supported original `CHAirPlay.apk` SHA256 is:

```text
6eae95d1f517b6f9f1beb903cd9d896b3106d58cdf077757cae6d8901a1077ec
```

For a connected TV, the builder reads `pm path com.homwee.mmp.screenshare` and pulls the single APK it reports. For automation, optional `-StorePasswordEnvironmentVariable NAME` and `-KeyPasswordEnvironmentVariable NAME` pass **environment variable names** to apksigner. Set the secrets securely in the calling environment. Without these options, apksigner prompts in the console. The script never records passwords in build audits.

Each build creates a new directory under `artifacts/airplay-repair/`, or your `-OutputDirectory`. The final `GlitchOS-AirPlay.apk` is aligned, signed and verified. `patch-audit.json` and `build-audit.json` record checksums and changed files. Intermediate OEM-derived files remain local in that directory; do not publish it. The repository ignores `artifacts/`, `local/`, tools and keys.

The six patched file hashes are fixed. Final APK hashes can differ with signing keys and build metadata. The local repair retains the OEM version name **2.0.20.33** and version code **2000033** to identify its upstream base. It is a GlitchOS repair of that build, not an OEM update.

### Exact changes

The helper checks the original APK and all six input files before writing anything. Each output file must match the SHA256 of the production version that worked on the tested TV.

| File | Change |
| --- | --- |
| `AndroidManifest.xml` | Clone package and label `GlitchOS AirPlay`; optional TV/touchscreen features; disable the clone's boot receiver. No launcher or diagnostic activity. |
| Two existing self-package strings | Point BuildConfig and the service's self-package check at the clone. JNI and component class names remain unchanged. |
| `libapscore.so` | ASCII `2` → `A` at file offset `0x1e397b`. |
| `libjdns_sd.so` | ASCII `2` → `A` at file offset `0xd546`. |
| `libjdns_sd_embedded.so` | ASCII `2` → `A` at file offset `0x6070f`. |

Each native byte changes the capability string from `0x527FFFF7` to `0x5A7FFFF7`, enabling bit 27 (`SupportsLegacyPairing`). All three advertisers must agree. The receiver's existing RTSP `/info` response already reported the corresponding capability, `0x1e5a7ffff7`.

The decoder, resolution, frame rate, JNI classes, cryptographic routines and permissions are unchanged. The build verifies the three patched library hashes, the other five unchanged libraries, exactly two DEX files, no diagnostic classes, the compiled package/label and the disabled boot receiver. It then verifies alignment and the APK signature.

GlitchOS starts and binds the selected receiver service, including Android 14's visible-client activity-start allowance. The receiver clone has no independent boot startup. The original OEM package remains installed for rollback, and its receiver service is stopped to avoid duplicate advertisements. The clone's original vendor application still expects its service to be started promptly after process creation.

### Why this fixed the failure

The phone connected, but native packet diagnostics showed invalid-stream markers before decoding. Both hardware and software decoders failed on the malformed input. The receiver advertised legacy pairing as unavailable while its handshake code expected the related key setup. Enabling the matching advertised capability restored valid packets and sustained mirroring on the tested phone.

UxPlay's maintainers documented the same capability/key-setup mismatch in [issue 176](https://github.com/FDH2/UxPlay/issues/176). Their [May 2023 correction](https://github.com/FDH2/UxPlay/commit/d38f8690c2645959c413823acdd2c4f98f545914) adjusted key handling when legacy pairing is not requested. This local recipe instead enables the pairing path already implemented by this specific receiver. It does not bypass authentication or modify session keys.

### Tests and limits

Run the synthetic patch tests without an APK or Android tools:

```powershell
.\tests\Test-AirPlayPatch.ps1
```

They cover missing/duplicate anchors, checksum and offset rejection, exactly one changed byte per native patch, preservation of input buffers, the intended manifest scope and rejection of unsupported originals. A complete build additionally validates the exact OEM-derived output hashes and signed APK. The repository intentionally has no OEM fixtures.

This is not a general AirPlay decoder patch or support claim for other TVs, firmware or phones. The known-good behavior belongs to the tested receiver build and setup. For another original checksum, the script stops before patching; do not remove that check or guess replacement offsets.
