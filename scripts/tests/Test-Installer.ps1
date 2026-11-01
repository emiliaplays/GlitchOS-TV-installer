[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path $PSScriptRoot -Parent
$installer = Join-Path $scriptRoot 'Install-GlitchOSTV.ps1'
$restorer = Join-Path $scriptRoot 'Restore-GlitchOSTV.ps1'
$mockAdb = Join-Path $PSScriptRoot 'Mock-Adb.ps1'
. (Join-Path $scriptRoot 'GlitchOS.Common.ps1')
$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $temporaryBase ('GlitchOSInstallerTests-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$oldMockVariable = $env:GLITCHOS_TEST_STATE
$env:GLITCHOS_TEST_STATE = Join-Path $testRoot 'mock-state.json'
$script:checks = 0

function Assert-True($Condition, [string]$Message) { if (!$Condition) { throw "FAIL: $Message" }; $script:checks++ }
function New-FixtureApk([string]$Name, [string]$Package) {
    $path = Join-Path $testRoot $Name
    $archive = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $archive.CreateEntry('AndroidManifest.xml'); $writer = New-Object IO.StreamWriter($entry.Open())
        try { $writer.Write('<manifest package="' + $Package + '" />') } finally { $writer.Dispose() }
    } finally { $archive.Dispose() }
    return $path
}
function Reset-Mock {
    $packageMap = [ordered]@{}
    foreach ($package in (@($script:GlitchHomePackages) + @($script:GlitchCleanupPackages) + @('com.homwee.mmp.screenshare', 'com.netflix.ninja', 'com.google.android.youtube.tv'))) { $packageMap[$package] = 0 }
    $mock = [ordered]@{
        Packages = $packageMap; Home = 'com.google.android.apps.tv.launcherx'; Sdk = 34; Connection = 'device'
        WebView = 'com.google.android.webview'; FailInstall = $false; FailLaunch = $false; FailDisable = ''; ResolveFailure = $false; SabotageBackupDirectory = ''
        Settings = [ordered]@{ secure_android_id = '1234567890abcdef'; secure_enabled_accessibility_services = 'com.spocky.projengmenu/com.spocky.projengmenu.services.ProjectivyAccessibilityService:flar2.homebutton/a.i'; secure_accessibility_enabled = '1'; global_tvmac = 'Old TV' }
        Log = @()
    }
    $mock | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $env:GLITCHOS_TEST_STATE -Encoding UTF8
}
function Read-Mock { return Get-Content -LiteralPath $env:GLITCHOS_TEST_STATE -Raw | ConvertFrom-Json }
function Write-Mock($Mock) { $Mock | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $env:GLITCHOS_TEST_STATE -Encoding UTF8 }
function Find-Backup([string]$Directory) { return @(Get-ChildItem -LiteralPath $Directory -Filter '*.json')[0].FullName }
function Invoke-TestInstall([string]$Directory, [hashtable]$Extra = @{}) {
    & $installer -Device 'MOCK-TV' -AdbPath $mockAdb -LauncherApk $launcher -BackupDirectory $Directory @Extra | Out-Null
}
function Expect-Failure([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action | Out-Null } catch { $caught = $true; Assert-True ($_.Exception.Message -match $Pattern) ('Expected error ' + $Pattern + '; got ' + $_.Exception.Message) }
    Assert-True $caught 'Operation should fail'
}

$completed = $false
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $launcher = New-FixtureApk 'launcher.apk' 'com.glitchos.tv'
    $repair = New-FixtureApk 'repair.apk' 'com.glitchos.airplayrepair'
    $wrong = New-FixtureApk 'wrong.apk' 'example.wrong'
    Assert-True ((Get-GlitchApkPackage $launcher) -eq 'com.glitchos.tv') 'APK manifest package parser'
    $release = Join-Path (Split-Path $scriptRoot -Parent) 'releases\GlitchOS-TV-Edition-1.4.0.apk'
    if (Test-Path -LiteralPath $release) { Assert-True ((Get-GlitchApkPackage $release) -eq 'com.glitchos.tv') 'Actual release compiled manifest parser' }

    # Exercise the public Windows PowerShell -File entrypoint with both path defaults.
    # Parameter-default expressions cannot rely on PSScriptRoot during PS 5.1 -File binding.
    Reset-Mock
    Assert-True (Test-Path -LiteralPath $release) 'Default launcher release exists for entrypoint regression'
    $defaultBackupDirectory = Join-Path (Split-Path $scriptRoot -Parent) 'backups'
    $defaultBackupExisted = Test-Path -LiteralPath $defaultBackupDirectory
    $defaultBackupCount = if ($defaultBackupExisted) { @(Get-ChildItem -LiteralPath $defaultBackupDirectory -File).Count } else { 0 }
    $entrypointPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $entrypointOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Device 'MOCK-TV' -AdbPath $mockAdb -WhatIf 2>&1
        $entrypointExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $entrypointPreference }
    Assert-True ($entrypointExit -eq 0) ('Windows PowerShell -File default paths succeed: ' + ($entrypointOutput -join ' '))
    Assert-True (@((Read-Mock).Log).Count -gt 0) 'Subprocess entrypoint contacted only the mock reader'
    Assert-True (@((Read-Mock).Log | Where-Object Mutation).Count -eq 0) 'Subprocess WhatIf made no device mutations'
    Assert-True ((Test-Path -LiteralPath $defaultBackupDirectory) -eq $defaultBackupExisted) 'Subprocess WhatIf does not create the default backup directory'
    if ($defaultBackupExisted) { Assert-True (@(Get-ChildItem -LiteralPath $defaultBackupDirectory -File).Count -eq $defaultBackupCount) 'Subprocess WhatIf adds no backup files' }

    Reset-Mock
    $backupDirectory = Join-Path $testRoot 'dry-run'
    Invoke-TestInstall $backupDirectory @{ WhatIf = $true; Cleanup = $true; AirPlayApk = $repair; AirPlayName = 'New TV' }
    Assert-True (@((Read-Mock).Log | Where-Object Mutation).Count -eq 0) 'WhatIf makes no device mutations'
    Assert-True (!(Test-Path -LiteralPath $backupDirectory)) 'WhatIf creates no backup files'

    Reset-Mock
    $backupDirectory = Join-Path $testRoot 'default'
    Invoke-TestInstall $backupDirectory
    $mock = Read-Mock
    $mutations = @($mock.Log | Where-Object Mutation | ForEach-Object { $_.Arguments -join ' ' })
    $firstDisable = [Array]::FindIndex([string[]]$mutations, [Predicate[string]]{ param($s) $s.StartsWith('pm disable-user') })
    $launchIndex = [Array]::FindIndex([string[]]$mutations, [Predicate[string]]{ param($s) $s.StartsWith('am start ') })
    Assert-True ($firstDisable -gt $launchIndex -and $launchIndex -ge 0) 'Explicit launcher start precedes package disable'
    Assert-True (@($mutations | Where-Object { $_ -match '^pm disable-user' }).Count -eq 2) 'Default only disables the two Home packages'
    Assert-True ($mock.Packages.'com.netflix.ninja' -eq 0 -and $mock.Packages.'com.google.android.youtube.tv' -eq 0) 'Entertainment apps remain enabled'
    Assert-True ($mock.Settings.secure_enabled_accessibility_services -eq 'flar2.homebutton/a.i') 'Unrelated accessibility service preserved'
    $stateFile = Find-Backup $backupDirectory
    $mock.Settings.secure_android_id = 'different-tv'; Write-Mock $mock
    $beforeCount = @($mock.Log | Where-Object Mutation).Count
    Expect-Failure { & $restorer -Device 'MOCK-TV' -AdbPath $mockAdb -StateFile $stateFile } 'different TV'
    Assert-True (@((Read-Mock).Log | Where-Object Mutation).Count -eq $beforeCount) 'Wrong-device restore refuses before mutation'
    $mock = Read-Mock; $mock.Settings.secure_android_id = '1234567890abcdef'; Write-Mock $mock
    & $restorer -Device 'MOCK-TV' -AdbPath $mockAdb -StateFile $stateFile | Out-Null
    $mock = Read-Mock
    Assert-True ($mock.Home -eq 'com.google.android.apps.tv.launcherx' -and $mock.Packages.'com.google.android.apps.tv.launcherx' -eq 0) 'Home and exact package state restored'
    Assert-True ($mock.Settings.secure_enabled_accessibility_services -match 'ProjectivyAccessibilityService') 'Original accessibility configuration restored'
    Assert-True ($mock.Packages.PSObject.Properties.Name -contains 'com.glitchos.tv') 'Restore retains installed launcher'

    Reset-Mock
    $mock = Read-Mock; $mock.FailLaunch = $true; Write-Mock $mock
    Expect-Failure { Invoke-TestInstall (Join-Path $testRoot 'launch-failure') } 'Installation failed'
    $mock = Read-Mock
    Assert-True (@($mock.Log | Where-Object { ($_.Arguments -join ' ') -match '^pm disable-user' }).Count -eq 0) 'Failed launcher never disables Home packages'
    Assert-True ($mock.Home -eq 'com.google.android.apps.tv.launcherx') 'Failed launcher restores role'

    Reset-Mock
    $mock = Read-Mock; $mock.FailDisable = 'com.google.android.feedback'; Write-Mock $mock
    Expect-Failure { Invoke-TestInstall (Join-Path $testRoot 'cleanup-failure') @{ Cleanup = $true } } 'Installation failed'
    $mock = Read-Mock
    Assert-True ($mock.Packages.'com.homwee.store' -eq 0 -and $mock.Packages.'com.google.android.apps.tv.launcherx' -eq 0) 'Partial cleanup rolls back all attempted changes'

    Reset-Mock
    $mock = Read-Mock; $mock.WebView = 'com.google.android.webview.canary'; Write-Mock $mock
    Invoke-TestInstall (Join-Path $testRoot 'active-canary') @{ Cleanup = $true }
    Assert-True ((Read-Mock).Packages.'com.google.android.webview.canary' -eq 0) 'Active Canary is not disabled'

    Reset-Mock
    $backupDirectory = Join-Path $testRoot 'optional-airplay'
    $name = 'Glitch''s TV; $(echo nope)'
    Invoke-TestInstall $backupDirectory @{ AirPlayApk = $repair; AirPlayName = $name }
    Assert-True ((Read-Mock).Settings.global_tvmac -ceq $name) 'AirPlay name shell metacharacters remain literal'
    & $restorer -Device 'MOCK-TV' -AdbPath $mockAdb -StateFile (Find-Backup $backupDirectory) | Out-Null
    Assert-True ((Read-Mock).Packages.'com.glitchos.airplayrepair' -eq 3) 'New repair is disabled on restore'
    Assert-True ((Read-Mock).Packages.'com.homwee.mmp.screenshare' -eq 0) 'Original receiver untouched'
    Assert-True ((Read-Mock).Settings.global_tvmac -eq 'Old TV') 'Sharing name restored'

    Reset-Mock
    $mock = Read-Mock
    $mock.Packages | Add-Member -NotePropertyName 'com.glitchos.tv' -NotePropertyValue 3
    $mock.Packages | Add-Member -NotePropertyName 'com.glitchos.airplayrepair' -NotePropertyValue 4
    Write-Mock $mock
    $backupDirectory = Join-Path $testRoot 'existing-disabled'
    Invoke-TestInstall $backupDirectory @{ AirPlayApk = $repair }
    Assert-True ((Read-Mock).Packages.'com.glitchos.tv' -eq 1 -and (Read-Mock).Packages.'com.glitchos.airplayrepair' -eq 1) 'Previously disabled apps enabled for installation'
    & $restorer -Device 'MOCK-TV' -AdbPath $mockAdb -StateFile (Find-Backup $backupDirectory) | Out-Null
    Assert-True ((Read-Mock).Packages.'com.glitchos.tv' -eq 3 -and (Read-Mock).Packages.'com.glitchos.airplayrepair' -eq 4) 'Preexisting app enabled states restored exactly'

    Reset-Mock
    $mock = Read-Mock
    $mock.Packages | Add-Member -NotePropertyName 'com.glitchos.tv' -NotePropertyValue 0
    $mock.Packages | Add-Member -NotePropertyName 'com.glitchos.airplayrepair' -NotePropertyValue 0
    $mock.Packages.'com.google.android.apps.tv.launcherx' = 3
    $mock.Packages.'com.google.android.tungsten.setupwraith' = 3
    $mock.Home = 'com.glitchos.tv'; Write-Mock $mock
    $backupDirectory = Join-Path $testRoot 'existing-enabled-repair'
    Invoke-TestInstall $backupDirectory @{ AirPlayApk = $repair }
    & $restorer -Device 'MOCK-TV' -AdbPath $mockAdb -StateFile (Find-Backup $backupDirectory) | Out-Null
    Assert-True ((Read-Mock).Packages.'com.glitchos.airplayrepair' -eq 0) 'Preexisting enabled repair remains enabled'
    Assert-True ((Read-Mock).Home -eq 'com.glitchos.tv') 'Existing GlitchOS Home role is preserved on restore'

    Reset-Mock
    Expect-Failure { Invoke-TestInstall (Join-Path $testRoot 'wrong-apk') @{ AirPlayApk = $wrong } } 'expected'
    Assert-True (@((Read-Mock).Log).Count -eq 0) 'Wrong APK rejected before device contact'
    $mock = Read-Mock; $mock.Sdk = 28; Write-Mock $mock
    Expect-Failure { Invoke-TestInstall (Join-Path $testRoot 'old-android') } 'API 29'
    Assert-True (@((Read-Mock).Log | Where-Object Mutation).Count -eq 0) 'Unsupported Android version is read-only'

    Reset-Mock
    $mock = Read-Mock; $mock.FailInstall = $true; Write-Mock $mock
    Expect-Failure { Invoke-TestInstall (Join-Path $testRoot 'install-failure') } 'Installation failed'
    Assert-True (@((Read-Mock).Log | Where-Object { ($_.Arguments -join ' ') -match '^pm disable-user|^cmd package set-home-activity' }).Count -eq 0) 'ADB install failure never changes Home or disables packages'

    Reset-Mock
    $mock = Read-Mock; $mock.SabotageBackupDirectory = Join-Path $testRoot 'unavailable-backup'; Write-Mock $mock
    Expect-Failure { Invoke-TestInstall (Join-Path $testRoot 'unavailable-backup') } 'Installation failed'
    Assert-True ((Read-Mock).Home -eq 'com.google.android.apps.tv.launcherx') 'Backup write failure still restores Home'
    Assert-True ((Read-Mock).Packages.'com.google.android.apps.tv.launcherx' -eq 0) 'Backup write failure still restores package state from memory'

    Reset-Mock
    Expect-Failure { Invoke-TestInstall (Join-Path $testRoot 'invalid-name') @{ AirPlayName = ' TV ' } } 'whitespace'
    Assert-True (@((Read-Mock).Log).Count -eq 0) 'Whitespace-padded name rejected before device contact'

    Write-Output "PASS: $script:checks assertions. All device operations used Mock-Adb.ps1; no TV was contacted."
    $completed = $true
} finally {
    $env:GLITCHOS_TEST_STATE = $oldMockVariable
    if ($completed) {
        # Verify the absolute target before recursive deletion, using PowerShell end-to-end.
        $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
        if ([IO.Path]::GetDirectoryName($resolvedTestRoot).TrimEnd('\', '/') -ne $temporaryBase -or ![IO.Path]::GetFileName($resolvedTestRoot).StartsWith('GlitchOSInstallerTests-')) { throw 'Refusing to delete an unexpected test directory.' }
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    } else { Write-Warning "Test files retained for inspection: $testRoot" }
}
