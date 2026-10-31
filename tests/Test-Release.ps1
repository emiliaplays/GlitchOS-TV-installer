[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$version = Get-Content -LiteralPath (Join-Path $repo 'version.json') -Raw | ConvertFrom-Json
$apk = Join-Path $repo "releases/GlitchOS-TV-Edition-$($version.launcher.versionName).apk"
$actual = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $version.launcher.apkSha256) { throw 'Launcher release hash differs from version.json.' }
$sums = Get-Content -LiteralPath (Join-Path $repo 'releases/SHA256SUMS') -Raw
if ($sums -notmatch [regex]::Escape($actual)) { throw 'Launcher release hash missing from SHA256SUMS.' }
[xml]$manifest = Get-Content -LiteralPath (Join-Path $repo 'launcher/AndroidManifest.xml') -Raw
$android = 'http://schemas.android.com/apk/res/android'
if ($manifest.manifest.package -ne $version.launcher.package -or
    $manifest.manifest.GetAttribute('versionName', $android) -ne $version.launcher.versionName -or
    [int]$manifest.manifest.GetAttribute('versionCode', $android) -ne $version.launcher.versionCode) {
    throw 'Launcher source manifest does not match release metadata.'
}
$parseErrors = @()
Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -Recurse | Where-Object {
    $_.FullName -notmatch '[\\/](artifacts|backups|\.?local|tools|build|output)[\\/]'
} | ForEach-Object {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    $parseErrors += $errors
}
if ($parseErrors.Count) { $parseErrors | ForEach-Object { Write-Error $_.ToString() -ErrorAction Continue }; throw 'PowerShell syntax validation failed.' }
Write-Host 'PASS: release checksum, source version and PowerShell syntax.'
