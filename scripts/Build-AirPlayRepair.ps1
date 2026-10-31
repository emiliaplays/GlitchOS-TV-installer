<# Builds a local repair from the owner's supported OEM APK. Does not install anything. #>
[CmdletBinding(DefaultParameterSetName='Apk')]
param(
    [Parameter(Mandatory, ParameterSetName='Apk')][string]$OriginalApk,
    [Parameter(Mandatory, ParameterSetName='Device')][Alias('DeviceSerial')][string]$Device,
    [Parameter(ParameterSetName='Device')][string]$AdbPath = 'adb',
    [Parameter(Mandatory)][string]$JavaPath,
    [Parameter(Mandatory)][string]$ApktoolJar,
    [Parameter(Mandatory)][string]$BuildToolsPath,
    [Parameter(Mandatory)][string]$KeyStore,
    [Parameter(Mandatory)][string]$KeyAlias,
    [string]$OutputDirectory,
    [string]$StorePasswordEnvironmentVariable,
    [string]$KeyPasswordEnvironmentVariable
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$inputMode = $PSCmdlet.ParameterSetName
. (Join-Path $PSScriptRoot 'Patch-AirPlayRepair.ps1')

function Resolve-AirPlayExecutable {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Resolve-Path -LiteralPath $Path).Path }
    return (Get-Command -Name $Path -CommandType Application -ErrorAction Stop).Source
}

function Invoke-AirPlayExternal {
    param([string]$Executable, [string[]]$Arguments, [string]$Action, [switch]$Capture)
    $previousPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 turns benign native stderr into ErrorRecords.
        # The process exit code, not the selected output stream, determines failure.
        $ErrorActionPreference = 'Continue'
        $lines = @(& $Executable @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($exitCode -ne 0) { throw "$Action failed (exit $exitCode):`n$($lines -join "`n")" }
    if ($Capture) { return @($lines | ForEach-Object { $_.ToString() }) }
    foreach ($line in $lines) { Write-Host $line }
}

function Read-AirPlayZipEntry {
    param($Entry)
    if ($null -eq $Entry) { throw 'Required APK entry is missing.' }
    $stream = $Entry.Open()
    $memory = New-Object IO.MemoryStream
    try { $stream.CopyTo($memory); return ,$memory.ToArray() }
    finally { $stream.Dispose(); $memory.Dispose() }
}

function Assert-AirPlayBuiltApk {
    param([string]$Apk, [string]$SourceApk, [object[]]$PatchAudit)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $original = [IO.Compression.ZipFile]::OpenRead($SourceApk)
    $built = [IO.Compression.ZipFile]::OpenRead($Apk)
    try {
        $dexNames = @($built.Entries | Where-Object { $_.FullName -match '^classes\d*\.dex$' } | ForEach-Object { $_.FullName } | Sort-Object)
        if (($dexNames -join ',') -ne 'classes.dex,classes2.dex') { throw 'Unexpected DEX files: diagnostic helpers must not be included.' }
        foreach ($name in $dexNames) {
            $dexText = [Text.Encoding]::ASCII.GetString((Read-AirPlayZipEntry $built.GetEntry($name)))
            foreach ($forbidden in @('HeaderProbe', 'RepairActivity', 'GlitchAirPlayHeader')) {
                if ($dexText.Contains($forbidden)) { throw "Diagnostic reference found in $name`: $forbidden" }
            }
        }
        $originalLibraries = @($original.Entries | Where-Object { $_.FullName -match '^lib/.+\.so$' })
        $builtLibraries = @($built.Entries | Where-Object { $_.FullName -match '^lib/.+\.so$' })
        if ($originalLibraries.Count -ne 8 -or $builtLibraries.Count -ne 8) { throw 'Unexpected native library inventory.' }
        foreach ($entry in $originalLibraries) {
            $change = @($PatchAudit | Where-Object { $_.RelativePath -eq $entry.FullName })
            $expected = Get-AirPlayBytesHash (Read-AirPlayZipEntry $entry)
            if ($change.Count -eq 1) { $expected = $change[0].AfterSha256 }
            $actual = Get-AirPlayBytesHash (Read-AirPlayZipEntry $built.GetEntry($entry.FullName))
            if ($actual -ne $expected) { throw "Unexpected built native library: $($entry.FullName)" }
        }
    } finally { $original.Dispose(); $built.Dispose() }
}

$java = Resolve-AirPlayExecutable $JavaPath
$apktool = (Resolve-Path -LiteralPath $ApktoolJar).Path
$buildTools = (Resolve-Path -LiteralPath $BuildToolsPath).Path
$keyFile = (Resolve-Path -LiteralPath $KeyStore).Path
$zipalign = Resolve-AirPlayExecutable (Join-Path $buildTools 'zipalign.exe')
$aapt2 = Resolve-AirPlayExecutable (Join-Path $buildTools 'aapt2.exe')
$apksigner = (Resolve-Path -LiteralPath (Join-Path $buildTools 'lib/apksigner.jar')).Path
$expectedApktool = 'dbf930b076c6b9be08d57c449cacefc3bdd6b71ebd59b3066fc0e1f5b14f9423'
if ((Get-FileHash -LiteralPath $apktool -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedApktool) {
    throw 'Use the official apktool_3.0.3.jar with the documented SHA256. No APK was decoded or modified.'
}
foreach ($variableName in @($StorePasswordEnvironmentVariable, $KeyPasswordEnvironmentVariable)) {
    if ($variableName -and [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($variableName))) {
        throw "Password environment variable is missing or empty: $variableName"
    }
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot '../artifacts/airplay-repair' }
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$buildName = 'build-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$work = Join-Path $outputRoot $buildName
[IO.Directory]::CreateDirectory($work) | Out-Null
$inputApk = Join-Path $work 'CHAirPlay-original.apk'

if ($inputMode -eq 'Device') {
    $adb = Resolve-AirPlayExecutable $AdbPath
    $packagePaths = @(Invoke-AirPlayExternal -Executable $adb -Arguments @('-s', $Device, 'shell', 'pm', 'path', 'com.homwee.mmp.screenshare') -Action 'Read original package path' -Capture |
        Where-Object { $_ -match '^package:/' } | ForEach-Object { $_.Substring(8).Trim() })
    if ($packagePaths.Count -ne 1 -or $packagePaths[0] -notmatch '^/[^\r\n]+\.apk$') {
        throw 'Expected one installed original CHAirPlay APK on the selected device.'
    }
    Invoke-AirPlayExternal -Executable $adb -Arguments @('-s', $Device, 'pull', $packagePaths[0], $inputApk) -Action 'Copy original APK from TV'
} else {
    Assert-AirPlayOriginalApk $OriginalApk
    [IO.File]::Copy((Resolve-Path -LiteralPath $OriginalApk).Path, $inputApk, $false)
}
Assert-AirPlayOriginalApk $inputApk
$decoded = Join-Path $work 'decoded'
$framework = Join-Path $work 'framework'
Write-Host 'Decoding the verified original APK locally...'
Invoke-AirPlayExternal -Executable $java -Arguments @('-jar', $apktool, 'd', '-p', $framework, '-o', $decoded, $inputApk) -Action 'Decode APK'
$patchAudit = @(Invoke-AirPlayRepairPatch -Directory $decoded -Apk $inputApk -AuditFile (Join-Path $work 'patch-audit.json'))
$unsigned = Join-Path $work 'GlitchOS-AirPlay-unsigned.apk'
$aligned = Join-Path $work 'GlitchOS-AirPlay-aligned.apk'
$signed = Join-Path $work 'GlitchOS-AirPlay.apk'
Write-Host 'Building the receiver clone with the verified production patch...'
Invoke-AirPlayExternal -Executable $java -Arguments @('-jar', $apktool, 'b', '-f', '-p', $framework, '-o', $unsigned, $decoded) -Action 'Build APK'
Assert-AirPlayBuiltApk -Apk $unsigned -SourceApk $inputApk -PatchAudit $patchAudit
$badging = @(Invoke-AirPlayExternal -Executable $aapt2 -Arguments @('dump', 'badging', $unsigned) -Action 'Inspect manifest' -Capture)
if (-not ($badging -match "^package: name='com.glitchos.airplayrepair'") -or
    -not ($badging -match "^application-label:'GlitchOS AirPlay'$") -or ($badging -match 'launchable-activity:')) {
    throw 'Unexpected production package, label or launcher activity.'
}
$tree = @(Invoke-AirPlayExternal -Executable $aapt2 -Arguments @('dump', 'xmltree', $unsigned, '--file', 'AndroidManifest.xml') -Action 'Inspect boot receiver' -Capture)
$bootLines = @($tree | Select-String -Pattern 'com.changhong.mmp.receiver.BootReceiver' -Context 0,2)
if ($bootLines.Count -ne 1 -or ($bootLines[0].Context.PostContext -join "`n") -notmatch ':enabled\([^)]*\)=false[\s\S]*:exported\([^)]*\)=false') {
    throw 'The clone boot receiver must be disabled and non-exported.'
}
Invoke-AirPlayExternal -Executable $zipalign -Arguments @('-p', '4', $unsigned, $aligned) -Action 'Align APK'
$signArguments = @('-jar', $apksigner, 'sign', '--ks', $keyFile, '--ks-key-alias', $KeyAlias, '--out', $signed)
if ($StorePasswordEnvironmentVariable) { $signArguments += @('--ks-pass', ('env:' + $StorePasswordEnvironmentVariable)) }
if ($KeyPasswordEnvironmentVariable) { $signArguments += @('--key-pass', ('env:' + $KeyPasswordEnvironmentVariable)) }
$signArguments += $aligned
Write-Host 'Signing with your local key (apksigner prompts if password variables were omitted)...'
# Keep prompts attached to the console; buffering stderr would hide password prompts.
$previousPreference = $ErrorActionPreference
try { $ErrorActionPreference = 'Continue'; & $java @signArguments; $signExitCode = $LASTEXITCODE }
finally { $ErrorActionPreference = $previousPreference }
if ($signExitCode -ne 0) { throw "Sign APK failed (exit $signExitCode)." }
Invoke-AirPlayExternal -Executable $java -Arguments @('-jar', $apksigner, 'verify', '--verbose', '--print-certs', $signed) -Action 'Verify signature'
Invoke-AirPlayExternal -Executable $zipalign -Arguments @('-c', '-p', '4', $signed) -Action 'Verify alignment'
Assert-AirPlayBuiltApk -Apk $signed -SourceApk $inputApk -PatchAudit $patchAudit
$result = [ordered]@{
    Package='com.glitchos.airplayrepair'; Label='GlitchOS AirPlay'; UpstreamVersion='2.0.20.33';
    OriginalApkSha256=(Get-FileHash -LiteralPath $inputApk).Hash.ToLowerInvariant();
    ApktoolSha256=$expectedApktool; Apk=$signed; ApkSha256=(Get-FileHash -LiteralPath $signed).Hash.ToLowerInvariant();
    PatchFiles=$patchAudit; BuiltUtc=[DateTime]::UtcNow.ToString('o')
}
[IO.File]::WriteAllText((Join-Path $work 'build-audit.json'), ($result | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
Write-Host "Built and verified: $signed"
Write-Host 'No app was installed and no TV settings were changed. Keep the original APK and your signing key private.'
