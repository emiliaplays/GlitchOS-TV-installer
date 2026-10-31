# GlitchOS TV installer 1.0.0

Installs **GlitchOS TV Edition 1.3.1 (version code 9)** and provides a reversible Home-button configuration, optional cleanup and a local AirPlay repair build.

## Included

- The tested launcher APK and matching native Java source.
- Liquid-glass appearance, remote navigation, favorites, app search, clock, input/settings shortcuts and receiver controls.
- Direct Home routing, avoiding the Google TV flash on the tested firmware.
- An optional seven-package cleanup profile; streaming, music and game apps remain installed.
- A backup of relevant configuration before changes, an installer preview and a restore script.
- A strict local build recipe for **CHAirPlay 2.0.20.33 (2000033)**. The fix corrects inconsistent legacy-pairing capability advertisements in three native libraries. The patched receiver is built from the owner's own matching original APK; it is not included as a download.
- Receiver naming through the `-AirPlayName 'GlitchOS TV'` option.

## Tested TV

**CHiQ L40G7B** is the owner's probable retail model. The unit identifies itself as **Changhong AI PONT**, running **Android 14 / API 34**, build **UKNV.260603.001**.

The configured TV was fully working for the documented tested functions, including direct Home, launcher operation and iPhone mirroring with picture, sound and rotation after reboot. The new portable installer was checked with mocked installation/restore scenarios and a read-only preview on that TV. It has not been used for a second end-to-end installation on another television. See [TESTED-DEVICES.md](TESTED-DEVICES.md).

## Download and use

Download `GlitchOS-TV-installer-v1.0.0.zip`, extract it, and follow the Windows instructions in [README.md](../README.md). Preview the installer with `-WhatIf` before applying your chosen options. ADB requires approval on the TV.

The full installer requires Android TV 10/API 29 or newer and active user 0. The standalone launcher APK supports API 26 or newer. The AirPlay repair requires the exact documented original binary; mismatches are rejected before patching.

Firmware and app data are not replaced. Disabling preinstalled apps does not reclaim the system APKs' disk space. Restore recovers the saved configuration; it does not downgrade already installed app versions. No comparative performance benchmarks are claimed.
