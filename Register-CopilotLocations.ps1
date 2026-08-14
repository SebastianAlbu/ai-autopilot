<#
.SYNOPSIS
    Register the ~/.copilot agents folder in a VS Code user settings.json, and remove
    any duplicate skills-folder registration.

.DESCRIPTION
    Registers the agents folder, and REMOVES any skills-folder registration:

        chat.agentFilesLocations   -> "<abs>/.copilot/agents"  (added; no "~" expansion)
        chat.agentSkillsLocations  -> "~/.copilot/skills"      (REMOVED, see below)

    VS Code Copilot reads ~/.claude/skills natively. Registering a second skills folder
    that holds the same skills is what makes every skill appear twice in the picker, so
    the installer keeps one real store (~/.claude/skills), junctions ~/.copilot/skills at
    it for the Copilot CLI, and this script strips the now-duplicate registration.

    Agents still need the explicit registration: they live in a separate folder in the
    Copilot *.agent.md schema, which is not what ~/.claude/agents contains.

    Edits are idempotent and preserve existing JSONC (comments / trailing commas) by
    doing targeted text edits rather than a full re-serialize.

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

function Remove-LocationValue {
    param([string]$Value)

    if (-not (Test-Path -LiteralPath $SettingsPath)) { return }
    $lines = @(Get-Content -LiteralPath $SettingsPath)
    $needle = '"' + $Value + '"'
    $kept = @($lines | Where-Object { $_ -notmatch [regex]::Escape($needle) })
    if ($kept.Count -eq $lines.Count) { return }

    # Line-scoped delete on purpose: settings.json is JSONC, so a parse + re-serialize
    # would strip the user's comments. VS Code writes one entry per line.
    Set-Content -LiteralPath $SettingsPath -Value $kept -Encoding utf8
    Write-Host "[OK] Removed duplicate skills location '$Value' from settings.json."
}

# Strip every form the skills folder may have been registered under.
Remove-LocationValue -Value $skillsValue
Remove-LocationValue -Value $skills

Add-LocationEntry -Key 'chat.agentFilesLocations' -Value $agentsValue
