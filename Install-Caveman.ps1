#Requires -Version 5.1
<#
.SYNOPSIS
    Download latest caveman release, unzip, install skills.

.DESCRIPTION
    1. Query GitHub API for latest release of JuliusBrussee/caveman.
    2. Download the source zip (zipball).
    3. Extract archive to a temp folder.
    4. Copy contents of the release `skills` folder into the destination path (default: $HOME\.claude\skills - the single skills store).
#>

[CmdletBinding()]
param(
    [string[]]$DstPath = @((Join-Path $HOME '.claude/skills'))
)

$ErrorActionPreference = 'Stop'

# Ensure every destination ends in a 'skills' folder.
$DstPath = $DstPath | ForEach-Object {
    if ((Split-Path -Path $_ -Leaf) -ne 'skills') { Join-Path $_ 'skills' } else { $_ }
}

# GitHub requires TLS 1.2 for API/download on older PowerShell.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repo = 'JuliusBrussee/caveman'
$apiUrl = "https://api.github.com/repos/$repo/releases/latest"
$headers = @{ 'User-Agent' = 'caveman-installer'; 'Accept' = 'application/vnd.github+json' }

# Resolve the latest release and its source zip URL.
Write-Host "Query latest release of $repo"
$release = Invoke-RestMethod -Uri $apiUrl -Headers $headers
$tag = $release.tag_name
if (-not $tag) { throw "Could not determine the release tag for $repo." }
$zipUrl = $release.zipball_url
if ([string]::IsNullOrWhiteSpace($zipUrl)) {
    throw "Could not determine the release zip URL for $repo."
}
Write-Host "Latest release: $tag"

# Download and extract into a fresh temp folder.
$tempPath = Join-Path ([IO.Path]::GetTempPath()) ("caveman_" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
$zipPath = Join-Path $tempPath 'caveman.zip'
$extractDir = Join-Path $tempPath 'extracted-archive'

try {
    Write-Host "Downloading $zipUrl"
    Invoke-WebRequest -Uri $zipUrl -Headers $headers -OutFile $zipPath

    Write-Host "Extracting archive"
    Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

    # GitHub zipball wraps everything in a single top-level folder (owner-repo-sha).
    $root = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
    if (-not $root) { throw "Extracted archive does not contain the expected top-level folder." }
    Write-Host "Archive root: $($root.Name)"

    # Copy skills into each destination path.
    $skillsPath = Join-Path $root.FullName 'skills'
    if (-not (Test-Path $skillsPath)) { throw "'skills' folder not found." }
    $skillsGlob = Join-Path $skillsPath '*'
    foreach ($dst in $DstPath) {
        New-Item -ItemType Directory -Path $dst -Force | Out-Null
        Write-Host "Copy skills to $dst"
        Copy-Item -Path $skillsGlob -Destination $dst -Recurse -Force
    }

    Write-Host "Done. Installed caveman $tag."
}
finally {
    if (Test-Path $tempPath) { Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue }
}
