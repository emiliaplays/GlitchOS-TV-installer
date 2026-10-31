# Launcher source

This directory contains the exact Java source, resources and manifest for GlitchOS TV Edition 1.3.1, version code 9. The matching tested APK is in [`../releases`](../releases/). The launcher is a native Android app using Android SDK classes; it has no third-party UI framework or Internet permission.

## Build on Windows

Install JDK 17, Android SDK Platform 35 and Android SDK Build-Tools 35.0.0. The script does not download tools. With `JAVA_HOME` and `ANDROID_SDK_ROOT` set:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\launcher\build.ps1
```

You can instead pass explicit installation paths:

```powershell
.\launcher\build.ps1 -JavaHomePath 'C:\Java\jdk-17' -AndroidSdkPath 'C:\Android\Sdk'
```

For tools stored outside the standard SDK layout, pass `-AndroidJarPath` and `-BuildToolsPath`. Other options include `-BuildToolsVersion`, `-CompileSdk`, `-VersionCode`, `-OutputPath`, `-KeystorePath` and `-KeyAlias`.

The script compiles resources with aapt2, Java with javac, and DEX with D8, then aligns and signs the APK. The default output is `launcher/output/GlitchOS-TV-Edition-1.3.1.apk`. Each build uses a fresh ignored directory under `launcher/.local/build/`.

## Signing your builds

On the first build, the script generates your own signing key and a random password under ignored `launcher/.local/`. Keep that folder private and back it up to sign compatible future updates. No project signing key is distributed in this repository.

For a custom keystore, set the `GLITCHOS_KEYSTORE_PASSWORD` environment variable before running with `-KeystorePath`; the key and store must use the same password. Passwords are passed to Java tools through a temporary environment variable, not included in build output.

Your own key will differ from the key that signed the supplied release APK. Android will not install a differently signed APK as an update to that release. Changing signing identity requires removing the existing launcher, which removes its saved preferences; restore another working Home app first. Keep the same key for subsequent builds.

The published APK's checksum identifies that exact release. A local rebuild uses a different signature and is not expected to have the same checksum.

## Receiver integration

The launcher prefers `com.glitchos.airplayrepair` if installed, otherwise the original `com.homwee.mmp.screenshare`. It binds the selected receiver while visible and uses the firmware's existing background-service option. The repaired receiver is built separately from the owner's matching TV firmware; its code and binaries are not included here.

AirPlay's displayed name is read from the firmware setting when available. The exact 1.3.1 source retains the original test receiver's fallback display name, `SmartTV(D245)`, for firmware that does not expose that setting. It does not connect to a hard-coded network address.
