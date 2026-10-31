# Local fake executable for Test-Installer.ps1. Never invokes ADB or accesses a TV.
$ErrorActionPreference = 'Stop'
if (!$env:GLITCHOS_TEST_STATE) { throw 'Mock ADB requires GLITCHOS_TEST_STATE.' }
$mockFile = $env:GLITCHOS_TEST_STATE
$mock = Get-Content -LiteralPath $mockFile -Raw | ConvertFrom-Json
$nativeArguments = @($args)
if ($nativeArguments[0] -eq '-s') { $nativeArguments = @($nativeArguments | Select-Object -Skip 2) }
$tokens = @($nativeArguments)
if ($nativeArguments[0] -eq 'shell') {
    $tokens = @(); $quoted = $false; $word = New-Object Text.StringBuilder; $command = [string]$nativeArguments[1]
    for ($i = 0; $i -lt $command.Length; $i++) {
        $character = $command[$i]
        if ($character -eq "'") { $quoted = !$quoted }
        elseif (!$quoted -and $character -eq '\') { $i++; [void]$word.Append($command[$i]) }
        elseif (!$quoted -and $character -eq ' ') { $tokens += $word.ToString(); [void]$word.Clear() }
        else { [void]$word.Append($character) }
    }
    if ($quoted) { throw 'Mock received an unterminated shell quote.' }
    $tokens += $word.ToString()
}
$joined = $tokens -join ' '
$mutating = $tokens[0] -eq 'install' -or $joined -match '^(pm (enable|disable|disable-user|default-state|disable-until-used) |cmd package set-home-activity|cmd role clear-role-holders|settings --user 0 (put|delete) |am (start|stopservice) |input )'
$mock.Log += [pscustomobject]@{ Arguments = $tokens; Mutation = [bool]$mutating }
$global:LASTEXITCODE = 0
$answer = ''
switch -Regex ($joined) {
    '^connect ' { $answer = 'connected' ; break }
    '^get-state$' { $answer = $mock.Connection; break }
    '^getprop (.+)$' {
        $answer = switch ($Matches[1]) { 'ro.build.version.sdk' { [string]$mock.Sdk } 'ro.serialno' { 'MOCK-SERIAL-1' } 'ro.product.manufacturer' { 'CHiQ' } 'ro.product.model' { 'Mock TV' } 'ro.build.fingerprint' { 'mock/tv/test' } default { '' } }; break
    }
    '^pm list features$' { $answer = 'feature:android.software.leanback'; break }
    '^am get-current-user$' { $answer = '0'; break }
    '^pm path --user 0 (.+)$' { if ($mock.Packages.PSObject.Properties.Name -contains $Matches[1]) { $answer = 'package:/data/app/' + $Matches[1] + '/base.apk' }; break }
    '^dumpsys package (.+)$' { $answer = '  User 0: installed=true hidden=false enabled=' + $mock.Packages.($Matches[1]); break }
    '^dumpsys webviewupdate$' { $answer = 'Current WebView package (name, version): (' + $mock.WebView + ', 123)'; break }
    '^cmd role get-role-holders' { $answer = $mock.Home; break }
    '^cmd role clear-role-holders' { $mock.Home = $null; break }
    '^cmd package set-home-activity' { $mock.Home = $tokens[-1]; $answer = 'Success'; break }
    '^cmd package resolve-activity' {
        if ($mock.ResolveFailure -or $mock.Packages.'com.google.android.apps.tv.launcherx' -ne 3) { $answer = 'com.google.android.apps.tv.launcherx/.Home' }
        else { $answer = $mock.Home + '/.MainActivity' }; break
    }
    '^settings --user 0 get (\w+) (\w+)$' {
        $key = $Matches[1] + '_' + $Matches[2]
        if ($mock.Settings.PSObject.Properties.Name -contains $key) { $answer = $mock.Settings.$key } else { $answer = 'null' }; break
    }
    '^settings --user 0 put ' { $mock.Settings | Add-Member -NotePropertyName ($tokens[4] + '_' + $tokens[5]) -NotePropertyValue $tokens[6] -Force; break }
    '^settings --user 0 delete ' { $mock.Settings.PSObject.Properties.Remove($tokens[4] + '_' + $tokens[5]); break }
    '^install ' {
        if ($mock.FailInstall) { $answer = 'Failure [INSTALL_FAILED_TEST]'; $global:LASTEXITCODE = 1; break }
        $package = if ($tokens[-1] -match 'repair\.apk$') { 'com.glitchos.airplayrepair' } else { 'com.glitchos.tv' }
        if ($mock.Packages.PSObject.Properties.Name -notcontains $package) { $mock.Packages | Add-Member -NotePropertyName $package -NotePropertyValue 0 }
        $answer = 'Success'; break
    }
    '^pm (enable|disable|disable-user|default-state|disable-until-used) --user 0 (.+)$' {
        $operation = $Matches[1]; $package = $Matches[2]
        if ($operation -eq 'disable-user' -and $package -eq $mock.FailDisable) { $answer = 'Error: simulated package failure'; $global:LASTEXITCODE = 1; break }
        $mock.Packages.$package = switch ($operation) { 'default-state' { 0 } 'enable' { 1 } 'disable' { 2 } 'disable-user' { 3 } 'disable-until-used' { 4 } }
        if ($operation -eq 'disable-user' -and $mock.SabotageBackupDirectory) {
            # Simulate a removed backup drive, preserving fixtures in a renamed test folder.
            $target = (Resolve-Path -LiteralPath $mock.SabotageBackupDirectory).Path
            $expectedParent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($mockFile))
            if ([IO.Path]::GetDirectoryName($target) -ne $expectedParent -or ![IO.Path]::GetFileName($expectedParent).StartsWith('GlitchOSInstallerTests-')) { throw 'Unsafe mock folder target.' }
            Move-Item -LiteralPath $target -Destination ($target + '-unavailable')
            $mock.SabotageBackupDirectory = ''
        }
        $answer = 'Package state changed'; break
    }
    '^am start ' { if ($mock.FailLaunch) { $answer = 'Error type 3' } else { $answer = "Status: ok`nActivity: com.glitchos.tv/.MainActivity" }; break }
    '^am stopservice ' { $answer = 'Service stopped'; break }
    '^input keyevent 3$' { break }
    default { throw "Unexpected mock command: $joined" }
}
$mock | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $mockFile -Encoding UTF8 -WhatIf:$false
if ($null -ne $answer) { Write-Output $answer }
