param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^http://[^/]+(?:/.*)?$')]
    [string]$AuthApiBaseUrl,
    [ValidatePattern('^[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$VersionName = '1.0.38',
    [ValidateRange(1, 2147483647)]
    [int]$VersionCode = 40,
    [string]$EnvironmentId = 'mesting-d5gm7tuhxacddccfb',
    [string]$HostingDomain = 'mesting-d5gm7tuhxacddccfb-1331507389.tcloudbaseapp.com'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$manifestUrl = "https://$HostingDomain/releases/android/java-mysql-test/latest.json"
$packageName = 'com.mesting.music.javatest'
$normalizedApiUrl = $AuthApiBaseUrl.TrimEnd('/')

Push-Location -LiteralPath $appRoot
try {
    # This channel is deliberately a Debug-only HTTP integration test. It is
    # isolated by package id and must never be used for the stable Release path.
    & flutter build apk `
        --debug `
        --flavor 'javaMysqlTest' `
        --target-platform 'android-arm,android-arm64' `
        "--build-name=$VersionName" `
        "--build-number=$VersionCode" `
        "--dart-define=AUTH_API_BASE_URL=$normalizedApiUrl" `
        '--dart-define=ENABLE_APP_UPDATE_CHECKS=true' `
        "--dart-define=APP_UPDATE_MANIFEST_URL=$manifestUrl" `
        "--dart-define=APP_UPDATE_PACKAGE_NAME=$packageName"
    if ($LASTEXITCODE -ne 0) {
        throw 'Java/MySQL test APK build failed.'
    }

    $sourceApk = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-javaMysqlTest-debug.apk'
    if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
        throw "Java/MySQL test APK was not found: $sourceApk"
    }

    $archiveDirectory = Join-Path $appRoot 'build\java_mysql_test_apk'
    [IO.Directory]::CreateDirectory($archiveDirectory) | Out-Null
    $outputApk = Join-Path $archiveDirectory "Mesting-Music-Java-MySQL-Test-v$VersionName-build$VersionCode.apk"
    Copy-Item -LiteralPath $sourceApk -Destination $outputApk -Force

    Write-Output "Built Java/MySQL test APK: $outputApk"
    Write-Output "Package: $packageName"
    Write-Output "Update manifest: $manifestUrl"
    Write-Output "API base URL: $normalizedApiUrl"
} finally {
    Pop-Location
}
