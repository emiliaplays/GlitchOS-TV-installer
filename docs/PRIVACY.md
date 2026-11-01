# Privacy and local state

The GlitchOS launcher has no INTERNET permission, account system, advertising SDK or recommendation feed. Other TV apps and Android services retain their own network behavior. This project is not a system-wide ad blocker or telemetry remover.

The installer uses Android Debug Bridge (ADB) between your computer and your TV. Use a trusted local network. Android requires you to approve the computer on the TV. You can turn debugging off in the TV's developer settings when finished.

Installer backups can contain your device identifier, connection address, Home selection and accessibility-service configuration. Keep `backups/` private. The repository ignores backups, build outputs, extracted receiver files and signing keys by default.

If you report a problem, share only the necessary error text, Android version, model and firmware build. Remove IP addresses, serial numbers, MAC addresses, phone identifiers and tokens from diagnostics. Do not attach your signing key, complete device dump or vendor APK to a public issue.

Only the seven documented optional cleanup packages and two Google Home-routing packages are candidates for disabling. Entertainment apps, Google Play services and the active stable WebView are not cleanup targets. No DNS override is installed.

## Optional Now Playing access

Launcher 1.4.0 uses Android notification-listener access to obtain active media sessions. The launcher does not inspect, save, dismiss or relay notification contents. The service implements no notification-processing callbacks and disables notification-delivery categories through manifest filters on supported Android versions. Titles and embedded artwork are used locally while the tab is visible; no playback history or remote artwork downloads are added. The Android access grant is broader than these implemented functions and can be revoked at any time. See [setup and revocation](NOW-PLAYING.md).