# Synthetic fixtures only: no OEM APK, native library or decompiled source required.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/Patch-AirPlayRepair.ps1')

function Assert-True { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw $Message } }
function Assert-Throws {
    param([scriptblock]$Action, [string]$Message)
    $thrown = $false
    try { $null = & $Action } catch { $thrown = $true }
    Assert-True $thrown $Message
}

Assert-True ((Replace-AirPlayExactText 'left OLD right' 'OLD' 'NEW') -eq 'left NEW right') 'Exact text replacement failed.'
Assert-Throws { Replace-AirPlayExactText 'OLD OLD' 'OLD' 'NEW' } 'Duplicate text anchors were accepted.'
Assert-Throws { Replace-AirPlayExactText 'unchanged' 'OLD' 'NEW' } 'A missing text anchor was accepted.'

$fixture = [Text.Encoding]::ASCII.GetBytes('fixture:0x527FFFF7,0x1E:end')
$beforeHash = Get-AirPlayBytesHash $fixture
$patched = Edit-AirPlayCapabilityBytes $fixture $beforeHash 8
Assert-True ([Text.Encoding]::ASCII.GetString($patched) -eq 'fixture:0x5A7FFFF7,0x1E:end') 'Capability bit patch is incorrect.'
Assert-True ((Get-AirPlayBytesHash $fixture) -eq $beforeHash) 'Native input array was modified in place.'
$differences = @(for ($index=0; $index -lt $fixture.Length; $index++) { if ($fixture[$index] -ne $patched[$index]) { $index } })
Assert-True ($patched.Length -eq $fixture.Length -and $differences.Count -eq 1 -and $differences[0] -eq 11) 'Native patch changed more than the intended byte.'
Assert-Throws { Edit-AirPlayCapabilityBytes $fixture ('0' * 64) 8 } 'A native checksum mismatch was accepted.'
Assert-Throws { Edit-AirPlayCapabilityBytes $fixture $beforeHash 9 } 'An unexpected native offset was accepted.'
$duplicate = [Text.Encoding]::ASCII.GetBytes('fixture:0x527FFFF7,0x1E:0x527FFFF7')
Assert-Throws { Edit-AirPlayCapabilityBytes $duplicate (Get-AirPlayBytesHash $duplicate) 8 } 'Duplicate native capability strings were accepted.'
Assert-Throws { Edit-AirPlayCapabilityBytes $patched (Get-AirPlayBytesHash $patched) 8 } 'An already-patched library was accepted.'

$manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="com.homwee.mmp.screenshare">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application android:label="@string/app_name" android:name="com.changhong.mmp.airplay.AirPlayApplication">
        <receiver android:enabled="true" android:exported="true" android:name="com.changhong.mmp.receiver.BootReceiver">
        </receiver>
    </application>
</manifest>
'@
$updatedManifest = Edit-AirPlayManifestText $manifest
[xml]$xml = $updatedManifest
$android = 'http://schemas.android.com/apk/res/android'
Assert-True ($xml.DocumentElement.GetAttribute('package') -eq 'com.glitchos.airplayrepair') 'Manifest clone identity is incorrect.'
$application = $xml.SelectSingleNode('/manifest/application')
Assert-True ($application.GetAttribute('label',$android) -eq 'GlitchOS AirPlay') 'Manifest label is incorrect.'
Assert-True ($application.GetAttribute('name',$android) -eq 'com.changhong.mmp.airplay.AirPlayApplication') 'JNI/application class identity changed.'
$receiver = $xml.SelectSingleNode('/manifest/application/receiver')
Assert-True ($receiver.GetAttribute('enabled',$android) -eq 'false' -and $receiver.GetAttribute('exported',$android) -eq 'false') 'Boot receiver was not disabled.'
Assert-True ($xml.SelectNodes('/manifest/uses-feature').Count -eq 2) 'Optional TV features missing.'
Assert-True ($xml.SelectNodes('/manifest/uses-permission').Count -eq 1) 'Permissions changed unexpectedly.'
Assert-True ($xml.SelectNodes('//activity').Count -eq 0) 'A test or launcher activity was added.'
Assert-Throws { Edit-AirPlayManifestText $updatedManifest } 'Already-patched manifest was accepted.'

$unknownApk = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($unknownApk, 'synthetic non-OEM APK fixture')
    $unknownHash = (Get-FileHash -LiteralPath $unknownApk).Hash
    Assert-Throws { Assert-AirPlayOriginalApk $unknownApk } 'Unsupported OEM APK was accepted.'
    Assert-Throws { Invoke-AirPlayRepairPatch -Directory (Split-Path $unknownApk -Parent) -Apk $unknownApk } 'Unknown APK was allowed into patch planning.'
    Assert-True ((Get-FileHash -LiteralPath $unknownApk).Hash -eq $unknownHash) 'Rejected input was modified.'
} finally { Remove-Item -LiteralPath $unknownApk -Force }

Write-Host 'AirPlay patch tests passed: exact anchors, checksum/offset gates, one-byte-only edits, immutable input, manifest scope and unsupported-build refusal.'
