param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('JAVA_MYSQL_TEST_ONLY')]
    [string]$ChannelAcknowledgement,
    [Parameter(Mandatory = $true)]
    [string[]]$ReleaseNotes,
    [Parameter(Mandatory = $true)]
    [string]$InputApkPath,
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
$normalizedNotes = @(
    $ReleaseNotes |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }
)
if ($normalizedNotes.Count -eq 0) {
    throw 'At least one non-empty release note is required.'
}

$apkPath = (Resolve-Path -LiteralPath $InputApkPath).Path
if (-not (Test-Path -LiteralPath $apkPath -PathType Leaf)) {
    throw "Java/MySQL test APK was not found: $apkPath"
}

$apk = Get-Item -LiteralPath $apkPath
$sha256 = (Get-FileHash -LiteralPath $apk.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$remoteDirectory = 'releases/android/java-mysql-test'
$fileName = "mesting-music-java-mysql-test-$VersionName-$VersionCode.apk"
$remoteApkPath = "$remoteDirectory/$fileName"
$apkUrl = "https://$HostingDomain/$remoteApkPath"
$manifestDirectory = Join-Path $appRoot 'build\app_update\java_mysql_test'
[IO.Directory]::CreateDirectory($manifestDirectory) | Out-Null
$manifestPath = Join-Path $manifestDirectory 'latest.json'

$requiredWarnings = @(
    '测试通道：不会向正式稳定版用户推送。',
    '当前使用 HTTP Java/MySQL 测试接口；请勿在不可信网络中用于真实账号。',
    '头像跨设备访问、旧头像迁移和数据容灾尚未完成生产化验证。',
    '若发现登录、社交、聊天或一起听异常，请停止测试并反馈。'
)
$manifest = [ordered]@{
    packageName = 'com.mesting.music.javatest'
    versionName = $VersionName
    versionCode = $VersionCode
    minimumVersionCode = 1
    mandatory = $false
    title = 'Java + MySQL 测试版'
    releaseNotes = @($requiredWarnings + $normalizedNotes)
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

# The stable feed is intentionally never referenced by this script. Upload
# immutable artifacts first, then this channel's latest.json as the final step.
& tcb hosting deploy $apk.FullName $remoteApkPath -e $EnvironmentId --retry-count 3 --json
if ($LASTEXITCODE -ne 0) { throw 'Test APK upload to CloudBase static hosting failed.' }

$versionManifestPath = "$remoteDirectory/manifests/$VersionCode.json"
& tcb hosting deploy $manifestPath $versionManifestPath -e $EnvironmentId --retry-count 3 --json
if ($LASTEXITCODE -ne 0) { throw 'Test archived manifest upload failed.' }

& tcb hosting deploy $manifestPath "$remoteDirectory/latest.json" -e $EnvironmentId --retry-count 3 --json
if ($LASTEXITCODE -ne 0) { throw 'Test latest manifest publish failed.' }

Write-Output "Published Java/MySQL test $VersionName ($VersionCode)"
Write-Output "APK: $apkUrl"
Write-Output "Manifest: https://$HostingDomain/$remoteDirectory/latest.json"
Write-Output "SHA-256: $sha256"
