# Tested devices

## Verified unit

| Field | Verified value |
| --- | --- |
| Brand/manufacturer | CHiQ / Changhong |
| Firmware-reported model | AI PONT |
| Physical retail model | CHiQ L40G7B, tentatively identified by the owner; not independently checked against the physical label. |
| Android version | Android 14 |
| Android API level | 34 |
| Firmware build | UKNV.260603.001 |
| Test date | 2026-10-31 |
| Launcher release | GlitchOS TV Edition 1.3.1, version code 9 |
| Installer release | 1.0.0 |
| Original receiver | CHAirPlay 2.0.20.33, version code 2000033 |
| Original receiver package | `com.homwee.mmp.screenshare` |
| Repaired package | `com.glitchos.airplayrepair` |
| Receiver native ABI | `armeabi-v7a` |
| Physical display | 1920×1080 |
| Existing Android display override | 1280×720; retained in the final configuration. |
| Density | 213 dpi |

No serial number, network address, complete MAC address, account details or diagnostic log is needed to reproduce this compatibility record.

## What passed

| Function | Result and scope |
| --- | --- |
| Launcher installation | Final launcher APK installed and its Android signature verified. |
| Remote navigation | D-pad navigation, focus feedback and app opening were checked. |
| Home button | Home resolves directly to GlitchOS on this firmware. The Google TV launcher/setup packages remain reversibly disabled. |
| Launcher UI | Favorites, app search, installed-app artwork and glass-style surfaces are implemented in native Android UI. |
| TV integration | TV settings and the native input selector opened successfully. |
| Selected cleanup | Seven requested packages disabled for the active user, with previous states saved. Stable WebView and entertainment apps retained. |
| AirPlay discovery | Repaired receiver's active discovery and connection-response capability values agree. |
| iPhone picture | User confirmed a visible picture and a stable connection. |
| Audio | User confirmed sound works. |
| Rotation/video test | User confirmed the phone rotation/video test completed successfully. |
| Restart recovery | After a full TV reboot, GlitchOS returned as Home, started the repaired receiver, and mirroring still worked. |
| Production receiver | No added header logger, test activity or third DEX; original hardware decoder retained. |
| Final network/decoder settings | Temporary DNS filtering and software-decoder experiments were reverted. |

Picture, sound, rotation and reboot validation were completed with launcher 1.3 and the final production receiver. Launcher 1.3.1 then changed only the displayed receiver-name instructions to read the firmware's saved sharing name; that update was installed and checked through the saved setting and network discovery. The receiver APK did not change for 1.3.1.

The configured system was fully working for these tested functions on this unit. The record does not claim that the public installer has already been run on additional TVs, that every retained app was playback-tested, or that protected streaming content can be mirrored.

## Installer and build validation

The TV configuration above was applied and tested before the public installer was packaged. Installer 1.0.0 is validated separately with automated mock-device tests and a read-only `-WhatIf` dry run on the configured TV. A complete installation and restoration using the public scripts has not yet been repeated on a TV.

The public launcher build script was run successfully against JDK 17 and Android SDK 35 tools. Its generated APK passed Android v2/v3 signature verification using a newly generated local key. The supplied release APK remains the exact tested artifact with the checksum in `releases/SHA256SUMS`.

## Limits

- Other CHiQ retail models, firmware revisions, Android versions and receiver binary variants are unverified.
- The owner tentatively identified the retail model as CHiQ L40G7B. That is distinct from the verified firmware-reported `AI PONT` name, and the physical model label has not been independently checked.
- No Apple certification, AirPlay 2, HomeKit or DRM compatibility claim is made.
- The pairing repair is specific to matching receiver binaries. Matching only a brand or app version is insufficient.
- The source uses the tested TV's native input action and receiver components; other TV firmware can implement these differently.

When reporting another device, include its retail model, firmware-reported model, Android/API version, firmware build, receiver version and which functions passed. Do not include serial numbers, complete MAC addresses, private network addresses, account information or unredacted system logs.
