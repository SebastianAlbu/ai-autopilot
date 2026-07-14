<#
.SYNOPSIS
    Install the agents + skills GLOBALLY for every AI tool on this Windows machine.

.DESCRIPTION
    Each tool scans its own home folder, so we install into all of them:
        Claude Code     ~/.claude/skills    ~/.claude/agents
        VS Code Copilot ~/.copilot/skills   ~/.copilot/agents  (also reads ~/.claude/skills)
        Copilot CLI     ~/.copilot/skills   ~/.copilot/agents

    Skills use one portable SKILL.md format and are copied as-is. Agents are
    Copilot-format (*.agent.md); for Claude Code they are converted to the subagent
    schema (kebab name + description, full tools). Also downloads the latest "caveman"
    skills and, as a safety net, registers ~/.copilot in the VS Code user settings.json.

.PARAMETER NoCaveman
    Skip the caveman download.
#>
[CmdletBinding()]
param([switch]$NoCaveman)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$agentsSrc = Join-Path $root '.github\agents'
$skillsSrc = Join-Path $root '.github\skills'

if (-not (Test-Path $agentsSrc) -or -not (Test-Path $skillsSrc)) {
    Write-Error "Missing .github\agents or .github\skills next to this script. Run from the repo root."
    exit 1
}

$copilotSkills = Join-Path $HOME '.copilot\skills'
$claudeSkills  = Join-Path $HOME '.claude\skills'
$skillTargets  = @($copilotSkills, $claudeSkills)
$copilotAgents = Join-Path $HOME '.copilot\agents'
$claudeAgents  = Join-Path $HOME '.claude\agents'

Write-Host ""
Write-Host "Installing from : $root\.github"
Write-Host "Skills  -> $($skillTargets -join ', ')"
Write-Host "Agents  -> $copilotAgents (Copilot)  +  $claudeAgents (Claude Code)"
Write-Host ""

# --- Skills: copy the repo skills into every skills target ---
foreach ($dst in $skillTargets) {
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    Copy-Item -Path (Join-Path $skillsSrc '*') -Destination $dst -Recurse -Force
}
Write-Host "[OK] Repo skills installed."

# --- Agents: Copilot-format as-is; convert a Claude subagent copy ---
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
Write-Host "[OK] Agents installed (Copilot + Claude Code)."

# --- Caveman skills: download the latest release into every skills target ---
if (-not $NoCaveman) {
    $caveman = Join-Path $root 'Install-Caveman.ps1'
    if (Test-Path $caveman) {
        try { & $caveman -DstPath $skillTargets }
        catch { Write-Warning "caveman install failed ($($_.Exception.Message)) - skipping." }
    } else {
        Write-Warning "Install-Caveman.ps1 not found - skipping caveman."
    }
}
Write-Host ""

# --- VS Code settings.json: register ~/.copilot as a safety net ---
$userDir = $null
foreach ($c in @(
    (Join-Path $env:APPDATA 'Code\User'),
    (Join-Path $env:APPDATA 'Code - Insiders\User'),
    (Join-Path $HOME 'scoop\apps\vscode\current\data\user-data\User')
)) { if (Test-Path $c) { $userDir = $c; break } }

if ($userDir) {
    $reg = Join-Path $root 'Register-CopilotLocations.ps1'
    & $reg -SettingsPath (Join-Path $userDir 'settings.json') -CopilotDir (Join-Path $HOME '.copilot')
} else {
    Write-Host "[INFO] No VS Code user folder detected - skipping settings.json registration."
}

Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  - Claude Code: restart it (or run /agents) - loads from ~/.claude."
Write-Host "  - VS Code: run 'Developer: Reload Window'."
Write-Host "  - Copilot CLI: picks up ~/.copilot automatically."
