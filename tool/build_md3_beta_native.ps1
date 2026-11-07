param(
    [Parameter(Mandatory=$true)][string]$AndroidNdkRoot,
    [string]$CargoCommand = 'cargo',
    [string]$TargetDirectory = '',
    [string[]]$Targets = @('aarch64-linux-android','armv7-linux-androideabi','x86_64-linux-android'),
    [switch]$NoCopy
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$sourceRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$nativeSource = Join-Path $sourceRoot 'third_party/md3music/rust'
$ndkBin = Join-Path $AndroidNdkRoot 'toolchains/llvm/prebuilt/windows-x86_64/bin'
if (!(Test-Path -LiteralPath $ndkBin -PathType Container)) { throw 'Windows NDK LLVM toolchain is missing.' }
if (!$TargetDirectory) { $TargetDirectory = Join-Path $sourceRoot 'build/md3-native' }
# Only this process's environment is changed. Install the corresponding Rust
# targets beforehand; no global SDK/path/NDK configuration is changed here.
$env:CARGO_TARGET_DIR = $TargetDirectory
$matrix = @{
    'aarch64-linux-android' = @('arm64-v8a','aarch64-linux-android21-clang.cmd')
    'armv7-linux-androideabi' = @('armeabi-v7a','armv7a-linux-androideabi21-clang.cmd')
    'x86_64-linux-android' = @('x86_64','x86_64-linux-android21-clang.cmd')
}
Push-Location -LiteralPath $nativeSource
try {
    foreach ($target in $Targets) {
        if (!$matrix.ContainsKey($target)) { throw "Unsupported native target: $target" }
        $parts = $matrix[$target]
        $suffix = $target.Replace('-','_')
        [Environment]::SetEnvironmentVariable("CC_$suffix", (Join-Path $ndkBin $parts[1]), 'Process')
        [Environment]::SetEnvironmentVariable("AR_$suffix", (Join-Path $ndkBin 'llvm-ar.exe'), 'Process')
        [Environment]::SetEnvironmentVariable("CARGO_TARGET_$($suffix.ToUpperInvariant())_LINKER", (Join-Path $ndkBin $parts[1]), 'Process')
        & $CargoCommand build --locked --release --target $target
        if ($LASTEXITCODE -ne 0) { throw "Native build failed: $target" }
        $library = Join-Path $TargetDirectory "$target/release/libkugou_server.so"
        & (Join-Path $ndkBin 'llvm-readelf.exe') --dyn-syms $library | Select-String -Pattern ' start_server$| stop_server$| get_server_port$| is_server_running$'
        if ($LASTEXITCODE -ne 0) { throw 'Native ELF inspection failed.' }
        if (!$NoCopy) {
            $destination = Join-Path $sourceRoot "android/app/src/beta/jniLibs/$($parts[0])/libkugou_server.so"
            Copy-Item -LiteralPath $library -Destination $destination -Force
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $library).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $destination).Hash) { throw 'Native copy verification failed.' }
        }
        Get-FileHash -Algorithm SHA256 -LiteralPath $library
    }
} finally { Pop-Location }
