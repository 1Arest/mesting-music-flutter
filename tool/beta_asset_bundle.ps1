# Flutter 3.41 updates declared files but can leave removed assets in generated
# bundle directories. AGP can then package those orphan files even though they
# are absent from AssetManifest.bin. Only this flavor's generated staging may
# be cleared; source assets and previously delivered APKs are never touched.
function Clear-BetaAssetStaging {
    param([Parameter(Mandatory)][string]$AppRoot,
          [ValidateSet('debug', 'profile', 'release')][string]$Mode)
    $intermediates = [IO.Path]::GetFullPath((Join-Path $AppRoot 'build/app/intermediates'))
    if (!(Test-Path -LiteralPath $intermediates -PathType Container)) { return }
    $variant = 'beta' + $Mode.Substring(0, 1).ToUpperInvariant() + $Mode.Substring(1)
    $variantPattern = '[\\/]' + [regex]::Escape($variant) + '[\\/]'
    $targets = @(Get-ChildItem -LiteralPath $intermediates -Recurse -Directory -Filter 'flutter_assets' |
        Where-Object { $_.FullName -match $variantPattern })
    foreach ($directory in $targets) {
        $absolute = [IO.Path]::GetFullPath($directory.FullName)
        $inside = $absolute.StartsWith($intermediates + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)
        if (!$inside -or $directory.Name -ne 'flutter_assets' -or
            ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Unsafe generated asset staging path: $absolute"
        }
        Remove-Item -LiteralPath $absolute -Recurse -Force
    }
    Write-Output "Cleared $($targets.Count) generated $variant asset staging directories."
}

function Assert-BetaAssetExclusions {
    param([Parameter(Mandatory)][string]$AppRoot,
          [Parameter(Mandatory)][string]$Apk)
    # Manifest entries deliberately use a simple path + inline-flavors form.
    # Derive the exclusion list from it instead of maintaining a second list.
    $lines = Get-Content -LiteralPath (Join-Path $AppRoot 'pubspec.yaml')
    $excluded = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        if ($lines[$i] -match '^\s+- path: (assets/.+)$') {
            $relative = $Matches[1].Trim()
            if ($lines[$i + 1] -match '^\s+flavors: \[(.+)\]' -and
                $Matches[1] -notmatch '\bbeta\b') {
                $source = Join-Path $AppRoot $relative
                if (Test-Path -LiteralPath $source -PathType Container) {
                    foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
                        $excluded.Add([IO.Path]::GetRelativePath($AppRoot, $file.FullName).Replace('\', '/'))
                    }
                } else { $excluded.Add($relative) }
            }
        }
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($Apk)
    try {
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($entry in $archive.Entries) { $null = $names.Add($entry.FullName) }
        foreach ($relative in $excluded) {
            if ($names.Contains('assets/flutter_assets/' + $relative)) {
                throw "Retired Beta asset still packaged: $relative"
            }
        }
        Write-Output "Verified $($excluded.Count) formal-only assets are absent from the Beta APK."
    } finally { $archive.Dispose() }
}
