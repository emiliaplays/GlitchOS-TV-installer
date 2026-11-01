# Now Playing and updating to launcher 1.4.0

Open **Now Playing** in the top navigation. Compatible apps supply their title, artist, embedded cover art, progress and supported buttons. Use the D-pad and OK to pause/resume, skip tracks or episodes, or jump back/forward 10 seconds. **Switch player** changes which active session the controls target without starting or pausing anything. **Open app** returns to that player.

Buttons that the app does not support are disabled. Some video apps stop or remove their media session when Home is pressed. Channel switching and native AirPlay mirroring controls are not promised. Spotify display/pause/resume and two temporary test sessions were verified on the tested CHiQ TV; see [test details](TESTED-DEVICES.md).

## Update an existing working GlitchOS installation

Download and extract the complete [v1.1.0 release](https://github.com/emiliaplays/GlitchOS-TV-installer/releases/tag/v1.1.0). Open PowerShell in its folder and set your own ADB path and connected TV address:

```powershell
$adb = 'C:\Tools\platform-tools\adb.exe'
$tv = 'YOUR_TV_ADDRESS:PORT'
& $adb devices
Get-FileHash '.\releases\GlitchOS-TV-Edition-1.4.0.apk' -Algorithm SHA256
& $adb -s $tv install -r '.\releases\GlitchOS-TV-Edition-1.4.0.apk'
& $adb -s $tv shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
```

Compare the hash to [SHA256SUMS](../releases/SHA256SUMS). The published APK uses the same key as the previous release, preserving launcher data, favorites and settings. A custom build signed with your own key must be updated with that same key; if Android reports a signature mismatch, stop and build with the original key. Do not uninstall your working Home app to bypass it. No cleanup, receiver rebuild or Home reconfiguration is needed for this launcher update. First-time users should follow [Getting started](GETTING-STARTED.md).

## Enable media access

Android requires notification-listener access for the launcher to obtain other apps' active media sessions. In the tab, select **Enable controls → Open settings**, then enable **GlitchOS media controls**. This access is optional. GlitchOS does not inspect, save, dismiss or relay notification contents; see [privacy details](PRIVACY.md).

If the TV omits that settings screen, an authorized ADB connection can enable this component for Android owner user 0. Record whether it was already enabled before changing it:

```powershell
& $adb -s $tv shell settings get secure enabled_notification_listeners
& $adb -s $tv shell cmd notification allow_listener com.glitchos.tv/com.glitchos.tv.MediaAccessService 0
```

This preserves other listener grants. The tab updates after access changes. Start playback in a compatible app, press Home, open Now Playing, then test pause/resume. If several sessions exist, choose the desired one under Switch player. Empty or unavailable controls can mean the app does not expose a background media session.

## Turn media access off

Use **Media access** in the tab or revoke just this component:

```powershell
& $adb -s $tv shell cmd notification disallow_listener com.glitchos.tv/com.glitchos.tv.MediaAccessService 0
```

The regular installer does not grant this access, and its backup/restore scripts do not track or revoke it. When undoing setup, revoke it separately only if your setup added it. Revoking access does not uninstall the launcher or change other apps' permissions. See [changes and restore](CHANGES-AND-RESTORE.md) for Home and cleanup restoration.

Android reference: [MediaSessionManager access requirements](https://developer.android.com/reference/android/media/session/MediaSessionManager).
