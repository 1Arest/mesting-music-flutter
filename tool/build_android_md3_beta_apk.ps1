param(
    # Retain this internal native/UI flavor, with the requested public package
    # com.mesting.music. The old .beta installation remains a separate app.
    [string]$VersionName = '1.0.64',
    [ValidateRange(1, 2147483647)][int]$VersionCode = 85,
    [ValidateSet('debug', 'profile', 'release')][string]$Mode = 'release',
    [string]$TargetPlatform = 'android-arm,android-arm64',
    [string]$FlutterSdkRoot = $env:MESTING_BETA_FLUTTER_ROOT,
    # Explicit local diagnostic candidates only. Public builds emit no phase
    # logcat events; the bounded manual report remains available in the app.
    [switch]$TogetherSyncDiagnostics
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$appRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
Push-Location -LiteralPath $appRoot
try {
    # This is a process-local SDK selection. The existing formal build SDK and
    # the user's global PATH remain unchanged. Reproduction uses Flutter 3.41.9.
    $flutterCommand = if ($FlutterSdkRoot) {
        Join-Path $FlutterSdkRoot 'bin\flutter.bat'
    } else {
        (Get-Command flutter -ErrorAction Stop).Source
    }
    $sdk = & $flutterCommand --version --machine | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read Flutter SDK version.' }
    if ([version]$sdk.frameworkVersion -lt [version]'3.41.0') {
        throw 'Beta requires Flutter >= 3.41.0. Use -FlutterSdkRoot with the independent Flutter 3.41.9 SDK.'
    }
    # Compile locally only; this entry never deploys or writes an online manifest.
    # Channel identity is also enforced from Flutter's generated appFlavor.
    # Flutter 3.41 regenerates the native plugin registrant only when its pub
    # phase is enabled. After tests, --no-pub can leave integration_test in a
    # Release registrant even though Gradle excludes that development plugin.
    # Let Flutter generate the correct registrant, but reject dependency drift.
    $lockBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $appRoot 'pubspec.lock')).Hash
    . (Join-Path $PSScriptRoot 'beta_asset_bundle.ps1')
    Clear-BetaAssetStaging -AppRoot $appRoot -Mode $Mode
    & $flutterCommand build apk "--$Mode" --flavor beta `
        "--target-platform=$TargetPlatform" `
        "--build-name=$VersionName" "--build-number=$VersionCode" `
        '--dart-define=USE_CLOUDBASE_AUTH=true' `
        '--dart-define=ENABLE_APP_UPDATE_CHECKS=true' `
        '--dart-define=MESTING_NATIVE_PLAYBACK_LOGGING=false' `
        '--dart-define=MESTING_LOCAL_DIAGNOSTICS=false' `
        "--dart-define=TOGETHER_SYNC_DIAGNOSTICS=$($TogetherSyncDiagnostics.IsPresent.ToString().ToLowerInvariant())" `
        '--dart-define=APP_UPDATE_PACKAGE_NAME=com.mesting.music'
    if ($LASTEXITCODE -ne 0) { throw 'Beta APK build failed.' }
    $lockAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $appRoot 'pubspec.lock')).Hash
    if ($lockAfter -ne $lockBefore) { throw 'Dependency lock changed during the build; review it before packaging.' }
    $source = Join-Path $appRoot "build\app\outputs\flutter-apk\app-beta-$Mode.apk"
    if (!(Test-Path -LiteralPath $source -PathType Leaf)) { throw "Missing APK: $source" }
    Assert-BetaAssetExclusions -AppRoot $appRoot -Apk $source
    Write-Output "Beta APK: $source"
    Get-FileHash -Algorithm SHA256 -LiteralPath $source | Format-List
} finally {
    Pop-Location
}
