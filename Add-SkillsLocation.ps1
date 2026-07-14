<#
.SYNOPSIS
    Register a skills folder in the VS Code user settings.json so the skills load
    in every workspace (via the "chat.agentSkillsLocations" setting).

.DESCRIPTION
    Agent files (*.agent.md) in the user "prompts" folder are picked up globally,
    but skills are NOT — VS Code only scans workspace skill locations unless you add
    an extra location to the user setting "chat.agentSkillsLocations". This script
    adds that entry idempotently, preserving existing JSONC (comments / trailing
    commas) by doing a targeted text insert rather than a full re-serialize.

.PARAMETER SettingsPath
    Full path to the VS Code user settings.json.

.PARAMETER SkillsDir
    Full path to the folder that contains the skill sub-folders (each with SKILL.md).

.EXAMPLE
    ./Add-SkillsLocation.ps1 -SettingsPath "C:\Users\me\...\User\settings.json" `
                             -SkillsDir "C:\Users\me\...\User\prompts\skills"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SettingsPath,
    [Parameter(Mandatory)][string]$SkillsDir
)

$ErrorActionPreference = 'Stop'

# The "chat.agentSkillsLocations" setting only accepts paths that are relative or
# start with "~/" (absolute paths and "\" separators are rejected by VS Code).
# Use forward slashes and, when the folder lives under the user's home directory,
# rewrite it as a "~/"-relative path so it applies to every workspace.
$skills = ($SkillsDir -replace '\\', '/').TrimEnd('/')
$homeFwd = ($HOME -replace '\\', '/').TrimEnd('/')
if ($skills.ToLower().StartsWith(($homeFwd.ToLower() + '/'))) {
    $skills = '~/' + $skills.Substring($homeFwd.Length + 1)
}
elseif ($skills -match '^[A-Za-z]:/') {
    Write-Warning "Skills folder '$skills' is not under your home directory."
    Write-Warning "VS Code's 'chat.agentSkillsLocations' does not accept absolute paths;"
    Write-Warning "move the skills under your home folder, or add a '~/'-relative entry manually."
    return
}

# Ensure the settings file (and its folder) exist.
if (-not (Test-Path -LiteralPath $SettingsPath)) {
    $dir = Split-Path -Parent $SettingsPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -LiteralPath $SettingsPath -Value "{$([Environment]::NewLine)}" -Encoding utf8
}

$text = Get-Content -LiteralPath $SettingsPath -Raw
if ($null -eq $text) { $text = '{}' }

# Already configured?
if ($text -match 'chat\.agentSkillsLocations') {
    if ($text -match [regex]::Escape($skills)) {
        Write-Host "[OK] 'chat.agentSkillsLocations' already includes this skills folder."
        return
    }
    Write-Warning "'chat.agentSkillsLocations' exists but does not list this folder."
    Write-Warning "Add this line inside it manually:  `"$skills`": true"
    return
}

$nl = [Environment]::NewLine
$entry = @(
    '    "chat.agentSkillsLocations": {'
    "        `"$skills`": true"
    '    },'
) -join $nl

# Insert right after the opening brace so we don't touch existing entries.
$open = $text.IndexOf('{')
if ($open -lt 0) {
    $newText = "{$nl$entry$nl}"
} else {
    $newText = $text.Substring(0, $open + 1) + $nl + $entry + $text.Substring($open + 1)
}

Set-Content -LiteralPath $SettingsPath -Value $newText -Encoding utf8 -NoNewline
Write-Host "[OK] Added 'chat.agentSkillsLocations' -> $skills"
