# Build the optional AirPlay repair locally

The repair makes the built-in receiver advertise a pairing mode its code already supports. It was tested on a CHiQ Google TV running Android 14 with CHAirPlay **2.0.20.33**. The owner confirmed picture, sound, rotation and operation after a reboot. Other receiver builds are rejected by checksum; matching an app's version number alone is insufficient.

This repository contains the patch and build recipe, not the OEM APK, decompiled source or native libraries. The build reads your original APK, creates a separate package named `com.glitchos.airplayrepair`, and signs that package with your own local key. It does not install apps or change TV settings.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7.
- A local Java 17 installation; pass its `java.exe` path.
- [Official Apktool 3.0.3](https://github.com/iBotPeaches/Apktool/releases/tag/v3.0.3), saved locally as `apktool_3.0.3.jar`.
- Local [Android SDK Build Tools](https://developer.android.com/tools/releases/build-tools), containing `aapt2.exe`, `zipalign.exe` and `lib/apksigner.jar`. Version 35.0.0 was used for validation.
- Your own signing keystore and alias. Keep that key for future updates to your locally built receiver.
- Either the original APK copied from your TV or local ADB and an explicitly selected, already authorized TV connection.

The builder does not download these tools. It requires the Apktool JAR SHA256:

```text
dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423
```

The supported original `CHAirPlay.apk` SHA256 is:

```text
6eae95d1f517b6f9f1beb903cd9d896b3106d58cdf077757cae6d8901a1077ec
```

## Create your signing key

Use your Java installation's `keytool.exe`. This example prompts for the password; no password belongs in a command history or the repository.

```powershell
New-Item -ItemType Directory -Force .\local | Out-Null
& 'C:\Tools\jdk-17\bin\keytool.exe' -genkeypair `
  -keystore .\local\airplay-repair.p12 -storetype PKCS12 `
  -alias airplay-repair -keyalg RSA -keysize 3072 -validity 3650 `
  -dname 'CN=Local GlitchOS AirPlay'
```

If a receiver clone is already installed, an update must use the same signing key. A differently signed APK cannot update it in place.

## Build from your original APK

Run this from the repository root, adjusting tool paths:

```powershell
.\scripts\Build-AirPlayRepair.ps1 `
  -OriginalApk .\local\CHAirPlay.apk `
  -JavaPath 'C:\Tools\jdk-17\bin\java.exe' `
  -ApktoolJar 'C:\Tools\apktool_3.0.3.jar' `
  -BuildToolsPath 'C:\Android\Sdk\build-tools\35.0.0' `
  -KeyStore .\local\airplay-repair.p12 `
  -KeyAlias airplay-repair
```

Alternatively, replace `-OriginalApk` with these parameters to copy the installed original receiver using read-only ADB commands:

```powershell
  -Device '192.168.1.50:5555' -AdbPath 'C:\Tools\platform-tools\adb.exe'
```

Use your TV's address. `-DeviceSerial` is an alias for `-Device`. The builder reads `pm path com.homwee.mmp.screenshare` and pulls the single APK it reports; it never starts, stops or disables a TV app.

For automation, optional `-StorePasswordEnvironmentVariable NAME` and `-KeyPasswordEnvironmentVariable NAME` pass **environment variable names** to apksigner. Set the secrets securely in the calling environment. Without these options, apksigner prompts in the console. The script never records passwords in build audits.

Each build creates a new directory under `artifacts/airplay-repair/`, or your `-OutputDirectory`. The final `GlitchOS-AirPlay.apk` is aligned, signed and verified. `patch-audit.json` and `build-audit.json` record checksums and changed files. Intermediate OEM-derived files remain local in that directory; do not publish it. The repository ignores `artifacts/`, `local/`, tools and keys.

The six patched file hashes are fixed. Final APK hashes can differ with signing keys and build metadata.

Use the resulting APK with the installer's `-AirPlayApk` option; see the [main README](../README.md). The local repair retains the OEM version name **2.0.20.33** and version code **2000033** to identify its upstream base. It is a GlitchOS repair of that build, not an OEM update.

## Exact changes

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

## Why this fixed the failure

The phone connected, but native packet diagnostics showed invalid-stream markers before decoding. Both hardware and software decoders failed on the malformed input. The receiver advertised legacy pairing as unavailable while its handshake code expected the related key setup. Enabling the matching advertised capability restored valid packets and sustained mirroring on the tested phone.

UxPlay's maintainers documented the same capability/key-setup mismatch in [issue 176](https://github.com/FDH2/UxPlay/issues/176). Their [May 2023 correction](https://github.com/FDH2/UxPlay/commit/d38f8690c2645959c413823acdd2c4f98f545914) adjusted key handling when legacy pairing is not requested. This local recipe instead enables the pairing path already implemented by this specific receiver. It does not bypass authentication or modify session keys.

## Tests and limits

Run the synthetic patch tests without an APK or Android tools:

```powershell
.\tests\Test-AirPlayPatch.ps1
```

They cover missing/duplicate anchors, checksum and offset rejection, exactly one changed byte per native patch, preservation of input buffers, the intended manifest scope and rejection of unsupported originals. A complete build additionally validates the exact OEM-derived output hashes and signed APK. The repository intentionally has no OEM fixtures.

This is not a general AirPlay decoder patch or support claim for other TVs, firmware or phones. The known-good behavior belongs to the tested receiver build and setup. For another original checksum, the script stops before patching; do not remove that check or guess replacement offsets.
