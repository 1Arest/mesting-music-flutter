param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$Output,
    [Parameter(Mandatory = $true)][string]$KeyStore,
    [string]$KeyAlias = 'androiddebugkey',
    [string]$StorePassEnv = 'MESTING_SIGN_STORE_PASS',
    [string]$KeyPassEnv = 'MESTING_SIGN_KEY_PASS',
    [string]$AndroidSdkRoot = "$env:LOCALAPPDATA/Android/Sdk",
    [string]$ExpectedCertificateSha256 = '8ce2203ad821ad8d38576f9ae86350d98254ac05f2cb974e773c1973b22e0333'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# Signing credentials are supplied by the caller's environment and never
# written to source, command arguments, logs or the portable source archive.
if (![Environment]::GetEnvironmentVariable($StorePassEnv) -or
    ![Environment]::GetEnvironmentVariable($KeyPassEnv)) {
    throw 'Set the signing password environment variables before signing.'
}
if (Test-Path -LiteralPath $Output) { throw 'Refusing to overwrite a signed/frozen APK.' }
$inputApk = (Resolve-Path -LiteralPath $Apk).Path
$keyFile = (Resolve-Path -LiteralPath $KeyStore).Path
$signer = Get-ChildItem -LiteralPath (Join-Path $AndroidSdkRoot 'build-tools') -Directory |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'apksigner.bat' } |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
if (!$signer) { throw 'Android Build Tools apksigner is required.' }
& $signer sign --ks $keyFile --ks-key-alias $KeyAlias `
    --ks-pass "env:$StorePassEnv" --key-pass "env:$KeyPassEnv" `
    --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true `
    --v4-signing-enabled false `
    --out $Output $inputApk
if ($LASTEXITCODE -ne 0) { throw 'APK signing failed.' }
$report = (& $signer verify --verbose --print-certs $Output) -join "`n"
if ($LASTEXITCODE -ne 0 -or
    $report -notmatch 'certificate SHA-256 digest: ([0-9a-fA-F]{64})') {
    throw 'The signed APK failed certificate verification.'
}
$certificate = $Matches[1].ToLowerInvariant()
if ($certificate -ne $ExpectedCertificateSha256.ToLowerInvariant()) {
    throw 'Certificate differs from the retained upgrade identity. Do not install this APK.'
}
Write-Output "Verified upgrade certificate: $certificate"
# Windows PowerShell launched from a portable PowerShell may inherit a module
# path without Microsoft.PowerShell.Utility. Hash with .NET directly so an
# already successful signature is not reported as a failure by that host.
$musicHash = [Security.Cryptography.SHA256]::Create()
$musicStream = [IO.File]::OpenRead((Resolve-Path -LiteralPath $Output).Path)
try {
    [pscustomobject]@{
        Algorithm = 'SHA256'
        Hash = [BitConverter]::ToString($musicHash.ComputeHash($musicStream)).Replace('-', '').ToLowerInvariant()
        Path = (Resolve-Path -LiteralPath $Output).Path
    }
} finally {
    $musicStream.Dispose()
    $musicHash.Dispose()
}
