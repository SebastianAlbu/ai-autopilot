<#
.SYNOPSIS
    Collects pull request context for review: metadata + unified diff + changed files.

.DESCRIPTION
    Three ways to point at a PR:
      A) URL mode:     -Url <pull-request link>  (paste the Bitbucket PR link; everything is parsed from it)
      B) PR id mode:   -PullRequestId <id> -Repo <slug>
      C) Branch mode:  -SourceBranch <branch> [-TargetBranch <branch>]

    How the diff is obtained:
      * REST mode (A and B, when a token/credential is available): the script fetches metadata,
        the changed-file list AND the unified diff directly from the Bitbucket Data Center REST API
        at https://git.marquardt.de. No local checkout is required — paste a link and go.
      * Local git fallback: if REST is unavailable (no token / offline / older server), the script
        diffs the branches from a local checkout (-RepoPath) using the merge-base.

    Authentication for the REST call (never hardcode secrets):
      - -Token <PAT>            sent as 'Authorization: Bearer <token>'
      - $env:BITBUCKET_PAT      used automatically if -Token is omitted
      - -UseDefaultCredentials  domain SSO (NTLM/Kerberos)

.PARAMETER Url
    A Bitbucket pull request URL, e.g.
    https://git.marquardt.de/projects/TDST/repos/my-repo/pull-requests/42/overview
    The project key, repo slug, PR id and base URL are all extracted from it.

.PARAMETER SourceBranch
    Branch that contains the changes (the PR "from" ref). e.g. feature/TDST-123.

.PARAMETER TargetBranch
    Branch the PR merges into (the PR "to" ref). Defaults to 'develop'.

.PARAMETER PullRequestId
    Numeric Bitbucket pull request id. Triggers REST mode.

.PARAMETER Repo
    Repository slug, required in PR id mode.

.PARAMETER Project
    Bitbucket project key. Defaults to 'TDST'.

.PARAMETER RepoPath
    Path to the local git checkout, used only for the local-git fallback. Defaults to the current directory.

.PARAMETER NoRestDiff
    Force the local-git diff even when REST is available (e.g. to review uncommitted local state).

.EXAMPLE
    pwsh ./Get-PullRequestContext.ps1 -Url https://git.marquardt.de/projects/TDST/repos/my-repo/pull-requests/42/overview

.EXAMPLE
    pwsh ./Get-PullRequestContext.ps1 -PullRequestId 42 -Repo my-repo

.EXAMPLE
    pwsh ./Get-PullRequestContext.ps1 -SourceBranch feature/TDST-123 -TargetBranch develop -RepoPath C:\repo\my-repo
#>
[CmdletBinding(DefaultParameterSetName = 'Branches')]
param(
    [Parameter(ParameterSetName = 'Url', Mandatory = $true)]
    [string]$Url,

    [Parameter(ParameterSetName = 'Branches')]
    [string]$SourceBranch,

    [Parameter(ParameterSetName = 'Branches')]
    [Parameter(ParameterSetName = 'Pr')]
    [string]$TargetBranch = 'develop',

    [Parameter(ParameterSetName = 'Pr', Mandatory = $true)]
    [int]$PullRequestId,

    [Parameter(ParameterSetName = 'Pr', Mandatory = $true)]
    [string]$Repo,

    [string]$Project = 'TDST',
    [string]$BaseUrl = 'https://git.marquardt.de',
    [string]$Token = $env:BITBUCKET_PAT,
    [switch]$UseDefaultCredentials,
    [switch]$NoRestDiff,
    [string]$RepoPath = '.',
    [int]$ContextLines = 3
)

$ErrorActionPreference = 'Stop'

function Get-JiraKeys {
    param([string]$Text)
    return @([regex]::Matches("$Text", '[A-Z][A-Z0-9]+-\d+') | ForEach-Object { $_.Value } | Select-Object -Unique)
}

function Invoke-Bitbucket {
    param([string]$Uri, [switch]$Raw)
    $headers = @{ Accept = if ($Raw) { 'text/plain' } else { 'application/json' } }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{ Uri = $Uri; Headers = $headers; Method = 'GET'; UseBasicParsing = $true }
    if ($UseDefaultCredentials) { $params['UseDefaultCredentials'] = $true }
    if ($Raw) { return (Invoke-WebRequest @params).Content }
    return Invoke-RestMethod @params
}

function Resolve-Ref {
    param([string]$Name)
    foreach ($candidate in @($Name, "origin/$Name")) {
        git rev-parse --verify --quiet "$candidate^{commit}" *> $null
        if ($LASTEXITCODE -eq 0) { return $candidate }
    }
    throw "Cannot resolve branch '$Name' locally. Run: git fetch origin $Name"
}

function Get-DiffStat {
    param([string]$DiffText)
    $add = 0; $del = 0
    foreach ($line in ($DiffText -split "`n")) {
        if ($line -match '^\+' -and $line -notmatch '^\+\+\+') { $add++ }
        elseif ($line -match '^-' -and $line -notmatch '^---') { $del++ }
    }
    return "+$add / -$del lines changed"
}

# --- Parse the URL (URL mode) into project / repo / id / base URL -----------------------------------
if ($PSCmdlet.ParameterSetName -eq 'Url') {
    $m = [regex]::Match($Url, 'projects/([^/]+)/repos/([^/]+)/pull-requests/(\d+)', 'IgnoreCase')
    if (-not $m.Success) {
        throw "Could not parse a Bitbucket PR URL. Expected '.../projects/<KEY>/repos/<slug>/pull-requests/<id>'. Got: $Url"
    }
    $Project       = $m.Groups[1].Value
    $Repo          = $m.Groups[2].Value
    $PullRequestId = [int]$m.Groups[3].Value
    $uri           = [Uri]$Url
    $BaseUrl       = '{0}://{1}' -f $uri.Scheme, $uri.Authority
}

$useRest = $PSCmdlet.ParameterSetName -in @('Url', 'Pr')
$restBase = '{0}/rest/api/1.0/projects/{1}/repos/{2}/pull-requests/{3}' -f $BaseUrl.TrimEnd('/'), $Project, $Repo, $PullRequestId

$meta = $null
$changedFiles = $null
$diffStat = $null
$diff = $null
$restDiffOk = $false

# --- REST path: pull metadata + changed files + diff straight from Bitbucket ------------------------
if ($useRest) {
    try {
        $pr = Invoke-Bitbucket -Uri $restBase
        $SourceBranch = $pr.fromRef.displayId
        $TargetBranch = $pr.toRef.displayId
        $reviewers = @($pr.reviewers | ForEach-Object { $_.user.displayName })
        $meta = [pscustomobject]@{
            id           = $pr.id
            title        = $pr.title
            description  = $pr.description
            author       = $pr.author.user.displayName
            reviewers    = $reviewers
            sourceBranch = $SourceBranch
            targetBranch = $TargetBranch
            state        = $pr.state
            jiraKeys     = Get-JiraKeys ("{0} {1} {2}" -f $pr.title, $pr.description, $SourceBranch)
            link         = '{0}/projects/{1}/repos/{2}/pull-requests/{3}/overview' -f $BaseUrl.TrimEnd('/'), $Project, $Repo, $PullRequestId
            source       = 'bitbucket-rest'
        }
    }
    catch {
        Write-Warning "Bitbucket metadata REST call failed ($($_.Exception.Message)). Will try local git."
    }

    if (-not $NoRestDiff) {
        try {
            # Changed files via the /changes endpoint (paged).
            $statusMap = @{ ADD = 'A'; MODIFY = 'M'; DELETE = 'D'; MOVE = 'R'; COPY = 'C'; UNKNOWN = '?' }
            $lines = New-Object System.Collections.Generic.List[string]
            $start = 0
            do {
                $changes = Invoke-Bitbucket -Uri ("{0}/changes?limit=1000&start={1}" -f $restBase, $start)
                foreach ($c in $changes.values) {
                    $letter = $statusMap[[string]$c.type]; if (-not $letter) { $letter = '?' }
                    $lines.Add(("{0}`t{1}" -f $letter, $c.path.toString))
                }
                $start = $changes.nextPageStart
            } while (-not $changes.isLastPage)
            $changedFiles = $lines -join "`n"

            # Unified diff via the .diff endpoint (raw text).
            $diff = Invoke-Bitbucket -Raw -Uri ("{0}.diff?contextLines={1}" -f $restBase, $ContextLines)
            $diffStat = Get-DiffStat $diff
            $restDiffOk = $true
        }
        catch {
            Write-Warning "Bitbucket diff REST call failed ($($_.Exception.Message)). Falling back to local git diff."
        }
    }
}

# --- Local git fallback (or Branch mode): compute the diff from a checkout ---------------------------
if (-not $restDiffOk) {
    if (-not $SourceBranch) {
        throw "No diff from REST and no -SourceBranch available. Provide -Url/-PullRequestId with a token, or -SourceBranch."
    }
    Push-Location $RepoPath
    try {
        git fetch --quiet origin *> $null
        $src = Resolve-Ref $SourceBranch
        $tgt = Resolve-Ref $TargetBranch
        $mergeBase = (git merge-base $tgt $src).Trim()

        $changedFiles = git diff --name-status "$mergeBase" "$src"
        $diffStat     = git diff --stat        "$mergeBase" "$src"
        $diff         = git diff --unified=$ContextLines "$mergeBase" "$src"

        if (-not $meta) {
            $commitText = (git log "$mergeBase..$src" --pretty=format:'%s%n%b') -join ' '
            $meta = [pscustomobject]@{
                id           = $PullRequestId
                title        = (git log -1 --pretty=%s $src)
                description  = (git log -1 --pretty=%b $src)
                author       = (git log -1 --pretty=%an $src)
                reviewers    = @()
                sourceBranch = $SourceBranch
                targetBranch = $TargetBranch
                state        = 'LOCAL'
                jiraKeys     = Get-JiraKeys $commitText
                link         = $null
                source       = 'local-git'
            }
        }
    }
    finally {
        Pop-Location
    }
}

Write-Output "===== PR METADATA ====="
$meta | ConvertTo-Json -Depth 6
Write-Output ""
Write-Output "===== CHANGED FILES ====="
$changedFiles
Write-Output ""
Write-Output "===== DIFFSTAT ====="
$diffStat
Write-Output ""
Write-Output "===== UNIFIED DIFF ====="
$diff
