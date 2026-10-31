# Install GlitchOS on your TV: Windows guide

This guide installs the ready-made GlitchOS launcher from a Windows computer. You do not need to write code, install Android Studio or build an APK for the launcher.

**ADB** means Android Debug Bridge. It is Google's tool for letting an authorized computer install apps and change settings on an Android device. GlitchOS's installer uses it to communicate with your TV. [Official ADB documentation](https://developer.android.com/tools/adb).

The complete installer requires an **Android TV or Google TV running Android 10/API 29 or newer**, with Android's owner user **0** active. The launcher APK itself has a lower minimum of Android 8/API 26, but that does not make the installer compatible with older systems. The tested TV is an owner-reported, tentative CHiQ L40G7B with verified firmware model AI PONT; see [what has actually been tested](TESTED-DEVICES.md).

The default installation makes GlitchOS your Home screen and disables two Google TV Home/setup packages. It does not replace your firmware. Read [what changes and how to restore it](CHANGES-AND-RESTORE.md) before applying the preview.

## 1. Download and extract the project

1. Open [GlitchOS-TV-installer on GitHub](https://github.com/emiliaplays/GlitchOS-TV-installer).
2. Select the green **Code** button, then **Download ZIP**. This downloads the current `main` branch. You can also use this [direct current-main ZIP link](https://github.com/emiliaplays/GlitchOS-TV-installer/archive/refs/heads/main.zip).
3. In File Explorer, right-click the downloaded ZIP and choose **Extract All**. Do not run the project from inside the ZIP.
4. Put the extracted project folder at `C:\GlitchOS\GlitchOS-TV-installer`. You may rename the extracted `GlitchOS-TV-installer-main` folder to `GlitchOS-TV-installer`.

Check that the folder looks like this. If you see another project folder inside it, open that inner folder first:

```text
C:\GlitchOS\GlitchOS-TV-installer\
    README.md
    scripts\
        Install-GlitchOSTV.ps1
        Restore-GlitchOSTV.ps1
    releases\
        GlitchOS-TV-Edition-1.3.1.apk
    docs\
    launcher\
```

You can choose another location. If you do, change `$repo` in the commands below to match it.

If you already use Git, cloning is an alternative to downloading the ZIP:

```powershell
git clone https://github.com/emiliaplays/GlitchOS-TV-installer.git 'C:\GlitchOS\GlitchOS-TV-installer'
```

## 2. Download ADB and open PowerShell

Download **SDK Platform-Tools for Windows** from [Google's official download page](https://developer.android.com/tools/releases/platform-tools). Extract that ZIP to `C:\GlitchOS`, so that the executable is at:

```text
C:\GlitchOS\platform-tools\adb.exe
```

Open the Start menu and search for **Windows PowerShell**. Its built-in version 5.1 works; PowerShell 7 also works if you already have it. Use a normal PowerShell window, not Command Prompt. Administrator mode is not required by these instructions.

Paste this into PowerShell:

```powershell
$repo = 'C:\GlitchOS\GlitchOS-TV-installer'
$adb = 'C:\GlitchOS\platform-tools\adb.exe'
Set-Location -LiteralPath $repo
Test-Path '.\scripts\Install-GlitchOSTV.ps1'
& $adb version
```

The file check should print `True`, followed by ADB's version information. If either fails, correct the extraction paths before continuing.

Keep this PowerShell window open: `$repo`, `$adb` and the TV address you enter later are saved only in this session. The script examples call `powershell.exe`, which runs Windows PowerShell 5.1. If you prefer PowerShell 7, replace `powershell.exe` with `pwsh`. The `-ExecutionPolicy Bypass` argument applies to that script process; it does not permanently change Windows' execution policy.

## 3. Enable debugging on the TV

Keep the TV remote nearby. Connect the computer and TV to the same home network.

On many Google TVs, open **Settings → System → About**, highlight **Android TV OS build** or **Build number**, and press OK seven times. Return to Settings and find **Developer options**. Names and locations vary by manufacturer. [Android's developer-options instructions](https://developer.android.com/studio/debug/dev-options).

Use the connection method your TV actually provides:

| What your TV offers | Use this method |
| --- | --- |
| **Wireless debugging** with **Pair using pairing code** | Follow method A below. |
| **Network debugging / ADB debugging** with a listening address or port | Follow method B below. |
| Only **USB debugging** | Some TV firmware, including the tested CHiQ setup, also exposes network ADB. Other TVs require a supported USB debugging connection. Check your model's instructions; USB debugging alone does not guarantee port 5555 is available. |

Only authorize your own computer when the TV asks. You do not need OEM unlocking, a bootloader unlock or a factory reset.

### Method A: wireless pairing code

If your TV exposes this menu, enable **Wireless debugging**, then choose **Pair using pairing code**. Keep the pairing screen open. Enter its pairing address when the command asks, then enter the code shown on the TV:

```powershell
$pairAddress = Read-Host 'Enter the pairing IP:port shown on the TV'
& $adb pair $pairAddress
```

Return to the main Wireless debugging screen and use its **connection** IP address and port. This can be different from the pairing port:

```powershell
$tv = Read-Host 'Enter the connection IP:port from Wireless debugging'
& $adb connect $tv
```

The presence of the menu matters; Android's documented TV wireless-debugging support starts at Android 13/API 33, and manufacturers can expose different options. [Official pairing instructions](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi).

### Method B: network debugging address

Enable the TV's supported debugging option. Find its IP address in **Settings → Network & Internet → your connected network**, or the model's equivalent screen. Use the debugging port shown by the TV or specified for its firmware.

The tested CHiQ used port `5555`. That is not a universal port for every TV, and it is not the pairing-code method above. Enter your own TV address followed by its port:

```powershell
$tv = Read-Host 'Enter the TV debugging address as IP:port'
& $adb connect $tv
```

Accept **Allow USB debugging?** or **Allow debugging?** on the TV if it appears, even when the connection is over the network.

If your TV only supports a physical USB debugging connection, first establish that connection according to its manufacturer's instructions. Do not assume an ordinary TV USB socket supports it. Once ADB lists the TV, use its listed serial as `$tv` instead of a network address.

### Check the connection

```powershell
& $adb devices
```

Look for your TV followed by **`device`**. `unauthorized` means the TV still needs approval; `offline` means the connection is not ready. Do not run the installer until it shows `device`.

For an already connected USB device, set the serial from that list:

```powershell
$tv = Read-Host 'Enter the connected TV serial shown by adb devices'
```

## 4. Choose a setup and preview it

Choose **one** option below for this installation. `-WhatIf` previews the selected options: it reads the TV but does not install apps, change settings or create a backup. If the preview reports an unsupported device or another error, resolve that before applying anything.

### Option 1: launcher and direct Home only

This installs GlitchOS and makes Home open it directly. It disables the two Google TV Home/setup packages when present. It does not apply the seven-package cleanup.

Preview:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -WhatIf
```

Apply the same choice, with only `-WhatIf` removed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb
```

### Option 2: launcher, direct Home and selected cleanup

Use this pair of commands **instead of option 1** if you also want the seven packages listed in [Changes and restore](CHANGES-AND-RESTORE.md#optional-cleanup) disabled. Existing entertainment apps are retained. The installer skips Canary WebView if it is the active provider or cannot identify the active provider.

Preview:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -Cleanup -WhatIf
```

Apply the matching choice:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -Cleanup
```

Both options save the previous configuration before changing the TV. The direct Home setup disables Google TV's profile chooser and related setup/account flows; [restore the saved configuration](CHANGES-AND-RESTORE.md#restore-your-previous-configuration) before using those flows or resetting the TV.

## 5. Keep the backup and check the TV

The installer prints a line beginning **`Restore backup:`** with the full path to a JSON file. Copy that path somewhere you can find later. With the folders above, the file is inside:

```text
C:\GlitchOS\GlitchOS-TV-installer\backups\
```

Keep that backup and the extracted project folder. The backup contains device-specific information, so do not upload it to GitHub or attach it publicly. See [privacy guidance](PRIVACY.md).

On the TV, check that Home opens GlitchOS, use the D-pad and OK to open an app, and try the **Inputs** and **Settings** shortcuts. Hold OK on an app tile to manage favorites or open its app information.

The installer does not remove preinstalled APK files or free the storage occupied by them. It also does not delete your entertainment apps or their accounts.

If you reopen PowerShell later, repeat the `$repo`, `$adb`, `Set-Location` and connection steps before using the restore commands.

## Optional: repair AirPlay on a matching CHiQ receiver

This is a separate, more technical step. The launcher installer does not include a universal AirPlay receiver or automatically build one.

The supported original is **CHAirPlay 2.0.20.33**, version code **2000033**, and its actual binary fingerprints must match. A matching TV brand or version label alone is insufficient. Follow [the local AirPlay build guide](AIRPLAY.md); the builder refuses unsupported originals. The project does not distribute the vendor receiver APK or its libraries.

Once that guide has produced your own `GlitchOS-AirPlay.apk`, set its actual full path:

```powershell
$repairApk = Read-Host 'Enter the full path to your locally built GlitchOS-AirPlay.apk'
```

Preview and apply with the same options:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -AirPlayApk $repairApk -AirPlayName 'GlitchOS TV' -WhatIf
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-GlitchOSTV.ps1 -Device $tv -AdbPath $adb -AirPlayApk $repairApk -AirPlayName 'GlitchOS TV'
```

Add `-Cleanup` to **both** commands only if you also want cleanup applied during that run. Each run creates a new backup of the configuration as it exists then; keep the earlier backup too if you want to return to the state before your first installation.

Open GlitchOS's **AirPlay** control and turn it off, then on. Leave the GlitchOS home screen visible. On an iPhone on the same network, open **Control Center → Screen Mirroring** and choose the displayed receiver name. Picture, sound, rotation and restart recovery passed on the tested unit; protected video services and other TV models are not guaranteed.

## Common problems

| What you see | What to do |
| --- | --- |
| `Test-Path` prints `False` | Check that `$repo` points to the folder containing `README.md` and `scripts`, not its parent or an unopened ZIP. |
| `adb.exe` cannot be found | Check the extracted `platform-tools` folder and update `$adb`. A double-nested `platform-tools\platform-tools` folder is a common extraction mistake. |
| `unauthorized` | Look at the TV and accept its debugging prompt. Reconnect after approval. |
| Connection refused or timed out | Recheck the TV's current address, debugging option and port. For pairing, use the connection port after pairing. Keep both devices on the same home network; a guest network may isolate them. |
| Connection stops working after reboot | Check the TV's IP address and wireless-debugging port again; they may have changed. Update `$tv` and reconnect. |
| Installer says Android user is not `0` | Use the TV's owner/main Android user. Do not remove the check or force the installation on another user. |
| Scripts are blocked by execution policy | Use the full `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...` command shown above. Do not make a permanent machine-wide policy change. |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | An existing app has a different signing key. Use an update signed with the same key. Do not uninstall the current Home app until another working Home app has been restored. |
| Google TV appears again after a firmware update | Updates can re-enable its packages. Reconnect and inspect a new `-WhatIf` preview before applying the Home setup again. |
| AirPlay repair reports unsupported input | Keep the original receiver. Do not bypass the binary checks or use an APK from another TV. |
| Installation fails partway through | Read the final message. The installer attempts to restore the captured configuration; if the connection dropped, reconnect and run restore with the printed backup path. |

For restoration commands, use [Changes and restore](CHANGES-AND-RESTORE.md). When installation and testing are complete, you may turn debugging off in the TV settings; enable and authorize it again when you need to update or restore.
