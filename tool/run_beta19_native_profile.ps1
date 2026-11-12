param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$Device = 'eb293ac2',
    [string]$Target = 'integration_test/beta19_native_suite_test.dart',
    [string]$FlutterSdkRoot = $env:MESTING_BETA_FLUTTER_ROOT,
    [string]$AndroidSdkRoot = "$env:LOCALAPPDATA/Android/Sdk"
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Profile only an externally prepared copy whose beta applicationIdSuffix is
# .beta.benchmark. Never test against the user's installed production identity.
# Flutter drive's default stop() UNINSTALLS its application; keeping it running
# is mandatory even for the isolated package. This runner never clears data.
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$aapt = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkRoot 'build-tools') -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt.exe' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (!$aapt) { throw 'Android Build Tools aapt.exe is required.' }
$badging = (& $aapt dump badging $apkPath) -join "`n"
if ($LASTEXITCODE -ne 0 -or
    $badging -notmatch "package: name='com.mesting.music.beta.benchmark'") {
    throw 'Refusing native profiling: APK must use com.mesting.music.beta.benchmark.'
}
$flutter = if ($FlutterSdkRoot) {
    Join-Path $FlutterSdkRoot 'bin/flutter.bat'
} else {
    (Get-Command flutter -ErrorAction Stop).Source
}
$adb = Join-Path $AndroidSdkRoot 'platform-tools/adb.exe'
Push-Location -LiteralPath $projectPath
try {
    & $adb -s $Device install -r $apkPath
    if ($LASTEXITCODE -ne 0) { throw 'ADB refused replacement install; no uninstall fallback is allowed.' }
    & $flutter drive --profile --flavor beta -d $Device `
        --driver=test_driver/integration_test.dart "--target=$Target" `
        "--use-application-binary=$apkPath" --host-vmservice-port=8181 `
        --keep-app-running --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Native profile suite failed; inspect its result before making claims.' }
} finally {
    Pop-Location
}
