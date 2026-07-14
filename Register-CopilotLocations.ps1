<#
.SYNOPSIS
    Register the ~/.copilot agents + skills folders in a VS Code user settings.json.

.DESCRIPTION
    VS Code (Copilot) and the Copilot CLI both scan "~/.copilot/agents" and
    "~/.copilot/skills" as GLOBAL locations by default, so copying the files there is
    normally enough. This script additionally registers those folders in the VS Code
    user settings.json as a belt-and-suspenders measure (covers older builds that do
    not scan ~/.copilot yet):

        chat.agentSkillsLocations  -> "~/.copilot/skills"   (accepts "~/"-relative)
        chat.agentFilesLocations   -> "<abs>/.copilot/agents" (no "~" expansion; abs)

    Edits are idempotent and preserve existing JSONC (comments / trailing commas) by
    doing targeted text inserts rather than a full re-serialize.

.PARAMETER SettingsPath
    Full path to the VS Code user settings.json.

.PARAMETER CopilotDir
    Full path to the ~/.copilot folder that holds the "agents" and "skills" sub-folders.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SettingsPath,
    [Parameter(Mandatory)][string]$CopilotDir
)

$ErrorActionPreference = 'Stop'

$copilot = ($CopilotDir -replace '\\', '/').TrimEnd('/')
$homeFwd = ($HOME -replace '\\', '/').TrimEnd('/')

# Skills setting accepts "~/"-relative; rewrite when under the home folder.
$skills = "$copilot/skills"
if ($skills.ToLower().StartsWith(($homeFwd.ToLower() + '/'))) {
    $skillsValue = '~/' + $skills.Substring($homeFwd.Length + 1)
} else {
    $skillsValue = $skills
}
# Agents setting does NOT expand "~"; use an absolute path with forward slashes.
$agentsValue = "$copilot/agents"

# Ensure the settings file (and its folder) exist.
if (-not (Test-Path -LiteralPath $SettingsPath)) {
    $dir = Split-Path -Parent $SettingsPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content -LiteralPath $SettingsPath -Value "{$([Environment]::NewLine)}" -Encoding utf8
}

function Add-LocationEntry {
    param([string]$Key, [string]$Value)

    $text = Get-Content -LiteralPath $SettingsPath -Raw
    if ($null -eq $text) { $text = '{}' }

    $escapedKey = [regex]::Escape($Key)
    if ($text -match $escapedKey) {
        if ($text -match [regex]::Escape($Value)) {
            Write-Host "[OK] '$Key' already includes '$Value'."
        } else {
            Write-Warning "'$Key' exists but does not list '$Value'."
            Write-Warning "Add this line inside it manually:  `"$Value`": true"
        }
        return
    }

    $nl = [Environment]::NewLine
    $entry = @(
        "    `"$Key`": {"
        "        `"$Value`": true"
        '    },'
    ) -join $nl

    $open = $text.IndexOf('{')
    if ($open -lt 0) {
        $newText = "{$nl$entry$nl}"
    } else {
        $newText = $text.Substring(0, $open + 1) + $nl + $entry + $text.Substring($open + 1)
    }
    Set-Content -LiteralPath $SettingsPath -Value $newText -Encoding utf8 -NoNewline
    Write-Host "[OK] Added '$Key' -> $Value"
}

Add-LocationEntry -Key 'chat.agentSkillsLocations' -Value $skillsValue
Add-LocationEntry -Key 'chat.agentFilesLocations'  -Value $agentsValue
