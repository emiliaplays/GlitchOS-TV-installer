# See NOTICE.md for provenance and distribution notes.
[CmdletBinding()]
param([Alias('DecodedDirectory')][string]$PatchDecodedDirectory,
      [Alias('OriginalApk')][string]$PatchOriginalApk,
      [Alias('AuditPath')][string]$PatchAuditPath,
      [Alias('CheckOnly')][switch]$PatchCheckOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AirPlayBytesHash {
    param([Parameter(Mandatory)][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-AirPlayOriginalApk {
    param([Parameter(Mandatory)][string]$Path)
    $expected = '6eae95d1f517b6f9f1beb903cd9d896b3106d58cdf077757cae6d8901a1077ec'
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Unsupported original APK SHA256: $actual. This repair supports only the documented CHAirPlay 2.0.20.33 build ($expected). No patch was applied."
    }
}

function Replace-AirPlayExactText {
    param([Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Old,
          [Parameter(Mandatory)][AllowEmptyString()][string]$New)
    $position = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($position -lt 0 -or $Text.IndexOf($Old, $position + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Patch anchor must occur exactly once: $Old"
    }
    return $Text.Substring(0, $position) + $New + $Text.Substring($position + $Old.Length)
}

function Edit-AirPlayManifestText {
    param([Parameter(Mandatory)][string]$Text)
    $text = Replace-AirPlayExactText $Text 'package="com.homwee.mmp.screenshare"' 'package="com.glitchos.airplayrepair"'
    $text = Replace-AirPlayExactText $text 'android:label="@string/app_name"' 'android:label="GlitchOS AirPlay"'
    $oldReceiver = '<receiver android:enabled="true" android:exported="true" android:name="com.changhong.mmp.receiver.BootReceiver">'
    $newReceiver = '<receiver android:enabled="false" android:exported="false" android:name="com.changhong.mmp.receiver.BootReceiver">'
    $text = Replace-AirPlayExactText $text $oldReceiver $newReceiver
    $matches = [regex]::Matches($text, '<manifest\b[^>]*>')
    if ($matches.Count -ne 1 -or $text.Contains('android.software.leanback') -or $text.Contains('android.hardware.touchscreen')) {
        throw 'Unexpected manifest feature declarations.'
    }
    $newline = "`n"
    if ($text.Contains("`r`n")) { $newline = "`r`n" }
    $features = $newline + '    <uses-feature android:name="android.software.leanback" android:required="false"/>' +
                $newline + '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>'
    return $text.Insert($matches[0].Index + $matches[0].Length, $features)
}

function Edit-AirPlayCapabilityBytes {
    param([Parameter(Mandatory)][byte[]]$Bytes, [Parameter(Mandatory)][string]$ExpectedSha256,
          [Parameter(Mandatory)][int]$ExpectedStringOffset)
    if ((Get-AirPlayBytesHash $Bytes) -ne $ExpectedSha256) { throw 'Unexpected native library checksum.' }
    $ascii = [Text.Encoding]::ASCII.GetString($Bytes)
    $oldValue = '0x527FFFF7'
    $offset = $ascii.IndexOf($oldValue, [StringComparison]::Ordinal)
    if ($offset -ne $ExpectedStringOffset -or $ascii.IndexOf($oldValue, $offset + $oldValue.Length, [StringComparison]::Ordinal) -ge 0) {
        throw 'Unexpected native capability location or occurrence count.'
    }
    [byte[]]$updated = $Bytes.Clone()
    $updated[$offset + 3] = 0x41 # ASCII 2 -> A: capability bit 27 only.
    return ,$updated
}

function Get-AirPlayRepairPatchPlan {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Apk)
    Assert-AirPlayOriginalApk $Apk
    $specifications = @(
        @{ Path='AndroidManifest.xml'; Kind='Manifest'; Before='bb7d2e3952357487f1d4d69116cc05e22e2a0c11f6890fd56f57e368f921b45e'; After='ac75e8241a2e641a314f06976581ed710dd6e62ed605f5630f6854edd4cb360a' },
        @{ Path='smali/b/d/a/a/a.smali'; Kind='BuildConfig'; Before='7f8ea22651cfc0c10f54596f9574634feade81f2143ca035591f588a6ce81dd5'; After='b0e1ef3a116f4e2a3247d75c998fa5e77dfb832f6929ae660feef66ea8d782f5' },
        @{ Path='smali/com/changhong/mmp/airplay/service/AirPlayInitService$k.smali'; Kind='SelfPackage'; Before='6393945efe997ef41cdc4901b8bdeb3f73a741933cb4bcc4e0d4fe7016b102e8'; After='790ba3b4f5a6cc84404ab8a92817d2abd983348ec76d57feb94525d4a17c1941' },
        @{ Path='lib/armeabi-v7a/libapscore.so'; Kind='Native'; Offset=0x1e3978; Before='eb697903b68a9a66319db1213d0eb6927fd40f08664544216c7a60eac791d60e'; After='8c9e53d730aa462232cb431f65c9d900c98978eccb6552699430bec2115773c0' },
        @{ Path='lib/armeabi-v7a/libjdns_sd.so'; Kind='Native'; Offset=0xd543; Before='cd6d6016607c1bbb7fce1cd036dc730f4139c5553c9d5244fec531e46c665fb5'; After='fe03a0a06c37fa3360d89a440401c6c59ede4eac398753791acd652a87cacc58' },
        @{ Path='lib/armeabi-v7a/libjdns_sd_embedded.so'; Kind='Native'; Offset=0x6070c; Before='40f5a7843a72bd0ecce8d11ef72fd37b4d1f967c89d65549b325ec215fbf31ae'; After='5aa6112e295c347b5ab6c8d3551116370998f7b14ab451305be3e144e2ec836b' }
    )
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    foreach ($spec in $specifications) {
        $file = Join-Path $Directory $spec.Path
        $before = [IO.File]::ReadAllBytes($file)
        if ((Get-AirPlayBytesHash $before) -ne $spec.Before) { throw "Unexpected decoded file: $($spec.Path). Decode the supported original with Apktool 3.0.3; no patch was applied." }
        if ($spec.Kind -eq 'Native') {
            $after = Edit-AirPlayCapabilityBytes $before $spec.Before $spec.Offset
        } else {
            $content = $utf8.GetString($before)
            switch ($spec.Kind) {
                'Manifest' { $updated = Edit-AirPlayManifestText $content }
                'BuildConfig' { $updated = Replace-AirPlayExactText $content '"com.homwee.mmp.screenshare"' '"com.glitchos.airplayrepair"' }
                'SelfPackage' { $updated = Replace-AirPlayExactText $content '"com.homwee.mmp.screenshare"' '"com.glitchos.airplayrepair"' }
            }
            $after = $utf8.GetBytes($updated)
        }
        $afterHash = Get-AirPlayBytesHash $after
        if ($afterHash -ne $spec.After) { throw "Patched output differs from the validated production file: $($spec.Path). No patch was applied." }
        [pscustomobject]@{ Path=$file; RelativePath=$spec.Path; Kind=$spec.Kind; BeforeSha256=$spec.Before; AfterSha256=$afterHash; Bytes=$after }
    }
}

function Invoke-AirPlayRepairPatch {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Apk,
          [string]$AuditFile, [switch]$PlanOnly)
    # Materialize and validate EVERY change before writing any file.
    $plan = @(Get-AirPlayRepairPatchPlan -Directory $Directory -Apk $Apk)
    $audit = @($plan | Select-Object RelativePath, Kind, BeforeSha256, AfterSha256)
    if (-not $PlanOnly) {
        foreach ($item in $plan) { [IO.File]::WriteAllBytes($item.Path, $item.Bytes) }
        if ($AuditFile) {
            [IO.File]::WriteAllText([IO.Path]::GetFullPath($AuditFile), ($audit | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
        }
    }
    return $audit
}

if ($MyInvocation.InvocationName -ne '.') {
    if (-not $PatchDecodedDirectory -or -not $PatchOriginalApk) { throw 'Supply -DecodedDirectory and -OriginalApk, or dot-source this helper for tests.' }
    Invoke-AirPlayRepairPatch -Directory $PatchDecodedDirectory -Apk $PatchOriginalApk -AuditFile $PatchAuditPath -PlanOnly:$PatchCheckOnly
}
