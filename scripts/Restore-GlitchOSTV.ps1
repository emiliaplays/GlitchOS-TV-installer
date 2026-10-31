[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)][string]$Device,
    [string]$AdbPath = 'adb',
    [Parameter(Mandatory = $true)][string]$StateFile
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'GlitchOS.Common.ps1')
$StateFile = (Resolve-Path -LiteralPath $StateFile).Path
$state = Get-Content -LiteralPath $StateFile -Raw | ConvertFrom-Json
if ($state.SchemaVersion -ne 1) { throw 'Unsupported backup format.' }
Initialize-GlitchAdb $Device $AdbPath
$identity = Get-GlitchDeviceContext
if ($state.Identity.AndroidId) {
    if ($identity.AndroidId -ne $state.Identity.AndroidId) { throw 'This backup belongs to a different TV (Android ID mismatch). No settings changed.' }
} elseif (!$state.Identity.Serial -or $identity.Serial -ne $state.Identity.Serial) {
    throw 'This backup belongs to a different TV (serial mismatch). No settings changed.'
}
if ($state.Identity.Serial -and $identity.Serial -and $state.Identity.Serial -ne $identity.Serial) { throw 'TV serial does not match the backup. No settings changed.' }
Write-Output "Restore configuration captured $($state.CreatedUtc) for $($state.Identity.Model). Installed APKs remain; this does not restore older app versions or app data."
if (!$PSCmdlet.ShouldProcess($Device, "Restore HOME, selected package states, and changed settings from $StateFile")) { return }
Restore-GlitchConfiguration $state $StateFile
Write-Output 'Previous configuration restored. GlitchOS remains installed as an app.'
