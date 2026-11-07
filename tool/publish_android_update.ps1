param(
    [Parameter(Mandatory = $true)]
    [string[]]$ReleaseNotes,
    [string]$Title = 'Mesting Music update',
    [int]$MinimumVersionCode = 1,
    [switch]$Mandatory,
    [switch]$SkipBuild,
    [string]$InputApkPath = '',
    [string]$EnvironmentId = 'mesting-d5gm7tuhxacddccfb',
    [string]$HostingDomain = 'mesting-d5gm7tuhxacddccfb-1331507389.tcloudbaseapp.com'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$appRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$pubspecPath = Join-Path $appRoot 'pubspec.yaml'
$versionMatch = Select-String `
    -LiteralPath $pubspecPath `
    -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$'

if ($null -eq $versionMatch -or $versionMatch.Matches.Count -ne 1) {
    throw 'pubspec.yaml must contain exactly one version: x.y.z+build entry.'
}

$versionName = $versionMatch.Matches[0].Groups[1].Value
$versionCode = [int]$versionMatch.Matches[0].Groups[2].Value
if ($MinimumVersionCode -gt $versionCode) {
    throw 'MinimumVersionCode cannot exceed the release versionCode.'
}

$normalizedNotes = @(
    $ReleaseNotes |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
if ($normalizedNotes.Count -eq 0) {
    throw 'At least one non-empty release note is required.'
}

Push-Location -LiteralPath $appRoot
try {
    if (-not $SkipBuild) {
        # Public Android releases target physical ARM phones only. Keep both
        # current 64-bit devices and the 32-bit ARM compatibility fallback,
        # while excluding emulator-focused x86_64 native libraries.
        & flutter build apk `
            --release `
            --flavor 'stable' `
            --target-platform 'android-arm,android-arm64'
        if ($LASTEXITCODE -ne 0) {
            throw 'Release APK build failed.'
        }
    }

    $apkPath = Join-Path $appRoot 'build\app\outputs\flutter-apk\app-stable-release.apk'
    if ($SkipBuild -and $InputApkPath.Trim()) {
        $apkPath = (Resolve-Path -LiteralPath $InputApkPath).Path
    }
    if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
        throw "Release APK was not found: $apkPath"
    }

    $apk = Get-Item -LiteralPath $apkPath
    $sha256 = (
        Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    $fileName = "mesting-music-$versionName-$versionCode.apk"
    $remoteDirectory = 'releases/android'
    $remoteApkPath = "$remoteDirectory/$fileName"
    $apkUrl = "https://$HostingDomain/$remoteApkPath"
    $manifestDirectory = Join-Path $appRoot 'build\app_update'
    [IO.Directory]::CreateDirectory($manifestDirectory) | Out-Null
    $manifestPath = Join-Path $manifestDirectory 'latest.json'

    $manifest = [ordered]@{
        packageName = 'com.mesting.music'
        versionName = $versionName
        versionCode = $versionCode
        minimumVersionCode = $MinimumVersionCode
        mandatory = [bool]$Mandatory
        title = $Title
        releaseNotes = $normalizedNotes
        apkUrl = $apkUrl
        sha256 = $sha256
        sizeBytes = [long]$apk.Length
        publishedAt = [DateTimeOffset]::Now.ToString('o')
    }
    $json = $manifest | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText(
        $manifestPath,
        $json + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )

    # Upload immutable files first. Publish latest.json only after the APK exists.
    & tcb hosting deploy `
        $apk.FullName `
        $remoteApkPath `
        -e $EnvironmentId `
        --retry-count 3 `
        --json
    if ($LASTEXITCODE -ne 0) {
        throw 'APK upload to CloudBase static hosting failed.'
    }

    $versionManifestPath = "$remoteDirectory/manifests/$versionCode.json"
    & tcb hosting deploy `
        $manifestPath `
        $versionManifestPath `
        -e $EnvironmentId `
        --retry-count 3 `
        --json
    if ($LASTEXITCODE -ne 0) {
        throw 'Archived manifest upload failed.'
    }

    & tcb hosting deploy `
        $manifestPath `
        "$remoteDirectory/latest.json" `
        -e $EnvironmentId `
        --retry-count 3 `
        --json
    if ($LASTEXITCODE -ne 0) {
        throw 'latest.json publish failed.'
    }

    Write-Output "Published Mesting Music $versionName ($versionCode)"
    Write-Output "APK: $apkUrl"
    Write-Output "Manifest: https://$HostingDomain/$remoteDirectory/latest.json"
    Write-Output "SHA-256: $sha256"
} finally {
    Pop-Location
}
