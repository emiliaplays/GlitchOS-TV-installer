# Changelog

## Installer 1.0.0 — 2026-10-31

- Initial public installer package with GlitchOS TV Edition 1.3.1 source and tested launcher APK.
- Documented the direct Home configuration, seven-package optional cleanup and restoration scope.
- Added device-specific local AirPlay repair tooling; vendor receiver binaries, native libraries and decompiled vendor code are not distributed.
- Recorded successful launcher, picture, sound, rotation and reboot validation on the owner's CHiQ TV, tentatively identified as L40G7B; verified firmware model AI PONT, Android 14, build UKNV.260603.001.

## Launcher 1.3.1 — 2026-10-31

- Read the firmware's configured sharing name for AirPlay connection instructions.
- Preserved the receiver integration from 1.3; the receiver binary is unchanged.
- Release version code: 9.

## Launcher 1.3 — 2026-10-31

- Prefer the locally repaired CHiQ receiver while keeping the original system receiver intact as a fallback.
- Control receiver startup from GlitchOS and avoid duplicate original/repaired services.
- Retain Android's visible-client activity-launch allowance while the launcher is on screen.
- Verified the production receiver with iPhone picture, sound, rotation and a full TV reboot.

## Launcher 1.2.1 — 2026-10-31

- Added a visible service binding so Android 14 can open an incoming AirPlay mirror activity from the home screen.

## Launcher 1.2 — 2026-10-31

- Added a saved AirPlay enable/disable control using the TV's existing receiver service.

## Launcher 1.1 — 2026-10-31

- Added glass-style surfaces, reflective highlights and remote-focus effects using cached gradients.
- Added direct Home configuration for the tested firmware.

## Launcher 1.0 — 2026-10-31

- Initial native TV launcher with installed apps, favorites, search, inputs and settings shortcuts.
