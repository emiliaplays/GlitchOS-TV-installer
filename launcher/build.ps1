[CmdletBinding()]
param(
    [string]$AndroidSdkPath,
    [string]$JavaHomePath,
    [string]$BuildToolsVersion = '35.0.0',
    [int]$CompileSdk = 35,
    [string]$AndroidJarPath,
    [string]$BuildToolsPath,
    [string]$KeystorePath,
    [string]$KeyAlias = 'glitchos',
    [int]$VersionCode = 0,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
$localPath = Join-Path $projectPath '.local'
New-Item -ItemType Directory -Force -Path $localPath | Out-Null

if (!$JavaHomePath) { $JavaHomePath = $env:JAVA_HOME }
if (!$JavaHomePath) {
    $javacCommand = Get-Command javac.exe -ErrorAction SilentlyContinue
    if ($javacCommand) { $JavaHomePath = Split-Path (Split-Path $javacCommand.Source -Parent) -Parent }
}
if (!$JavaHomePath) { throw 'Set JAVA_HOME or pass -JavaHomePath pointing to a JDK 17 installation.' }
if (!$AndroidSdkPath) { $AndroidSdkPath = $env:ANDROID_SDK_ROOT }
if (!$AndroidSdkPath) { $AndroidSdkPath = $env:ANDROID_HOME }
if (!$AndroidJarPath -and $AndroidSdkPath) {
    $AndroidJarPath = Join-Path $AndroidSdkPath ('platforms\android-' + $CompileSdk + '\android.jar')
}
if (!$BuildToolsPath -and $AndroidSdkPath) {
    $BuildToolsPath = Join-Path $AndroidSdkPath ('build-tools\' + $BuildToolsVersion)
}
if (!$AndroidJarPath -or !$BuildToolsPath) {
    throw 'Set ANDROID_SDK_ROOT or pass -AndroidSdkPath; alternatively pass both -AndroidJarPath and -BuildToolsPath.'
}

$javaPath = Join-Path $JavaHomePath 'bin\java.exe'
$javacPath = Join-Path $JavaHomePath 'bin\javac.exe'
$jarPath = Join-Path $JavaHomePath 'bin\jar.exe'
$keytoolPath = Join-Path $JavaHomePath 'bin\keytool.exe'
$aaptPath = Join-Path $BuildToolsPath 'aapt2.exe'
$zipalignPath = Join-Path $BuildToolsPath 'zipalign.exe'
$d8JarPath = Join-Path $BuildToolsPath 'lib\d8.jar'
$signerJarPath = Join-Path $BuildToolsPath 'lib\apksigner.jar'
$lambdaStubsPath = Join-Path $BuildToolsPath 'core-lambda-stubs.jar'
foreach ($required in @($javaPath,$javacPath,$jarPath,$keytoolPath,$AndroidJarPath,$aaptPath,$zipalignPath,$d8JarPath,$signerJarPath,$lambdaStubsPath)) {
    if (!(Test-Path -LiteralPath $required -PathType Leaf)) { throw ('Required build tool not found: ' + $required) }
}

[xml]$manifest = Get-Content -LiteralPath (Join-Path $projectPath 'AndroidManifest.xml') -Raw
$androidNamespace = 'http://schemas.android.com/apk/res/android'
$versionName = $manifest.manifest.GetAttribute('versionName', $androidNamespace)
if ($VersionCode -eq 0) { $VersionCode = [int]$manifest.manifest.GetAttribute('versionCode', $androidNamespace) }
if ($VersionCode -lt 1) { throw 'VersionCode must be positive.' }
if (!$OutputPath) { $OutputPath = Join-Path $projectPath ('output\GlitchOS-TV-Edition-' + $versionName + '.apk') }
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
New-Item -ItemType Directory -Force -Path (Split-Path $OutputPath -Parent) | Out-Null

# Use a fresh directory so deleted source files cannot leave stale compiled classes.
$buildPath = Join-Path $localPath ('build\' + [guid]::NewGuid().ToString('N'))
$classesPath = Join-Path $buildPath 'classes'
$generatedPath = Join-Path $buildPath 'generated'
$dexPath = Join-Path $buildPath 'dex'
New-Item -ItemType Directory -Force -Path $classesPath,$generatedPath,$dexPath | Out-Null

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw ('Build command failed: ' + $Executable) }
}

Invoke-Checked $aaptPath @('compile','--dir',(Join-Path $projectPath 'res'),'-o',(Join-Path $buildPath 'resources.zip'))
Invoke-Checked $aaptPath @('link','-o',(Join-Path $buildPath 'unsigned.apk'),'-I',$AndroidJarPath,'--manifest',(Join-Path $projectPath 'AndroidManifest.xml'),'--java',$generatedPath,'--version-code',$VersionCode.ToString(),(Join-Path $buildPath 'resources.zip'))
$sources = @(Get-ChildItem -LiteralPath (Join-Path $projectPath 'src'),$generatedPath -Filter '*.java' -Recurse | ForEach-Object FullName)
Invoke-Checked $javacPath (@('-encoding','UTF-8','-source','8','-target','8','-bootclasspath',($AndroidJarPath + ';' + $lambdaStubsPath),'-d',$classesPath) + $sources)
Invoke-Checked $jarPath @('cf',(Join-Path $buildPath 'classes.jar'),'-C',$classesPath,'.')
Invoke-Checked $javaPath @('-cp',$d8JarPath,'com.android.tools.r8.D8','--lib',$AndroidJarPath,'--min-api','26','--output',$dexPath,(Join-Path $buildPath 'classes.jar'))
Invoke-Checked $jarPath @('uf',(Join-Path $buildPath 'unsigned.apk'),'-C',$dexPath,'classes.dex')
Invoke-Checked $zipalignPath @('-f','-p','4',(Join-Path $buildPath 'unsigned.apk'),(Join-Path $buildPath 'aligned.apk'))

$usesDefaultKey = !$KeystorePath
if ($usesDefaultKey) { $KeystorePath = Join-Path $localPath 'launcher-signing.jks' }
$KeystorePath = [System.IO.Path]::GetFullPath($KeystorePath)
New-Item -ItemType Directory -Force -Path (Split-Path $KeystorePath -Parent) | Out-Null
$passwordPath = Join-Path $localPath 'keystore-password.txt'
$signingPassword = $env:GLITCHOS_KEYSTORE_PASSWORD
if (!$signingPassword -and $usesDefaultKey -and (Test-Path -LiteralPath $passwordPath)) {
    $signingPassword = (Get-Content -LiteralPath $passwordPath -Raw).Trim()
}
if (!$signingPassword -and $usesDefaultKey -and !(Test-Path -LiteralPath $KeystorePath)) {
    $randomBytes = New-Object byte[] 32
    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $random.GetBytes($randomBytes) } finally { $random.Dispose() }
    $signingPassword = [Convert]::ToBase64String($randomBytes)
    Set-Content -LiteralPath $passwordPath -Value $signingPassword -Encoding ASCII
}
if (!$signingPassword) { throw 'Set GLITCHOS_KEYSTORE_PASSWORD to the password for the selected keystore.' }
$previousSigningPassword = $env:GLITCHOS_BUILD_KEYSTORE_PASSWORD
try {
    $env:GLITCHOS_BUILD_KEYSTORE_PASSWORD = $signingPassword
    if (!(Test-Path -LiteralPath $KeystorePath)) {
        Invoke-Checked $keytoolPath @('-genkeypair','-keystore',$KeystorePath,'-alias',$KeyAlias,'-storepass:env','GLITCHOS_BUILD_KEYSTORE_PASSWORD','-keypass:env','GLITCHOS_BUILD_KEYSTORE_PASSWORD','-dname','CN=GlitchOS TV Edition Local Build','-keyalg','RSA','-keysize','2048','-validity','10000')
    }
    Invoke-Checked $javaPath @('-jar',$signerJarPath,'sign','--ks',$KeystorePath,'--ks-key-alias',$KeyAlias,'--ks-pass','env:GLITCHOS_BUILD_KEYSTORE_PASSWORD','--key-pass','env:GLITCHOS_BUILD_KEYSTORE_PASSWORD','--out',$OutputPath,(Join-Path $buildPath 'aligned.apk'))
    Invoke-Checked $javaPath @('-jar',$signerJarPath,'verify','--verbose',$OutputPath)
} finally {
    $env:GLITCHOS_BUILD_KEYSTORE_PASSWORD = $previousSigningPassword
    $signingPassword = $null
}
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
Write-Output ('Built: ' + $OutputPath)
