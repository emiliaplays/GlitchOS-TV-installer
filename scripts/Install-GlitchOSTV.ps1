[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][string]$Device,
    [string]$AdbPath = 'adb',
    [string]$LauncherApk,
    [switch]$Cleanup,
    [string]$AirPlayApk,
    [string]$AirPlayName,
    [string]$BackupDirectory
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GlitchOS.Common.ps1')
if (!$LauncherApk) { $LauncherApk = Join-Path (Split-Path $PSScriptRoot -Parent) 'releases\GlitchOS-TV-Edition-1.3.1.apk' }
if (!$BackupDirectory) { $BackupDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'backups' }

$LauncherApk = Assert-GlitchApkPackage $LauncherApk 'com.glitchos.tv'
if ($AirPlayApk) { $AirPlayApk = Assert-GlitchApkPackage $AirPlayApk 'com.glitchos.airplayrepair' }
$renameAirPlay = $PSBoundParameters.ContainsKey('AirPlayName')
if ($renameAirPlay -and ([string]::IsNullOrWhiteSpace($AirPlayName) -or $AirPlayName -ne $AirPlayName.Trim() -or $AirPlayName -match '[\x00-\x1f\x7f]' -or [Text.Encoding]::UTF8.GetByteCount($AirPlayName) -gt 50)) {
    throw 'AirPlayName must be nonempty, have no leading/trailing whitespace or control characters, and fit within 50 UTF-8 bytes.'
}
Initialize-GlitchAdb $Device $AdbPath
$identity = Get-GlitchDeviceContext
$packages = @()
foreach ($package in (@($script:GlitchHomePackages) + @($script:GlitchCleanupPackages) + @('com.glitchos.tv', 'com.glitchos.airplayrepair', 'com.homwee.mmp.screenshare'))) {
    $packages += Get-GlitchPackageState $package
}
$originalReceiver = @($packages | Where-Object { $_.Package -eq 'com.homwee.mmp.screenshare' })[0]
if (($AirPlayApk -or $renameAirPlay) -and !$originalReceiver.Installed) { throw 'Optional AirPlay repair/naming requires this firmware''s original CHiQ receiver. It is not a universal receiver APK.' }
$homeRole = Get-GlitchHomeRole
if ($homeRole -and $homeRole -notmatch '^[a-zA-Z][a-zA-Z0-9_.]+$') { throw 'Cannot safely identify the original HOME role.' }
$services = Get-GlitchSetting 'secure' 'enabled_accessibility_services'
$accessibilityEnabled = Get-GlitchSetting 'secure' 'accessibility_enabled'
$removedServices = @(Get-GlitchRedirectServices $services)
$disablePackages = @($packages | Where-Object { $_.Installed -and $_.Package -in $script:GlitchHomePackages -and $_.Enabled -ne 3 } | ForEach-Object { $_.Package })
if ($Cleanup) {
    $cleanupCandidates = @($packages | Where-Object { $_.Installed -and $_.Package -in $script:GlitchCleanupPackages -and $_.Enabled -ne 3 } | ForEach-Object { $_.Package })
    if ('com.google.android.webview.canary' -in $cleanupCandidates) {
        $webview = Invoke-GlitchShell @('dumpsys', 'webviewupdate')
        $provider = [regex]::Match($webview, 'Current WebView package.*?:\s*\(([^,\s)]+)')
        if (!$provider.Success -or $provider.Groups[1].Value -eq 'com.google.android.webview.canary') {
            Write-Warning 'Skipping WebView Canary: it is active, or the active provider could not be verified.'
            $cleanupCandidates = @($cleanupCandidates | Where-Object { $_ -ne 'com.google.android.webview.canary' })
        }
    }
    $disablePackages += $cleanupCandidates
}
# Windows PowerShell 5.1's Get-FileHash uses a property pipeline that can be
# suppressed by a process-level -WhatIf. Hash this local file directly instead.
$hashAlgorithm = [Security.Cryptography.SHA256]::Create()
$launcherStream = [IO.File]::OpenRead($LauncherApk)
try { $launcherSha256 = [BitConverter]::ToString($hashAlgorithm.ComputeHash($launcherStream)).Replace('-', '') }
finally { $launcherStream.Dispose(); $hashAlgorithm.Dispose() }
$state = [ordered]@{
    SchemaVersion = 1; CreatedUtc = [DateTime]::UtcNow.ToString('o'); Status = 'Prepared'; Identity = $identity
    OriginalHomeRole = $homeRole; OriginalAccessibilityServices = $services; OriginalAccessibilityEnabled = $accessibilityEnabled
    OriginalAirPlayName = (Get-GlitchSetting 'global' 'tvmac'); Packages = $packages
    LauncherPreviouslyInstalled = [bool](@($packages | Where-Object { $_.Package -eq 'com.glitchos.tv' })[0].Installed)
    RepairPreviouslyInstalled = [bool](@($packages | Where-Object { $_.Package -eq 'com.glitchos.airplayrepair' })[0].Installed)
    LauncherSha256 = $launcherSha256
    Changes = [ordered]@{ Packages = @(); Home = $false; Accessibility = $false; AirPlayName = $false; LauncherInstall = $false; AirPlayInstall = $false }
    RestoreScope = 'Configuration only. Installed apps remain; previous APK versions and app data are not backed up.'
}
Write-Output "TV: $($identity.Manufacturer) $($identity.Model), Android API $($identity.Sdk), user 0."
Write-Output ('Planned package disables: ' + $(if ($disablePackages.Count) { $disablePackages -join ', ' } else { '(none)' }))
if ($removedServices.Count) { Write-Output 'Only the GlitchOS/Projectivy Home redirect accessibility entries will be removed.' }
if (!$PSCmdlet.ShouldProcess($Device, 'Back up current configuration, install GlitchOS, and make it Home with the selected options')) { return }

if (!(Test-Path -LiteralPath $BackupDirectory)) { New-Item -ItemType Directory -Path $BackupDirectory | Out-Null }
$backupRoot = (Resolve-Path -LiteralPath $BackupDirectory).Path
$safeDevice = $Device -replace '[^a-zA-Z0-9_.-]', '_'
$stateFile = Join-Path $backupRoot ($safeDevice + '-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff') + '.json')
Save-GlitchState $state $stateFile
Write-Output "Restore backup: $stateFile"
try {
    $state.Changes.LauncherInstall = $true; Save-GlitchState $state $stateFile
    Invoke-GlitchAdb @('install', '-r', $LauncherApk) | Out-Null
    if (!(Get-GlitchPackageState 'com.glitchos.tv').Installed) { throw 'Launcher installation verification failed.' }
    $launcherOriginal = @($packages | Where-Object { $_.Package -eq 'com.glitchos.tv' })[0]
    if ($launcherOriginal.Installed -and $launcherOriginal.Enabled -notin @(0, 1)) {
        $state.Changes.Packages += 'com.glitchos.tv'; Save-GlitchState $state $stateFile
        Set-GlitchPackageState 'com.glitchos.tv' 1
    }
    $state.Changes.Home = $true; Save-GlitchState $state $stateFile
    Invoke-GlitchShell @('cmd', 'package', 'set-home-activity', '--user', '0', 'com.glitchos.tv') | Out-Null
    # Some TVs force Google's resolver priority until its Home package is disabled.
    # Verify the requested role and explicitly launch GlitchOS before disabling anything.
    if ((Get-GlitchHomeRole) -ne 'com.glitchos.tv') { throw 'The TV did not assign the HOME role to GlitchOS.' }
    $launch = Invoke-GlitchShell @('am', 'start', '--user', '0', '-W', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME', '-n', 'com.glitchos.tv/.MainActivity')
    if ($launch -notmatch '(?im)^Status:\s*ok\s*$') { throw "GlitchOS could not be launched successfully: $launch" }
    foreach ($package in $disablePackages) {
        $state.Changes.Packages += $package; Save-GlitchState $state $stateFile
        Set-GlitchPackageState $package 3
    }
    if ($removedServices.Count) {
        $state.Changes.Accessibility = $true; Save-GlitchState $state $stateFile
        $remaining = @($services -split ':' | Where-Object { $_ -and $_ -notin $removedServices })
        if ($remaining.Count) { Set-GlitchSetting 'secure' 'enabled_accessibility_services' ($remaining -join ':') }
        else { Set-GlitchSetting 'secure' 'enabled_accessibility_services' $null; Set-GlitchSetting 'secure' 'accessibility_enabled' '0' }
    }
    Invoke-GlitchShell @('cmd', 'package', 'set-home-activity', '--user', '0', 'com.glitchos.tv') | Out-Null
    $resolved = Invoke-GlitchShell @('cmd', 'package', 'resolve-activity', '--brief', '--user', '0', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME')
    if ($resolved -notmatch '(?m)^com\.glitchos\.tv/(?:\.MainActivity|com\.glitchos\.tv\.MainActivity)\s*$') { throw 'HOME still resolves to another app. Restoring previous configuration.' }
    if ($AirPlayApk) {
        $state.Changes.AirPlayInstall = $true; Save-GlitchState $state $stateFile
        Invoke-GlitchAdb @('install', '-r', $AirPlayApk) | Out-Null
        if (!(Get-GlitchPackageState 'com.glitchos.airplayrepair').Installed) { throw 'AirPlay package installation verification failed.' }
        $repairOriginal = @($packages | Where-Object { $_.Package -eq 'com.glitchos.airplayrepair' })[0]
        if ($repairOriginal.Installed -and $repairOriginal.Enabled -notin @(0, 1)) {
            $state.Changes.Packages += 'com.glitchos.airplayrepair'; Save-GlitchState $state $stateFile
            Set-GlitchPackageState 'com.glitchos.airplayrepair' 1
        }
    }
    if ($renameAirPlay) {
        $state.Changes.AirPlayName = $true; Save-GlitchState $state $stateFile
        Set-GlitchSetting 'global' 'tvmac' $AirPlayName
        if ((Get-GlitchSetting 'global' 'tvmac') -ne $AirPlayName) { throw 'AirPlay sharing-name verification failed.' }
    }
    Invoke-GlitchShell @('am', 'start', '--user', '0', '-W', '-a', 'android.intent.action.MAIN', '-c', 'android.intent.category.HOME', '-n', 'com.glitchos.tv/.MainActivity') | Out-Null
    $state.Status = 'Installed'; Save-GlitchState $state $stateFile
    Write-Output "Installed. Keep the private restore backup: $stateFile"
    if ($AirPlayApk -or $renameAirPlay) { Write-Output 'Open the GlitchOS AirPlay menu and toggle AirPlay off/on to activate the receiver/name. Connect from the phone while GlitchOS is visible.' }
} catch {
    $failure = $_.Exception.Message
    $state.Status = 'Failed'
    try { Save-GlitchState $state $stateFile }
    catch { Write-Warning 'Could not update the backup file. Attempting restoration from the captured state in memory.' }
    try { Restore-GlitchConfiguration $state $stateFile; Write-Warning 'Previous configuration was restored. Any installed APKs remain installed.' }
    catch { Write-Warning "Automatic restore was incomplete: $($_.Exception.Message). Retry Restore-GlitchOSTV.ps1 with $stateFile when ADB is available." }
    throw "Installation failed: $failure. Backup: $stateFile"
}
