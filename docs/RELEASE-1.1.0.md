# GlitchOS TV installer v1.1.0 — Now Playing

Includes **GlitchOS TV Edition 1.4.0 (version code 10)**. The new Now Playing tab brings titles, artwork, progress, play/pause, previous/next, 10-second skips, player selection and return-to-app controls to the launcher. It also fixes glass opacity during redraws so focused buttons stay readable.

The installer now selects the new APK by default. Optional cleanup and the CHiQ AirPlay repair recipe remain unchanged. The receiver is still built locally from the exact supported original APK; OEM binaries and private signing keys are not included.

## Install or update

- Download `GlitchOS-TV-installer-v1.1.0.zip` for the installer, signed launcher, source and all guides.
- Existing installations: follow [update instructions](NOW-PLAYING.md) using `adb install -r`; no repeated cleanup is needed.
- First installation: follow [Getting started](GETTING-STARTED.md).
- Media controls require optional Android notification-listener access. The guide explains enabling and revoking it; this grant is separate from installer backup/restore.
- Give the included `AI-INSTALL.md` to your coding AI for assisted setup.

## Tested scope

Updated the owner's CHiQ TV, tentatively identified as L40G7B; verified firmware model Changhong AI PONT, Android 14/API 34, build UKNV.260603.001. Spotify title/art/progress and pause/resume worked. Two temporary silent players verified next/previous, exact 10-second seeks, session selection, unsupported actions, D-pad navigation, session removal and permission recovery. The test app was removed. Full iPhone mirroring and reboot tests were performed on the earlier receiver integration, not repeated for this launcher-only update.

App compatibility depends on active Android media sessions and supported actions. Some video apps stop on Home. This is not universal channel control or an AirPlay remote.

Verify release downloads using the attached `SHA256SUMS`. The separate source ZIP is the complete repository at this tag, including build instructions; the project ZIP also contains the tested signed APK.
