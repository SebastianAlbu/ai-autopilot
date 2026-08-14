<#
.SYNOPSIS
    Install the agents + skills GLOBALLY for every AI tool on this machine, in ONE
    physical place, so nothing ever shows up twice.

    Runs on Windows, macOS and Linux (PowerShell 7+). On macOS/Linux ./install.sh does
    the same job without needing PowerShell installed.

.DESCRIPTION
    Layout:
        ~/.claude/skills      <- THE skills store (one physical copy)
        ~/.copilot/skills     -> link to ~/.claude/skills   (junction on Windows)
        ~/.claude/agents      <- agents, Claude subagent schema (*.md)
        ~/.copilot/agents     <- agents, Copilot schema (*.agent.md)

    Why skills are NOT copied twice: VS Code Copilot reads ~/.claude/skills natively
    AND every folder listed in chat.agentSkillsLocations. Installing into both
    ~/.claude/skills and ~/.copilot/skills (and registering the latter) is exactly what
    makes each skill appear twice in the picker. So we keep one real folder, junction
    the other, and remove the duplicate registration.

    Agents genuinely need two folders: the two tools use different front-matter schemas
    and different file extensions, so they never collide.

    Every run PRUNES what previous versions installed - tracked in the manifest at
    ~/.ai-autopilot-manifest.json - from every known location first, so old copies from
    earlier layouts cannot linger.

    It also refreshes the Anthropic-authored skills vendored in .github/skills (docx, pdf,
    pptx, xlsx, skill-creator, frontend-design, ...) from anthropics/skills before copying,
    so you never install a stale copy. Offline is fine - it warns and installs what is
    vendored.

.PARAMETER NoCaveman
    Skip the caveman download.

.PARAMETER NoAnthropicUpdate
    Skip refreshing the vendored Anthropic skills from anthropics/skills.

.PARAMETER PruneOnly
    Remove everything this installer owns (all locations), then stop.

.PARAMETER NoLink
    Copy into ~/.copilot/skills instead of linking it. Re-introduces duplicates; use only
    if directory links are unavailable.

.PARAMETER DryRun
    Show what would be added/removed. Changes nothing.
#>
[CmdletBinding()]
param(
    [switch]$NoCaveman,
    [switch]$NoAnthropicUpdate,
    [switch]$PruneOnly,
    [switch]$NoLink,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# --- Platform ---------------------------------------------------------------------
# PowerShell 7 runs on macOS and Linux too, so this installer must not assume Windows.
# $IsWindows only exists in PS 6+; on Windows PowerShell 5.1 it is undefined, and that
# edition is Windows-only, hence the fallback.
$onWindows = if ($PSVersionTable.PSEdition -eq 'Desktop') { $true }
             elseif (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) { $IsWindows }
             else { $true }

# Build paths segment by segment - a literal '\' inside a string is not a separator on
# macOS/Linux and would create files with backslashes in their names.
function Join-Segments {
    param([Parameter(Mandatory)][string]$Base, [Parameter(Mandatory)][string[]]$Parts)
    $p = $Base
    foreach ($part in $Parts) { $p = Join-Path $p $part }
    return $p
}

$root = $PSScriptRoot
$agentsSrc = Join-Segments $root @('.github','agents')
$skillsSrc = Join-Segments $root @('.github','skills')
$manifestPath = Join-Path $HOME '.ai-autopilot-manifest.json'

if (-not $PruneOnly -and (-not (Test-Path $agentsSrc) -or -not (Test-Path $skillsSrc))) {
    Write-Error "Missing .github\agents or .github\skills next to this script. Run from the repo root."
    exit 1
}

$skillsStore   = Join-Segments $HOME @('.claude','skills')    # the one real skills folder
$copilotSkills = Join-Segments $HOME @('.copilot','skills')   # link to the store
$claudeAgents  = Join-Segments $HOME @('.claude','agents')    # Claude subagent schema
$copilotAgents = Join-Segments $HOME @('.copilot','agents')   # Copilot *.agent.md schema

# Where VS Code keeps the user settings.json, per platform.
$vsCodeUserDirs = if ($onWindows) {
    @(
        $(if ($env:APPDATA) { Join-Segments $env:APPDATA @('Code','User') }),
        $(if ($env:APPDATA) { Join-Segments $env:APPDATA @('Code - Insiders','User') }),
        (Join-Segments $HOME @('scoop','apps','vscode','current','data','user-data','User'))
    )
} elseif ($IsMacOS) {
    @(
        (Join-Segments $HOME @('Library','Application Support','Code','User')),
        (Join-Segments $HOME @('Library','Application Support','Code - Insiders','User'))
    )
} else {
    $cfg = if ($env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME } else { Join-Path $HOME '.config' }
    @(
        (Join-Segments $cfg @('Code','User')),
        (Join-Segments $cfg @('Code - Insiders','User'))
    )
}
$vsCodeUserDirs = @($vsCodeUserDirs | Where-Object { $_ })

# Every place any version of this installer has ever written to. Pruned each run -
# but only for items we own, never blindly.
# Join-Path throws on a null base, and $env:APPDATA is null off Windows - so the VS Code
# entries come from $vsCodeUserDirs, which is already platform-resolved.
$legacySkillRoots = @(
    (Join-Segments $HOME @('.copilot','skills')),
    (Join-Segments $HOME @('.claude','skills')),
    (Join-Segments $HOME @('.vscode','skills'))
) + @($vsCodeUserDirs | ForEach-Object { Join-Path $_ 'skills' })
$legacyAgentRoots = @(
    (Join-Segments $HOME @('.copilot','agents')),
    (Join-Segments $HOME @('.claude','agents')),
    (Join-Segments $HOME @('.vscode','agents'))
) + @($vsCodeUserDirs | ForEach-Object { Join-Path $_ 'agents' })

# Skills this installer places that do not live in the repo (downloaded by the caveman
# step). They are ours, so prune must be allowed to remove them.
$cavemanNames = @('cavecrew','caveman','caveman-commit','caveman-compress','caveman-help','caveman-review','caveman-stats')

function Remove-Item-Safe {
    param([string]$Path, [string]$Label = '  -')
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    Write-Host "$Label $Path"
    if (-not $DryRun) { Remove-Item -LiteralPath $Path -Recurse -Force }
    return $true
}

$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
    try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { Write-Warning "Manifest at $manifestPath is unreadable - pruning falls back to the repo contents only." }
}

function Get-RepoSkillNames {
    if (-not (Test-Path $skillsSrc)) { return @() }
    return @(Get-ChildItem -Path $skillsSrc -Directory | Select-Object -ExpandProperty Name)
}
function Get-RepoAgentSlugs {
    if (-not (Test-Path $agentsSrc)) { return @() }
    return @(Get-ChildItem -Path $agentsSrc -Filter '*.agent.md' | ForEach-Object { $_.Name -replace '\.agent\.md$', '' })
}

# What we own = repo contents + caveman + whatever the last run recorded. The manifest
# is what lets us clean up items renamed or dropped between versions.
$managedSkills = @(Get-RepoSkillNames) + $cavemanNames + @($manifest.skills) | Where-Object { $_ } | Sort-Object -Unique
$managedAgents = @(Get-RepoAgentSlugs) + @($manifest.agents) | Where-Object { $_ } | Sort-Object -Unique

# Recorded previously but NOT reinstalled by this run - the only items safe to delete
# from the install targets themselves; everything else there is overwritten by the copy.
# Caveman names stay in the "live" set even with -NoCaveman: that switch means "do not
# re-download", not "delete what is already installed". Listing them as stale would drop
# them from the store with nothing to restore them.
$liveSkills = @(Get-RepoSkillNames) + $cavemanNames | Where-Object { $_ }
$staleSkills = @($manifest.skills) | Where-Object { $_ -and $liveSkills -notcontains $_ }
$staleAgents = @($manifest.agents) | Where-Object { $_ -and (Get-RepoAgentSlugs) -notcontains $_ }

$installTargets = @($skillsStore, $claudeAgents, $copilotAgents)

function Test-IsLink {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return ($item -and $item.LinkType)
}

Write-Host ""
Write-Host "Installing from : $(Join-Path $root '.github')"
Write-Host "Skills store    : $skillsStore   (single copy)"
Write-Host "Copilot skills  : $copilotSkills $(if ($NoLink) { '(copy)' } elseif ($onWindows) { '(junction)' } else { '(symlink)' })"
Write-Host "Agents          : $claudeAgents (Claude)  +  $copilotAgents (Copilot)"
if ($DryRun) { Write-Host "MODE            : dry run - nothing will change" }
Write-Host ""

# --- Prune ------------------------------------------------------------------------
# Two different jobs, deliberately kept apart:
#   1. Old LOCATIONS   -> remove every managed item (nothing there gets rewritten).
#   2. Install TARGETS -> remove only STALE items; the rest is overwritten by the copy.
#      Pruning live items here would delete things a -NoCaveman run never restores.
Write-Host "Pruning previous installs (manifest-scoped)..."
$removed = 0
foreach ($name in $managedSkills) {
    foreach ($r in $legacySkillRoots) {
        if ($installTargets -contains $r) { continue }
        if (Test-IsLink $r) { continue }   # a link is the store itself - never delete through it
        if (Remove-Item-Safe (Join-Path $r $name)) { $removed++ }
    }
}
foreach ($name in $managedAgents) {
    foreach ($r in $legacyAgentRoots) {
        if ($installTargets -contains $r) { continue }
        if (Test-IsLink $r) { continue }
        foreach ($f in @("$name.agent.md", "$name.md")) {
            if (Remove-Item-Safe (Join-Path $r $f)) { $removed++ }
        }
    }
}
if ($PruneOnly) {
    # Full removal: the install targets are not being rewritten this time, so the live
    # items there have to go too.
    foreach ($name in $managedSkills) { if (Remove-Item-Safe (Join-Path $skillsStore $name)) { $removed++ } }
    foreach ($name in $managedAgents) {
        if (Remove-Item-Safe (Join-Path $claudeAgents  "$name.md"))       { $removed++ }
        if (Remove-Item-Safe (Join-Path $copilotAgents "$name.agent.md")) { $removed++ }
    }
    if (Test-IsLink $copilotSkills) { Remove-Item-Safe $copilotSkills | Out-Null }
    if (-not $DryRun -and (Test-Path -LiteralPath $manifestPath)) { Remove-Item -LiteralPath $manifestPath -Force }
    Write-Host "[OK] Pruned $removed item(s)."
    Write-Host ""
    Write-Host "Prune complete. Nothing was installed (-PruneOnly)."
    exit 0
}
foreach ($name in $staleSkills) { if (Remove-Item-Safe (Join-Path $skillsStore $name) '  - (stale)') { $removed++ } }
foreach ($name in $staleAgents) {
    if (Remove-Item-Safe (Join-Path $claudeAgents  "$name.md")       '  - (stale)') { $removed++ }
    if (Remove-Item-Safe (Join-Path $copilotAgents "$name.agent.md") '  - (stale)') { $removed++ }
}
Write-Host "[OK] Pruned $removed item(s)."

# --- Refresh the vendored Anthropic skills before copying anything ----------------
# Runs against the repo, not the install targets, so the update is visible in git and
# the same refreshed files land in every store.
if (-not $NoAnthropicUpdate) {
    $updater = Join-Path $root 'Update-AnthropicSkills.ps1'
    if (Test-Path $updater) {
        try { if ($DryRun) { & $updater -DryRun } else { & $updater } }
        catch { Write-Warning "Anthropic skill refresh failed ($($_.Exception.Message)) - installing the vendored copies." }
    } else {
        Write-Warning "Update-AnthropicSkills.ps1 not found - installing the vendored copies."
    }
    Write-Host ""
}

# --- Skills: ONE physical copy ----------------------------------------------------
if (-not $DryRun) {
    New-Item -ItemType Directory -Path $skillsStore -Force | Out-Null
    Copy-Item -Path (Join-Path $skillsSrc '*') -Destination $skillsStore -Recurse -Force
}
Write-Host "[OK] Skills installed to $skillsStore."

# --- Copilot CLI: point its folder at the same store ------------------------------
$useLink = -not $NoLink
if ($useLink) {
    if (Test-IsLink $copilotSkills) {
        if (-not $DryRun) { Remove-Item -LiteralPath $copilotSkills -Force -Recurse }
    }
    elseif (Test-Path -LiteralPath $copilotSkills) {
        # Real folder from an older install. Our items were pruned above, so what
        # remains belongs to the user - never delete that blindly.
        $foreign = @(Get-ChildItem -LiteralPath $copilotSkills -Force -ErrorAction SilentlyContinue |
                     Where-Object { $managedSkills -notcontains $_.Name } | Select-Object -ExpandProperty Name)
        if ($foreign.Count -eq 0) {
            if (-not $DryRun) { Remove-Item -LiteralPath $copilotSkills -Recurse -Force }
        } else {
            Write-Warning "$copilotSkills holds skills this installer does not own:"
            $foreign | ForEach-Object { Write-Host "         $_" }
            Write-Warning "Leaving it as a real folder - those may appear twice. Move them into $skillsStore and re-run."
            $useLink = $false
        }
    }
}
if ($useLink) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $copilotSkills) -Force | Out-Null
        # On Windows a Junction works for directories without admin rights or Developer
        # Mode, which a plain symlink there requires. Elsewhere, junctions do not exist.
        $linkType = if ($onWindows) { 'Junction' } else { 'SymbolicLink' }
        New-Item -ItemType $linkType -Path $copilotSkills -Target $skillsStore | Out-Null
    }
    Write-Host "[OK] $copilotSkills -> $skillsStore ($(if ($onWindows) { 'junction' } else { 'symlink' }), no second copy)."
} else {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $copilotSkills -Force | Out-Null
        Copy-Item -Path (Join-Path $skillsSrc '*') -Destination $copilotSkills -Recurse -Force
    }
    Write-Host "[OK] Skills copied to $copilotSkills (second copy - duplicates are possible)."
}

# --- Agents: two schemas, two folders, no overlap ---------------------------------
if (-not $DryRun) {
    New-Item -ItemType Directory -Path $copilotAgents -Force | Out-Null
    New-Item -ItemType Directory -Path $claudeAgents  -Force | Out-Null
    Copy-Item -Path (Join-Path $agentsSrc '*') -Destination $copilotAgents -Recurse -Force

    foreach ($file in Get-ChildItem -Path $agentsSrc -Filter '*.agent.md') {
        $slug = $file.Name -replace '\.agent\.md$', ''
        $fm = 0; $desc = ''; $inBody = $false
        $body = New-Object System.Collections.Generic.List[string]
        foreach ($ln in Get-Content -LiteralPath $file.FullName) {
            if ($ln -match '^---\s*$') { $fm++; if ($fm -ge 2) { $inBody = $true }; continue }
            if ($fm -eq 1 -and $ln -match '^description:') { $desc = $ln; continue }
            if ($fm -eq 1) { continue }
            if ($inBody) { $body.Add($ln) }
        }
        $out = @('---', "name: $slug")
        if ($desc) { $out += $desc }
        $out += '---'
        $out += $body
        Set-Content -LiteralPath (Join-Path $claudeAgents "$slug.md") -Value $out -Encoding utf8
    }
}
Write-Host "[OK] Agents installed (Copilot + Claude Code)."

# --- Caveman skills: into the single store only -----------------------------------
if (-not $NoCaveman -and -not $DryRun) {
    $caveman = Join-Path $root 'Install-Caveman.ps1'
    if (Test-Path $caveman) {
        try { & $caveman -DstPath @($skillsStore) }
        catch { Write-Warning "caveman install failed ($($_.Exception.Message)) - skipping." }
    } else {
        Write-Warning "Install-Caveman.ps1 not found - skipping caveman."
    }
}
Write-Host ""

# --- VS Code settings.json ---------------------------------------------------------
# agentFilesLocations  -> ~/.copilot/agents (VS Code needs the *.agent.md schema)
# agentSkillsLocations -> nothing of ours. VS Code already reads ~/.claude/skills
#                         natively; registering a second skills folder is exactly what
#                         produced the duplicates, so it is removed.
$userDir = $null
foreach ($c in $vsCodeUserDirs) { if ($c -and (Test-Path $c)) { $userDir = $c; break } }

if ($userDir -and -not $DryRun) {
    $reg = Join-Path $root 'Register-CopilotLocations.ps1'
    & $reg -SettingsPath (Join-Path $userDir 'settings.json') -CopilotDir (Join-Path $HOME '.copilot')
} elseif (-not $userDir) {
    Write-Host "[INFO] No VS Code user folder detected - skipping settings.json registration."
}

# --- Manifest ---------------------------------------------------------------------
if (-not $DryRun) {
    [pscustomobject]@{
        generatedBy   = 'ai-autopilot Install-AiAutopilot.ps1'
        skillsStore   = $skillsStore
        claudeAgents  = $claudeAgents
        copilotAgents = $copilotAgents
        # What is installed RIGHT NOW, not the historical union - writing the union
        # would keep every long-removed name in the file forever, so it could never
        # stop being reported as stale.
        skills        = @($liveSkills | Sort-Object -Unique)
        agents        = @(Get-RepoAgentSlugs | Sort-Object -Unique)
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
}

# --- Doctor: the check that catches this class of bug -------------------------------
Write-Host ""
$dupes = 0
foreach ($name in $managedSkills) {
    $hits = @()
    foreach ($r in $legacySkillRoots) {
        if (Test-IsLink $r) { continue }   # a link is the same physical folder
        if (Test-Path -LiteralPath (Join-Path $r $name)) { $hits += $r }
    }
    if ($hits.Count -gt 1) {
        Write-Host "[DUPLICATE] skill '$name' exists in: $($hits -join ', ')"
        $dupes++
    }
}
if ($dupes -gt 0) {
    Write-Warning "$dupes duplicated skill(s) - tools scanning both roots will list them twice."
    Write-Warning "Re-run this installer (it prunes), or delete the extra copies listed above."
} else {
    Write-Host "[OK] No duplicates: every skill exists in exactly one physical location."
}

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  - Claude Code: restart it (or run /agents) - loads from ~/.claude."
Write-Host "  - VS Code: run 'Developer: Reload Window'."
Write-Host "  - Copilot CLI: picks up ~/.copilot automatically."
