<#
.SYNOPSIS
    Generates the `plugins/` tree so this repo can also be consumed as a Claude Code / Copilot plugin.

.DESCRIPTION
    `.github/skills` and `.github/agents` are the SOURCE OF TRUTH. This script mirrors them into
    `plugins/ai-autopilot/` and writes the four manifests that the two plugin ecosystems expect:

      plugins/ai-autopilot/plugin.json                 Copilot CLI / VS Code  (may carry a `skills` field)
      plugins/ai-autopilot/.claude-plugin/plugin.json  Claude Code            (must live here, NO `skills` field)
      .claude-plugin/marketplace.json                  Claude Code marketplace
      .github/plugin/marketplace.json                  Copilot / VS Code marketplace

    Agents are emitted in both schemas, exactly as Install-AiAutopilot.ps1 does:
    `<slug>.agent.md` for Copilot, and a Claude-subagent copy (`name:` + `description:` only) for Claude Code.

    EVERYTHING UNDER plugins/ IS GENERATED. Edit `.github/` and re-run this script; hand edits are lost.

.PARAMETER Version
    Plugin version written into both plugin.json manifests. Defaults to the current one, or 1.0.0.

.PARAMETER OutputPath
    Where the plugin tree goes. Defaults to `plugins/ai-autopilot` next to this script.

.PARAMETER DryRun
    Report what would be written without touching the disk.

.EXAMPLE
    pwsh ./Build-Plugin.ps1

.EXAMPLE
    pwsh ./Build-Plugin.ps1 -Version 1.1.0
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$Version,
    [string]$OutputPath,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$root       = $PSScriptRoot
$skillsSrc  = Join-Path $root '.github\skills'
$agentsSrc  = Join-Path $root '.github\agents'
$pluginName = 'ai-autopilot'

if (-not $OutputPath) { $OutputPath = Join-Path $root "plugins\$pluginName" }
$claudeDir      = Join-Path $OutputPath '.claude-plugin'
$marketplaceCc  = Join-Path $root '.claude-plugin\marketplace.json'
$marketplaceGh  = Join-Path $root '.github\plugin\marketplace.json'

foreach ($dir in @($skillsSrc, $agentsSrc)) {
    if (-not (Test-Path -LiteralPath $dir)) { throw "Missing source folder: $dir. Run this from the repo root." }
}

# Keep the version stable across rebuilds unless it is bumped explicitly.
if (-not $Version) {
    $existing = Join-Path $claudeDir 'plugin.json'
    if (Test-Path -LiteralPath $existing) {
        try { $Version = (Get-Content -LiteralPath $existing -Raw | ConvertFrom-Json).version } catch { }
    }
}
if (-not $Version) { $Version = '1.0.0' }

$description = 'AI Autopilot — a PR-review orchestrator with specialist reviewer sub-agents (functionality, PR description, Jira alignment, config centralization, C#/SPLE/Python/embedded-C rulesets) plus the Bitbucket, Jira, Jenkins and Polyspace skills they run on.'

$skillNames = @(Get-ChildItem -Path $skillsSrc -Directory | Select-Object -ExpandProperty Name | Sort-Object)
$agentFiles = @(Get-ChildItem -Path $agentsSrc -Filter '*.agent.md' | Sort-Object Name)

function Write-GeneratedFile {
    param([string]$Path, [string]$Content)
    Write-Host "  + $($Path.Substring($root.Length).TrimStart('\','/'))"
    if ($DryRun) { return }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    Set-Content -LiteralPath $Path -Value $Content -Encoding utf8
}

function ConvertTo-ClaudeAgent {
    <#
    Copilot's *.agent.md frontmatter carries fields (tools, agents, argument-hint) that a Claude subagent
    file does not use. Keep name + description, drop the rest, keep the body verbatim.
    #>
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Slug)

    $fence = 0; $desc = ''; $inBody = $false
    $body = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ($line -match '^---\s*$') { $fence++; if ($fence -ge 2) { $inBody = $true }; continue }
        if ($fence -eq 1 -and $line -match '^description:') { $desc = $line; continue }
        if ($fence -eq 1) { continue }
        if ($inBody) { $body.Add($line) }
    }
    $out = @('---', "name: $Slug")
    if ($desc) { $out += $desc }
    $out += '---'
    return (($out + $body) -join "`n")
}

Write-Host ""
Write-Host "Building plugin '$pluginName' v$Version$(if ($DryRun) { '  [DRY RUN]' })"
Write-Host "  source : $skillsSrc"
Write-Host "           $agentsSrc"
Write-Host "  output : $OutputPath"
Write-Host ""

if (-not $PSCmdlet.ShouldProcess($OutputPath, 'regenerate plugin tree')) { return }

# --- Mirror skills and agents ------------------------------------------------------------------------
# Full replace, not merge: a skill deleted from .github must disappear from the plugin too.
if (-not $DryRun -and (Test-Path -LiteralPath $OutputPath)) {
    Remove-Item -LiteralPath $OutputPath -Recurse -Force
}

Write-Host "Skills ($($skillNames.Count)):"
foreach ($name in $skillNames) { Write-Host "  + skills/$name" }
if (-not $DryRun) {
    New-Item -ItemType Directory -Path (Join-Path $OutputPath 'skills') -Force | Out-Null
    Copy-Item -Path (Join-Path $skillsSrc '*') -Destination (Join-Path $OutputPath 'skills') -Recurse -Force
}

Write-Host "Agents ($($agentFiles.Count)):"
foreach ($file in $agentFiles) {
    $slug = $file.Name -replace '\.agent\.md$', ''
    Write-Host "  + agents/$($file.Name) + agents/$slug.md"
    if ($DryRun) { continue }
    New-Item -ItemType Directory -Path (Join-Path $OutputPath 'agents') -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $OutputPath "agents\$($file.Name)") -Force
    Set-Content -LiteralPath (Join-Path $OutputPath "agents\$slug.md") `
                -Value (ConvertTo-ClaudeAgent -Path $file.FullName -Slug $slug) -Encoding utf8
}

# --- Manifests ---------------------------------------------------------------------------------------
Write-Host "Manifests:"

$generatedNote = 'GENERATED by Build-Plugin.ps1 from .github/{skills,agents} — do not edit by hand.'

# Copilot CLI / VS Code: a `skills` array is allowed and helps discovery.
$copilotPlugin = [ordered]@{
    '_generated' = $generatedNote
    name         = $pluginName
    version      = $Version
    description  = $description
    skills       = $skillNames
}
Write-GeneratedFile -Path (Join-Path $OutputPath 'plugin.json') -Content ($copilotPlugin | ConvertTo-Json -Depth 5)

# Claude Code: the manifest MUST be at .claude-plugin/plugin.json and must NOT declare `skills` —
# Claude discovers them from the skills/ folder, and the extra field fails validation.
$claudePlugin = [ordered]@{
    '_generated' = $generatedNote
    name         = $pluginName
    version      = $Version
    description  = $description
}
Write-GeneratedFile -Path (Join-Path $claudeDir 'plugin.json') -Content ($claudePlugin | ConvertTo-Json -Depth 5)

$marketplace = [ordered]@{
    '_generated' = $generatedNote
    name         = $pluginName
    owner        = [ordered]@{ name = 'AI Autopilot' }
    plugins      = @(
        [ordered]@{
            name        = $pluginName
            source      = "./plugins/$pluginName"
            description = $description
            version     = $Version
        }
    )
}
$marketplaceJson = $marketplace | ConvertTo-Json -Depth 6
Write-GeneratedFile -Path $marketplaceCc -Content $marketplaceJson
Write-GeneratedFile -Path $marketplaceGh -Content $marketplaceJson

Write-GeneratedFile -Path (Join-Path $OutputPath 'README.md') -Content @"
# $pluginName (generated)

**Do not edit anything in this folder.** It is regenerated from `.github/skills` and `.github/agents` by
``Build-Plugin.ps1`` at the repo root. Change the source, then run:

``````powershell
pwsh ./Build-Plugin.ps1
``````

## Install

Claude Code:

``````
/plugin marketplace add <this-repo>
/plugin install $pluginName@$pluginName
``````

Or copy-install everything globally instead, without the plugin system:

``````powershell
pwsh ./Install-AiAutopilot.ps1
``````

Contains $($skillNames.Count) skills and $($agentFiles.Count) agents. See the repo README for what each does
and which environment variables they need.
"@

Write-Host ""
Write-Host "[OK] Plugin tree $(if ($DryRun) { 'would be' } else { 'is' }) up to date ($($skillNames.Count) skills, $($agentFiles.Count) agents)."
Write-Host "     Validate with: claude plugin validate $OutputPath"
Write-Host ""
