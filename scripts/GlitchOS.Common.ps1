Set-StrictMode -Version 2.0

# Explicit package manifest: this installer never discovers additional apps to disable.
$script:GlitchHomePackages = @('com.google.android.apps.tv.launcherx', 'com.google.android.tungsten.setupwraith')
$script:GlitchCleanupPackages = @(
    'com.homwee.store', 'com.google.android.feedback', 'com.google.android.webview.canary',
    'com.google.android.syncadapters.calendar', 'com.homwee.mmp.fileexplorer',
    'com.homwee.mmp.imageplayer', 'com.homwee.help'
)
$script:GlitchOriginalReceiver = 'com.homwee.mmp.screenshare/com.changhong.mmp.airplay.service.AirPlayInitService'
$script:GlitchRepairReceiver = 'com.glitchos.airplayrepair/com.changhong.mmp.airplay.service.AirPlayInitService'

function ConvertTo-GlitchShellToken {
    param([AllowEmptyString()][string]$Value)
    # adb shell joins its arguments. Quote each token for Android's shell, not PowerShell.
    return "'" + $Value.Replace("'", "'\''") + "'"
}

function Initialize-GlitchAdb {
    param([string]$Device, [string]$AdbPath)
    if ($Device -notmatch '^[a-zA-Z0-9_.:\[\]%-]+$') { throw 'Device must be an ADB serial or host:port, without spaces or shell characters.' }
    $command = Get-Command $AdbPath -CommandType Application,ExternalScript -ErrorAction Stop
    $script:GlitchAdb = $command.Source
    $script:GlitchDevice = $Device
    if ($Device.Contains(':')) { Invoke-GlitchAdb -Arguments @('connect', $Device) -NoDevice | Out-Null }
    if ((Invoke-GlitchAdb -Arguments @('get-state')).Trim() -ne 'device') {
        throw 'The TV is not authorized or connected. Enable debugging, connect ADB, and accept its prompt on the TV.'
    }
}

function Invoke-GlitchAdb {
    param([string[]]$Arguments, [switch]$NoDevice, [switch]$AllowFailure)
    $nativeArguments = @()
    if (!$NoDevice) { $nativeArguments += @('-s', $script:GlitchDevice) }
    $nativeArguments += $Arguments
    $savedPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue' # Windows PowerShell wraps native stderr in ErrorRecord.
        $output = & $script:GlitchAdb @nativeArguments 2>&1
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $savedPreference }
    # Preserve meaningful spaces in saved settings; discard only native line endings.
    $text = (($output | ForEach-Object { $_.ToString() }) -join "`n").TrimEnd("`r", "`n")
    if (!$AllowFailure -and ($code -ne 0 -or $text -match '(?im)^(?:error:|Error |Failure\s*\[|SecurityException|java\..*Exception|Unknown command|failed to connect|cannot connect)')) {
        throw "ADB failed (exit $code): $text"
    }
    return $text
}

function Invoke-GlitchShell {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $remoteCommand = ($Arguments | ForEach-Object { ConvertTo-GlitchShellToken $_ }) -join ' '
    return Invoke-GlitchAdb -Arguments @('shell', $remoteCommand) -AllowFailure:$AllowFailure
}

function Get-GlitchSetting {
    param([string]$Namespace, [string]$Key)
    $value = Invoke-GlitchShell @('settings', '--user', '0', 'get', $Namespace, $Key)
    if ($value -eq 'null' -or $value -eq '') { return $null }
    return $value
}

function Set-GlitchSetting {
    param([string]$Namespace, [string]$Key, [AllowNull()][AllowEmptyString()]$Value)
    if ($null -eq $Value) { Invoke-GlitchShell @('settings', '--user', '0', 'delete', $Namespace, $Key) | Out-Null }
    else { Invoke-GlitchShell @('settings', '--user', '0', 'put', $Namespace, $Key, [string]$Value) | Out-Null }
}

function Get-GlitchDeviceContext {
    $sdkText = Invoke-GlitchShell @('getprop', 'ro.build.version.sdk')
    $sdk = 0
    if (![int]::TryParse($sdkText, [ref]$sdk) -or $sdk -lt 29) { throw 'This installer requires Android TV 10 (API 29) or newer. The launcher was tested on Android 14.' }
    $features = Invoke-GlitchShell @('pm', 'list', 'features')
    if ($features -notmatch 'feature:android\.(software\.leanback|hardware\.type\.television)\b') { throw 'This device does not report Android TV/Leanback support.' }
    if ((Invoke-GlitchShell @('am', 'get-current-user')) -ne '0') { throw 'Switch to the TV owner (user 0) before running this installer.' }
    $androidId = Get-GlitchSetting 'secure' 'android_id'
    $serial = Invoke-GlitchShell @('getprop', 'ro.serialno')
    if (!$serial -or $serial -eq 'unknown') { $serial = $null }
    if (!$androidId -and !$serial) { throw 'Cannot read a stable device identity. A device-specific restore backup cannot be created safely.' }
    return [ordered]@{
        Device = $script:GlitchDevice; AndroidId = $androidId; Serial = $serial; Sdk = $sdk
        Manufacturer = (Invoke-GlitchShell @('getprop', 'ro.product.manufacturer'))
        Model = (Invoke-GlitchShell @('getprop', 'ro.product.model'))
        Fingerprint = (Invoke-GlitchShell @('getprop', 'ro.build.fingerprint'))
    }
}

function Get-GlitchHomeRole {
    $text = Invoke-GlitchShell @('cmd', 'role', 'get-role-holders', '--user', '0', 'android.app.role.HOME')
    $holders = @($text -split '\r?\n' | Where-Object { $_ -match '^[a-zA-Z][a-zA-Z0-9_.]+$' })
    if ($holders.Count -gt 1) { throw 'Unexpected multiple HOME role holders; no changes made.' }
    if ($holders.Count) { return $holders[0] }
    return $null
}

function Get-GlitchPackageState {
    param([string]$Package)
    $paths = Invoke-GlitchShell @('pm', 'path', '--user', '0', $Package) -AllowFailure
    if ($paths -notmatch '(?m)^package:') { return [ordered]@{ Package = $Package; Installed = $false; Enabled = $null } }
    $dump = Invoke-GlitchShell @('dumpsys', 'package', $Package)
    $userLine = [regex]::Match($dump, '(?m)^\s*User 0:\s*([^\r\n]+)')
    $enabled = [regex]::Match($userLine.Value, '\benabled=(\d+)\b')
    if (!$userLine.Success -or !$enabled.Success -or $userLine.Value -notmatch '\binstalled=true\b') {
        throw "Cannot determine the enabled state for $Package (user 0)."
    }
    $state = [int]$enabled.Groups[1].Value
    if ($state -notin @(0, 1, 2, 3, 4)) { throw "Unsupported enabled state $state for $Package." }
    return [ordered]@{ Package = $Package; Installed = $true; Enabled = $state }
}

function Set-GlitchPackageState {
    param([string]$Package, [int]$Enabled)
    $operation = switch ($Enabled) { 0 { 'default-state' } 1 { 'enable' } 2 { 'disable' } 3 { 'disable-user' } 4 { 'disable-until-used' } default { throw 'Invalid package enabled state.' } }
    Invoke-GlitchShell @('pm', $operation, '--user', '0', $Package) | Out-Null
    $actual = Get-GlitchPackageState $Package
    if (!$actual.Installed -or $actual.Enabled -ne $Enabled) { throw "Package state verification failed for $Package." }
}

function Save-GlitchState {
    param($State, [string]$Path)
    $temporary = $Path + '.tmp'
    $State | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-GlitchRedirectServices {
    param([AllowNull()][string]$Services)
    return @($Services -split ':' | Where-Object {
        $_ -in @('com.glitchos.tv/com.glitchos.tv.HomeRedirectService', 'com.glitchos.tv/.HomeRedirectService',
            'com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService',
            'com.spocky.projengmenu/.services.ProjectivyAccessibilityService')
    })
}

function Assert-GlitchApkPackage {
    param([string]$Path, [string]$ExpectedPackage)
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { throw "APK not found: $Path" }
    $package = Get-GlitchApkPackage $Path
    if ($package -ne $ExpectedPackage) { throw "APK package is '$package'; expected '$ExpectedPackage'. No app was installed." }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Get-GlitchApkPackage {
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead((Resolve-Path -LiteralPath $Path).Path)
    try {
        $entry = $archive.GetEntry('AndroidManifest.xml')
        if (!$entry -or $entry.Length -gt 8MB) { throw 'Missing or oversized APK AndroidManifest.xml.' }
        $inputStream = $entry.Open(); $memory = New-Object IO.MemoryStream
        try { $inputStream.CopyTo($memory); [byte[]]$data = $memory.ToArray() }
        finally { $inputStream.Dispose(); $memory.Dispose() }
    } finally { $archive.Dispose() }
    if ($data.Length -lt 8) { throw 'Truncated APK manifest.' }
    # Text XML permits simple offline test fixtures; real APKs use compiled XML below.
    if ([Text.Encoding]::UTF8.GetString($data).TrimStart().StartsWith('<')) {
        $settings = New-Object Xml.XmlReaderSettings; $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit; $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create((New-Object IO.StringReader([Text.Encoding]::UTF8.GetString($data))), $settings)
        try { $document = New-Object Xml.XmlDocument; $document.Load($reader); return $document.DocumentElement.GetAttribute('package') }
        finally { $reader.Dispose() }
    }
    function Read-U16([int]$Offset) {
        if ($Offset -lt 0 -or $Offset + 2 -gt $data.Length) { throw 'Malformed compiled APK manifest.' }
        return [BitConverter]::ToUInt16($data, $Offset)
    }
    function Read-U32([int]$Offset) {
        if ($Offset -lt 0 -or $Offset + 4 -gt $data.Length) { throw 'Malformed compiled APK manifest.' }
        return [BitConverter]::ToUInt32($data, $Offset)
    }
    if ((Read-U16 0) -ne 3 -or (Read-U32 4) -gt $data.Length) { throw 'Unsupported APK manifest format.' }
    $strings = @(); $offset = [int](Read-U16 2)
    while ($offset + 8 -le $data.Length) {
        $kind = Read-U16 $offset; $header = [int](Read-U16 ($offset + 2)); $size = [long](Read-U32 ($offset + 4))
        if ($header -lt 8 -or $size -lt $header -or $offset + $size -gt $data.Length) { throw 'Invalid APK manifest chunk bounds.' }
        if ($kind -eq 1) {
            if ($header -lt 28) { throw 'Invalid APK string-pool header.' }
            $count = [long](Read-U32 ($offset + 8)); $flags = Read-U32 ($offset + 16); $start = [long](Read-U32 ($offset + 20))
            if ($count -gt 100000 -or $header + $count * 4 -gt $size -or $start -ge $size) { throw 'Invalid APK string pool.' }
            $strings = New-Object 'System.Collections.Generic.List[string]'
            for ($i = 0; $i -lt $count; $i++) {
                $cursor = [int]($offset + $start + (Read-U32 ($offset + $header + $i * 4)))
                if ($cursor -lt $offset -or $cursor -ge $offset + $size) { throw 'Invalid APK string offset.' }
                if (($flags -band 0x100) -ne 0) {
                    # UTF-8 stores UTF-16 length followed by encoded byte length.
                    for ($j = 0; $j -lt 2; $j++) {
                        if ($cursor -ge $offset + $size) { throw 'Truncated APK string length.' }
                        $length = [int]$data[$cursor]; $cursor++
                        if (($length -band 0x80) -ne 0) {
                            if ($cursor -ge $offset + $size) { throw 'Truncated APK string length.' }
                            $length = (($length -band 0x7f) * 256) + $data[$cursor]; $cursor++
                        }
                    }
                    if ($cursor + $length -ge $offset + $size) { throw 'Truncated APK string.' }
                    $strings.Add([Text.Encoding]::UTF8.GetString($data, $cursor, $length))
                } else {
                    $length = [long](Read-U16 $cursor); $cursor += 2
                    if (($length -band 0x8000) -ne 0) { $length = (($length -band 0x7fff) * 65536) + (Read-U16 $cursor); $cursor += 2 }
                    if ($length -gt 1000000 -or $cursor + 2 * $length + 2 -gt $offset + $size) { throw 'Truncated APK UTF-16 string.' }
                    $strings.Add([Text.Encoding]::Unicode.GetString($data, $cursor, [int](2 * $length)))
                }
            }
        } elseif ($kind -eq 0x102) {
            if ($header -lt 16 -or $size -lt 36) { throw 'Invalid APK element header.' }
            $extension = $offset + $header; $nameIndex = Read-U32 ($extension + 4)
            if ($nameIndex -ge $strings.Count) { throw 'Invalid APK element name.' }
            if ($strings[[int]$nameIndex] -eq 'manifest') {
                $attributeStart = Read-U16 ($extension + 8); $attributeSize = Read-U16 ($extension + 10); $attributeCount = Read-U16 ($extension + 12)
                if ($attributeSize -lt 20 -or $header + $attributeStart + $attributeSize * $attributeCount -gt $size) { throw 'Invalid APK attribute bounds.' }
                for ($i = 0; $i -lt $attributeCount; $i++) {
                    $attribute = $extension + $attributeStart + $i * $attributeSize
                    $nameIndex = Read-U32 ($attribute + 4)
                    if ($nameIndex -ge $strings.Count) { throw 'Invalid APK attribute name.' }
                    if ($strings[[int]$nameIndex] -eq 'package') {
                        $value = Read-U32 ($attribute + 8)
                        if ($value -eq [uint32]::MaxValue -and $data[$attribute + 15] -eq 3) { $value = Read-U32 ($attribute + 16) }
                        if ($value -ge $strings.Count) { throw 'Invalid APK package attribute.' }
                        return $strings[[int]$value]
                    }
                }
            }
        }
        $offset += [int]$size
    }
    throw 'No package identifier found in APK manifest.'
}

function Restore-GlitchConfiguration {
    param($State, [string]$StateFile)
    $allowed = @($script:GlitchHomePackages) + @($script:GlitchCleanupPackages) + @('com.glitchos.tv', 'com.glitchos.airplayrepair')
    # Restore the previous Home's packages before disabling an originally disabled launcher.
    $orderedPackages = @($State.Changes.Packages | Where-Object { $_ -notin @('com.glitchos.tv', 'com.glitchos.airplayrepair') })
    foreach ($package in @($State.Changes.Packages)) {
        if ($package -notin $allowed) { throw "Backup contains an unexpected package change: $package" }
        $entry = @($State.Packages | Where-Object { $_.Package -eq $package })
        if ($entry.Count -ne 1 -or !$entry[0].Installed) { throw "Backup lacks the original state for $package." }
    }
    foreach ($package in $orderedPackages) {
        $entry = @($State.Packages | Where-Object { $_.Package -eq $package })[0]
        Set-GlitchPackageState $package ([int]$entry.Enabled)
    }
    if ($State.Changes.Home) {
        if ($State.OriginalHomeRole) {
            Invoke-GlitchShell @('cmd', 'package', 'set-home-activity', '--user', '0', $State.OriginalHomeRole) | Out-Null
        } else {
            Invoke-GlitchShell @('cmd', 'role', 'clear-role-holders', '--user', '0', 'android.app.role.HOME') | Out-Null
        }
        if ((Get-GlitchHomeRole) -ne $State.OriginalHomeRole) { throw 'Original HOME role could not be restored.' }
    }
    if ($State.Changes.Accessibility) {
        Set-GlitchSetting 'secure' 'enabled_accessibility_services' $State.OriginalAccessibilityServices
        Set-GlitchSetting 'secure' 'accessibility_enabled' $State.OriginalAccessibilityEnabled
    }
    if ($State.Changes.AirPlayName) { Set-GlitchSetting 'global' 'tvmac' $State.OriginalAirPlayName }
    if ($State.Changes.AirPlayInstall -and (Get-GlitchPackageState 'com.glitchos.airplayrepair').Installed) {
        Invoke-GlitchShell @('am', 'stopservice', '--user', '0', '-n', $script:GlitchRepairReceiver) | Out-Null
        if (!$State.RepairPreviouslyInstalled) { Set-GlitchPackageState 'com.glitchos.airplayrepair' 3 }
    }
    foreach ($package in @($State.Changes.Packages | Where-Object { $_ -in @('com.glitchos.tv', 'com.glitchos.airplayrepair') })) {
        $entry = @($State.Packages | Where-Object { $_.Package -eq $package })[0]
        Set-GlitchPackageState $package ([int]$entry.Enabled)
    }
    if ($State.Changes.Home) { Invoke-GlitchShell @('input', 'keyevent', '3') | Out-Null }
    $State.Status = 'Restored'
    try { Save-GlitchState $State $StateFile }
    catch { Write-Warning "Configuration restored, but the backup status could not be saved: $StateFile" }
}
