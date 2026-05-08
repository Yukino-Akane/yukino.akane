param(
    [Parameter(Mandatory=$true)][string]$SourceRoot,
    [string]$SourcePackageFullName = "",
    [string]$SourceVersion = "",
    [string]$ManifestPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-YukinoFileSha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Add-YukinoArtifact([System.Collections.Generic.List[object]]$Artifacts, [string]$Id, [string]$Root, [string]$RelativePath) {
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        return
    }

    $item = Get-Item -LiteralPath $path
    $Artifacts.Add([ordered]@{
        id = $Id
        path = $RelativePath.Replace("\", "/")
        sha256 = Get-YukinoFileSha256 $item.FullName
        bytes = $item.Length
    }) | Out-Null
}

function ConvertTo-YukinoRelativePath([string]$Root, [string]$Path) {
    $normalizedRoot = [IO.Path]::GetFullPath($Root).TrimEnd([char[]]@('\', '/'))
    $normalizedPath = [IO.Path]::GetFullPath($Path)
    if (-not $normalizedPath.StartsWith($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path is outside root. Root=$normalizedRoot Path=$normalizedPath"
    }
    return $normalizedPath.Substring($normalizedRoot.Length).TrimStart([char[]]@('\', '/')).Replace("\", "/")
}

$resolvedRoot = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
if (-not $ManifestPath) {
    $ManifestPath = Join-Path $resolvedRoot "yukino-source-manifest.json"
}

$artifacts = New-Object System.Collections.Generic.List[object]
$keyIds = @{
    "AppxManifest.xml" = "source.appxManifest"
    "app/Codex.exe" = "source.codexExe"
    "app/Yukino.exe" = "source.yukinoExe"
    "app/resources/app.asar" = "source.appAsar"
    "AppxBlockMap.xml" = "source.blockMap"
    "AppxSignature.p7x" = "source.signature"
}
Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -File | Sort-Object FullName | ForEach-Object {
    $relative = ConvertTo-YukinoRelativePath $resolvedRoot $_.FullName
    $id = if ($keyIds.ContainsKey($relative)) { $keyIds[$relative] } else { "source.file" }
    $artifacts.Add([ordered]@{
        id = $id
        path = $relative
        sha256 = Get-YukinoFileSha256 $_.FullName
        bytes = $_.Length
    }) | Out-Null
}

$manifest = [ordered]@{
    sourcePackageFullName = $SourcePackageFullName
    sourceVersion = $SourceVersion
    sourceRoot = $resolvedRoot
    generatedAt = [DateTime]::UtcNow.ToString("o")
    artifacts = $artifacts.ToArray()
}

$manifestDir = Split-Path -Parent $ManifestPath
if (-not (Test-Path -LiteralPath $manifestDir)) {
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
}
[IO.File]::WriteAllText($ManifestPath, ($manifest | ConvertTo-Json -Depth 8) + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Wrote Yukino source manifest: $ManifestPath"
