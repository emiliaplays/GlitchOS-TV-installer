[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Device,
    [string]$AdbPath = 'adb',
    [string]$OutputFile
)
$ErrorActionPreference = 'Stop'

function Read-Adb([string[]]$Arguments) {
    $lines = @(& $AdbPath -s $Device @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "ADB read failed: $($Arguments -join ' ')`n$($lines -join "`n")" }
    return ($lines -join "`n").Trim()
}

if ((Read-Adb @('get-state')) -ne 'device') { throw 'The selected TV is not connected and authorized.' }
$installed = (Read-Adb @('shell','pm','list','packages','--user','0')) -split '\r?\n'
$disabled = (Read-Adb @('shell','pm','list','packages','-d','--user','0')) -split '\r?\n'
$targets = @(
    'com.glitchos.tv', 'com.glitchos.airplayrepair', 'com.homwee.mmp.screenshare',
    'com.google.android.apps.tv.launcherx', 'com.google.android.tungsten.setupwraith',
    'com.homwee.store', 'com.google.android.feedback', 'com.google.android.webview.canary',
    'com.google.android.syncadapters.calendar', 'com.homwee.mmp.fileexplorer',
    'com.homwee.mmp.imageplayer', 'com.homwee.help'
)
$packageReport = foreach ($package in $targets) {
    $present = $installed -contains "package:$package"
    $version = $null
    if ($present) {
        $details = Read-Adb @('shell','dumpsys','package',$package)
        if ($details -match '(?m)^\s*versionName=(\S+)') { $version = $Matches[1] }
    }
    [ordered]@{ Package=$package; Installed=$present; DisabledForUser0=($disabled -contains "package:$package"); Version=$version }
}
$report = [ordered]@{
    ReportVersion = 1
    GeneratedUtc = [DateTime]::UtcNow.ToString('o')
    Manufacturer = Read-Adb @('shell','getprop','ro.product.manufacturer')
    Model = Read-Adb @('shell','getprop','ro.product.model')
    Android = Read-Adb @('shell','getprop','ro.build.version.release')
    SDK = Read-Adb @('shell','getprop','ro.build.version.sdk')
    Build = Read-Adb @('shell','getprop','ro.build.id')
    ActiveUser = Read-Adb @('shell','am','get-current-user')
    Home = Read-Adb @('shell','cmd','package','resolve-activity','--brief','--user','0','-a','android.intent.action.MAIN','-c','android.intent.category.HOME')
    Packages = @($packageReport)
    Note = 'Read-only report. Connection address, serial, Android ID and MAC are intentionally omitted.'
}
$json = $report | ConvertTo-Json -Depth 6
if ($OutputFile) {
    [System.IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFile), $json, [System.Text.UTF8Encoding]::new($false))
}
$json
