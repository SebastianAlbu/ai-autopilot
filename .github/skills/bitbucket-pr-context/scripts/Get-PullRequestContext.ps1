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
        on a Bitbucket Server / Data Center instance. No local checkout is required — paste a link and go.
      * Local git fallback: if REST is unavailable (no token / offline / older server), the script
        diffs the branches from a local checkout (-RepoPath) using the merge-base.

    Authentication for the REST call (never hardcode secrets):
      - -Token <PAT>            sent as 'Authorization: Bearer <token>'
      - $env:BITBUCKET_PAT      used automatically if -Token is omitted
      - -UseDefaultCredentials  domain SSO (NTLM/Kerberos)

.PARAMETER Url
    A Bitbucket pull request URL, e.g.
    https://bitbucket.example.com/projects/PROJ/repos/my-repo/pull-requests/42/overview
    The project key, repo slug, PR id and base URL are all extracted from it.

.PARAMETER SourceBranch
    Branch that contains the changes (the PR "from" ref). e.g. feature/PROJ-123.

.PARAMETER TargetBranch
    Branch the PR merges into (the PR "to" ref). Defaults to 'develop'.

.PARAMETER PullRequestId
    Numeric Bitbucket pull request id. Triggers REST mode.

.PARAMETER Repo
    Repository slug, required in PR id mode.

.PARAMETER NoPreviousReviews
    Skip the PR-comment lookup used to detect a follow-up (round 2+) review.

.PARAMETER PreviousReviewLimit
    How many of the most recent previous review comments to return. Defaults to 2.

.PARAMETER Project
    Bitbucket project key. Taken from -Url when given; otherwise set it explicitly (or via BITBUCKET_PROJECT).

.PARAMETER RepoPath
    Path to the local git checkout, used only for the local-git fallback. Defaults to the current directory.

.PARAMETER NoRestDiff
    Force the local-git diff even when REST is available (e.g. to review uncommitted local state).

.EXAMPLE
    pwsh ./Get-PullRequestContext.ps1 -Url https://bitbucket.example.com/projects/PROJ/repos/my-repo/pull-requests/42/overview

.EXAMPLE
    pwsh ./Get-PullRequestContext.ps1 -PullRequestId 42 -Repo my-repo

.EXAMPLE
    pwsh ./Get-PullRequestContext.ps1 -SourceBranch feature/PROJ-123 -TargetBranch develop -RepoPath C:\repo\my-repo
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

    [string]$Project = $env:BITBUCKET_PROJECT,
    [string]$BaseUrl = $(if ($env:BITBUCKET_BASE_URL) { $env:BITBUCKET_BASE_URL } else { 'https://bitbucket.example.com' }),
    [string]$Token = $env:BITBUCKET_PAT,
    [switch]$UseDefaultCredentials,
    [switch]$NoRestDiff,
    [switch]$NoPreviousReviews,
    [int]$PreviousReviewLimit = 2,
    [string]$RepoPath = '.',
    [int]$ContextLines = 3
)

$ErrorActionPreference = 'Stop'

function Get-JiraKeys {
    param([string]$Text)
    # ,@(...) keeps an empty result an empty JSON array; a bare @() serialises to null.
    return ,@([regex]::Matches("$Text", '[A-Z][A-Z0-9]+-\d+') | ForEach-Object { $_.Value } | Select-Object -Unique)
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
if ($useRest -and [string]::IsNullOrWhiteSpace($Project)) {
    throw "No Bitbucket project key. Pass -Project <KEY>, set `$env:BITBUCKET_PROJECT, or use -Url (the key is read from the link)."
}
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
            headCommit   = $pr.fromRef.latestCommit
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
                # -join: git returns the body as string[], which would serialise as a
                # JSON array instead of the description string every reviewer expects.
                description  = ((git log -1 --pretty=%b $src) -join "`n")
                author       = (git log -1 --pretty=%an $src)
                reviewers    = @()
                sourceBranch = $SourceBranch
                targetBranch = $TargetBranch
                headCommit   = (git rev-parse $src)
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

# --- Previous reviews posted by this system (round 2+ detection) -------------------------------------
# Bitbucket Server exposes PR comments through /activities (action = COMMENTED). We keep only comments
# that look like one of our review reports, newest last, so a follow-up round can recover its agenda.
$previousReviews = @()
if ($useRest -and -not $NoPreviousReviews) {
    try {
        $start = 0
        do {
            $acts = Invoke-Bitbucket -Uri ("{0}/activities?limit=100&start={1}" -f $restBase, $start)
            foreach ($a in $acts.values) {
                if ($a.action -ne 'COMMENTED' -or -not $a.comment) { continue }
                $text = [string]$a.comment.text
                if ($text -notmatch '(?m)^\s*<!--\s*ai-autopilot' -and $text -notmatch '(?m)^#\s*PR Review\b') { continue }
                $previousReviews += [pscustomobject]@{
                    commentId   = $a.comment.id
                    author      = $a.comment.author.displayName
                    createdDate = $a.comment.createdDate
                    text        = $text
                }
            }
            $start = $acts.nextPageStart
        } while (-not $acts.isLastPage)
        # Newest last; keep the most recent few so the agent isn't fed every historical round.
        $previousReviews = @($previousReviews | Sort-Object createdDate | Select-Object -Last $PreviousReviewLimit)
    }
    catch {
        Write-Warning "Could not read PR comments ($($_.Exception.Message)). Follow-up mode will not have a previous review to work from."
    }
}

Write-Output "===== PR METADATA ====="
$meta | ConvertTo-Json -Depth 6
Write-Output ""
Write-Output "===== PREVIOUS REVIEWS ====="
if ($previousReviews.Count -gt 0) {
    Write-Output ("Found {0} previous review comment(s) — this is a FOLLOW-UP review (round {1})." -f $previousReviews.Count, ($previousReviews.Count + 1))
    $previousReviews | ConvertTo-Json -Depth 6
}
else {
    Write-Output "none — this is a FIRST review."
}
Write-Output ""
Write-Output "===== CHANGED FILES ====="
$changedFiles
Write-Output ""
Write-Output "===== DIFFSTAT ====="
$diffStat
Write-Output ""
Write-Output "===== UNIFIED DIFF ====="
$diff
