<#
.SYNOPSIS
    Refresh the Anthropic-authored skills vendored in .github/skills from the upstream
    repo (anthropics/skills) so they never go stale.

.DESCRIPTION
    Which skills? Whichever of OUR .github/skills/<name> folders also exist upstream at
    skills/<name>. That is auto-detected on every run, so a skill added to either side is
    picked up with no list to maintain here.

    Our own skills (bitbucket-*, review-*, sple-standards, ...) have no upstream
    counterpart and are never touched.

    The resolved upstream commit is written to .github/skills/.anthropic-skills.lock.json
    so you can see exactly which version is vendored, and re-runs are a no-op when nothing
    changed.

    Vendored folders are REPLACED wholesale - do not hand-edit them; upstream wins.
    Everything is under git, so review the diff before committing.

    Network failures are non-fatal: the vendored copies are kept and the script exits 0,
    so being offline never blocks an install.

.PARAMETER Ref
    Upstream branch, tag or commit to pin to. Defaults to 'main'.

.PARAMETER DryRun
    Show what would change. Writes nothing.

.PARAMETER Force
    Re-copy even when the lock file already matches the upstream commit.

.PARAMETER List
    Show vendored vs. available-upstream skills, then stop.
#>
[CmdletBinding()]
param(
    [string]$Ref = 'main',
    [switch]$DryRun,
    [switch]$Force,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$upstreamRepo   = 'anthropics/skills'
$upstreamPrefix = 'skills'          # where the skills live inside that repo
$root       = $PSScriptRoot
$skillsDir  = Join-Path $root '.github\skills'
$lockPath   = Join-Path $skillsDir '.anthropic-skills.lock.json'
$api        = "https://api.github.com/repos/$upstreamRepo"
$headers    = @{ 'User-Agent' = 'ai-autopilot'; 'Accept' = 'application/vnd.github+json' }

if (-not (Test-Path $skillsDir)) {
    Write-Error "No $skillsDir - run from the repo root."
    exit 1
}

function Test-FolderDiffers {
    # Compares by relative path + content hash, so an identical folder is left alone
    # (keeps the git diff clean when upstream did not actually change this skill).
    param([string]$Left, [string]$Right)

    $map = {
        param($base)
        Get-ChildItem -LiteralPath $base -Recurse -File -Force | ForEach-Object {
            [pscustomobject]@{
                Rel  = $_.FullName.Substring($base.Length).TrimStart('\', '/')
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } | Sort-Object Rel
    }
    $l = @(& $map $Left)
    $r = @(& $map $Right)
    if ($l.Count -ne $r.Count) { return $true }
    for ($i = 0; $i -lt $l.Count; $i++) {
        if ($l[$i].Rel -ne $r[$i].Rel -or $l[$i].Hash -ne $r[$i].Hash) { return $true }
    }
    return $false
}

# --- Resolve the upstream commit ------------------------------------------------
$commit = $null
try { $commit = (Invoke-RestMethod -Uri "$api/commits/$Ref" -Headers $headers).sha } catch { }
if (-not $commit) {
    Write-Warning "Could not reach $upstreamRepo ($Ref) - keeping the vendored copies as they are."
    exit 0
}
$short = $commit.Substring(0, 7)

$locked = $null
if (Test-Path -LiteralPath $lockPath) {
    try { $locked = (Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json).commit } catch { }
}
if ($locked -eq $commit -and -not $Force -and -not $List) {
    Write-Host "[OK] Anthropic skills already at $upstreamRepo@$short - nothing to do."
    exit 0
}

# --- Which of our skills exist upstream? ----------------------------------------
$upstreamNames = $null
try {
    # Assign before piping: Invoke-RestMethod used inline in a pipeline hands the whole
    # JSON array downstream as a single Object[] instead of enumerating it, and the
    # filter below then silently yields nothing.
    $contents = Invoke-RestMethod -Uri "$api/contents/$upstreamPrefix`?ref=$Ref" -Headers $headers
    $upstreamNames = @($contents | Where-Object { $_.type -eq 'dir' } | Select-Object -ExpandProperty name)
} catch { }
if (-not $upstreamNames -or $upstreamNames.Count -eq 0) {
    Write-Warning "Could not list $upstreamRepo/$upstreamPrefix - keeping the vendored copies as they are."
    exit 0
}

$localNames  = @(Get-ChildItem -Path $skillsDir -Directory | Select-Object -ExpandProperty Name)
$managed     = @($localNames    | Where-Object { $upstreamNames -contains $_ } | Sort-Object)
$newUpstream = @($upstreamNames | Where-Object { $localNames    -notcontains $_ } | Sort-Object)

if ($List) {
    Write-Host "Upstream : $upstreamRepo@$short ($Ref)"
    Write-Host "Vendored : $($managed.Count) skill(s) tracked from upstream"
    $managed | ForEach-Object { Write-Host "  - $_" }
    if ($newUpstream.Count -gt 0) {
        Write-Host "Available upstream but not vendored here (add the folder to start tracking it):"
        $newUpstream | ForEach-Object { Write-Host "  + $_" }
    }
    exit 0
}

if ($managed.Count -eq 0) {
    Write-Host "[INFO] No vendored skills match an upstream skill - nothing to update."
    exit 0
}

Write-Host "Updating Anthropic skills from $upstreamRepo@$short ($Ref)..."

# --- Download once, copy the folders we track -----------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("anthropic-skills-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $zip = Join-Path $tmp 'src.zip'
    try { Invoke-WebRequest -Uri "$api/zipball/$commit" -Headers $headers -OutFile $zip -UseBasicParsing }
    catch { Write-Warning "Download failed - keeping the vendored copies as they are."; exit 0 }

    $ext = Join-Path $tmp 'x'
    New-Item -ItemType Directory -Path $ext -Force | Out-Null
    try { Expand-Archive -LiteralPath $zip -DestinationPath $ext -Force }
    catch { Write-Warning "Extract failed - keeping the vendored copies."; exit 0 }

    $srcRoot = Get-ChildItem -Path $ext -Directory | Select-Object -First 1
    if (-not $srcRoot) { Write-Warning "Unexpected archive layout - keeping the vendored copies."; exit 0 }

    $changed = 0; $skipped = 0
    foreach ($name in $managed) {
        $src = Join-Path $srcRoot.FullName (Join-Path $upstreamPrefix $name)
        $dst = Join-Path $skillsDir $name
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "  [skip] $name - not in the archive"; $skipped++; continue
        }
        if ((Test-Path -LiteralPath $dst) -and -not (Test-FolderDiffers $src $dst)) { continue }
        Write-Host "  [update] $name"
        if (-not $DryRun) {
            # Replace wholesale so files deleted upstream also disappear here.
            if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
            Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
        }
        $changed++
    }

    if ($DryRun) {
        Write-Host "[dry-run] $changed skill(s) would be updated; lock not written."
        exit 0
    }

    [pscustomobject]@{
        repo   = $upstreamRepo
        ref    = $Ref
        commit = $commit
        skills = @($managed)
    } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $lockPath -Encoding utf8

    if ($changed -eq 0) {
        Write-Host "[OK] Anthropic skills already current at $short (lock refreshed)."
    } else {
        Write-Host "[OK] Updated $changed skill(s) to $upstreamRepo@$short."
        Write-Host "     Review with: git diff -- .github/skills"
    }
    if ($skipped -gt 0) { Write-Warning "$skipped vendored skill(s) were not in the archive - left untouched." }

    if ($newUpstream.Count -gt 0) {
        Write-Host "[INFO] Upstream also offers: $($newUpstream -join ', ')"
        Write-Host "       Create the folder in .github\skills to start tracking one."
    }
}
finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
exit 0
