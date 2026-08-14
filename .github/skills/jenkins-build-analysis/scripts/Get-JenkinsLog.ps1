<#
.SYNOPSIS
    Reads a Jenkins build log — the whole console, or just one pipeline stage — filtered or tail-limited.

.DESCRIPTION
    Read-only. Console logs are routinely megabytes, so this script is small by default: the last 200 lines
    unless you ask for more. Use -Grep to find the error, -Stage to read one stage, -Full only when you
    genuinely need everything.

    With -Stage (or by default on a failed Pipeline build) the log is assembled from the stage's child flow
    nodes via /execution/node/{id}/wfapi/log, whose 'text' is HTML-annotated — the markup is stripped.
    Freestyle jobs have no stages; the script falls back to /consoleText.

    Configuration (never hardcode hostnames or secrets) — see JenkinsCommon.ps1:
      JENKINS_BASE_URL, JENKINS_ROOT_JOB, JENKINS_USER + JENKINS_TOKEN (or JENKINS_AUTH='user:token'),
      JENKINS_VERIFY_SSL.

.PARAMETER Target
    Job path relative to the root folder, or a full Jenkins URL.

.PARAMETER Selector
    Build number or symbolic selector (lastBuild, lastFailedBuild, ...). Defaults to lastBuild.

.PARAMETER Stage
    Read only this pipeline stage. Matched case-insensitively, exact name first, then substring.
    Omit it on a Pipeline build and the FAILED/UNSTABLE stage is used automatically.

.PARAMETER Console
    Force the full console log, skipping stage resolution.

.PARAMETER Grep
    Show only lines matching this regex (case-insensitive), with a match count. Beats -Tail for finding errors.

.PARAMETER Tail
    How many trailing lines to show when neither -Grep nor -Full is used. Defaults to 200.

.PARAMETER Full
    Emit the whole log. Expensive — prefer -Grep or -Stage.

.EXAMPLE
    pwsh ./Get-JenkinsLog.ps1 -Target MyComponent/main -Selector lastFailedBuild

.EXAMPLE
    pwsh ./Get-JenkinsLog.ps1 -Target MyComponent/main -Selector lastFailedBuild -Grep 'error|failed|FAILED'

.EXAMPLE
    pwsh ./Get-JenkinsLog.ps1 -Target MyComponent/main -Selector 431 -Stage Build -Tail 100
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,
    [string]$Selector,
    [string]$Stage,
    [switch]$Console,
    [string]$Grep,
    [int]$Tail = 200,
    [switch]$Full,

    [string]$BaseUrl,
    [string]$RootJob,
    [string]$User,
    [string]$Token
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JenkinsCommon.ps1')
Initialize-JenkinsContext -BaseUrl $BaseUrl -RootJob $RootJob -User $User -Token $Token

$buildUrl = Get-JenkinsBuildUrl -Target $Target -Selector $Selector

function Get-StageLogText {
    <#
    Concatenate the logs of a stage's child flow nodes. The stage node itself carries no log text; each
    child step has its own, reachable through the stage's /wfapi/describe.
    #>
    param([Parameter(Mandatory = $true)]$StageNode)

    # _links.self.href is already the absolute path of the stage's describe endpoint.
    $detail = Invoke-Jenkins -Uri ('{0}{1}' -f $script:JenkinsBaseUrl, $StageNode._links.self.href) -Optional
    $nodes  = @(if ($detail -and $detail.stageFlowNodes) { $detail.stageFlowNodes } else { @() })

    $parts = foreach ($node in $nodes) {
        $log = Invoke-Jenkins -Uri ('{0}/execution/node/{1}/wfapi/log' -f $buildUrl, $node.id) -Optional
        if (-not $log -or -not $log.text) { continue }
        $body = ConvertFrom-JenkinsHtmlLog -Text $log.text
        if (-not $body.Trim()) { continue }
        "--- {0} [{1}] ---`n{2}" -f $node.name, $node.status, $body
    }

    return ($parts -join "`n")
}

# --- Stage log --------------------------------------------------------------------------------------
if (-not $Console) {
    $wf = Invoke-Jenkins -Uri ('{0}/wfapi/describe' -f $buildUrl) -Optional
    if ($wf -and $wf.stages) {
        $target = $null
        if ($Stage) {
            $target = @($wf.stages) | Where-Object { "$($_.name)" -eq $Stage } | Select-Object -First 1
            if (-not $target) {
                $target = @($wf.stages) | Where-Object { "$($_.name)" -like "*$Stage*" } | Select-Object -First 1
            }
            if (-not $target) {
                throw ("No stage matching '{0}'. Stages: {1}" -f $Stage, (@($wf.stages).name -join ', '))
            }
        }
        else {
            # No stage asked for: the failed one is what you almost always want.
            $target = @($wf.stages) | Where-Object { "$($_.status)" -in @('FAILED', 'UNSTABLE') } | Select-Object -First 1
        }

        if ($target) {
            $text = Get-StageLogText -StageNode $target
            if ($text.Trim()) {
                Write-Output ("# stage '{0}' [{1}] of {2}`n" -f $target.name, $target.status, $wf.name)
                Write-Output (Format-JenkinsLog -Text $text -Tail $Tail -Full:$Full -Grep $Grep)
                return
            }
            Write-Verbose "Stage '$($target.name)' produced no log text; falling back to the console log."
        }
    }
    elseif ($Stage) {
        throw "No stage data for this build — it is not a Pipeline job (or the Pipeline Stage View plugin is absent). Drop -Stage to read the console log."
    }
}

# --- Console log ------------------------------------------------------------------------------------
$text = Invoke-Jenkins -Uri ('{0}/consoleText' -f $buildUrl) -Raw
Write-Output (Format-JenkinsLog -Text $text -Tail $Tail -Full:$Full -Grep $Grep)
