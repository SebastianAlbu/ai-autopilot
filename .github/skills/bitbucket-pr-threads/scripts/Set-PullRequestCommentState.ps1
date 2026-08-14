<#
.SYNOPSIS
    Resolves or reopens a Bitbucket Data Center pull request comment thread.

.DESCRIPTION
    Marks a PR comment thread RESOLVED (or reopens it as OPEN).

    Resolving *edits* the comment, so Bitbucket requires the comment's current `version`:
    the script fetches it first (GET .../comments/{id}) and then sends
    PUT .../comments/{id} { version, state }. A 409 means the version went stale between the
    two calls (someone edited the thread) — the script re-fetches and retries once.

    THIS IS A WRITE ACTION. Use -DryRun to preview; -WhatIf/-Confirm are supported.

    Authentication (never hardcode secrets):
      - -Token <PAT>            Authorization: Bearer (needs Repository/PR WRITE permission)
      - $env:BITBUCKET_PAT      used if -Token is omitted
      - -UseDefaultCredentials  domain SSO (NTLM/Kerberos)

.PARAMETER Url
    A Bitbucket PR URL, e.g. https://bitbucket.example.com/projects/PROJ/repos/my-repo/pull-requests/42/overview

.PARAMETER PullRequestId
    Numeric PR id (with -Repo and optional -Project) instead of -Url.

.PARAMETER Repo
    Repository slug (id mode).

.PARAMETER Project
    Bitbucket project key. Taken from -Url when given; otherwise set it explicitly (or via BITBUCKET_PROJECT).

.PARAMETER CommentId
    The id of the THREAD ROOT comment (the first `#<id>` of a thread in Get-PullRequestComments.ps1).
    Passing the id of a reply returns 404 — replies have no resolution state of their own.

.PARAMETER State
    RESOLVED (default) or OPEN.

.PARAMETER DryRun
    Print the payload that WOULD be sent and exit without calling the API.

.EXAMPLE
    pwsh ./Set-PullRequestCommentState.ps1 -Url <pr-url> -CommentId 1234 -State RESOLVED -DryRun

.EXAMPLE
    pwsh ./Set-PullRequestCommentState.ps1 -PullRequestId 42 -Repo my-repo -CommentId 1234 -State OPEN
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium', DefaultParameterSetName = 'Url')]
param(
    [Parameter(ParameterSetName = 'Url', Mandatory = $true)]
    [string]$Url,

    [Parameter(ParameterSetName = 'Ids', Mandatory = $true)]
    [int]$PullRequestId,

    [Parameter(ParameterSetName = 'Ids', Mandatory = $true)]
    [string]$Repo,

    [Parameter(ParameterSetName = 'Ids')]
    [string]$Project = $env:BITBUCKET_PROJECT,

    [Parameter(Mandatory = $true)]
    [int]$CommentId,

    [ValidateSet('RESOLVED', 'OPEN')]
    [string]$State = 'RESOLVED',

    [string]$BaseUrl = $(if ($env:BITBUCKET_BASE_URL) { $env:BITBUCKET_BASE_URL } else { 'https://bitbucket.example.com' }),
    [string]$Token = $env:BITBUCKET_PAT,
    [switch]$UseDefaultCredentials,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# --- Resolve the PR coordinates ---------------------------------------------------------------------
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

if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "No Bitbucket project key. Pass -Project <KEY>, set `$env:BITBUCKET_PROJECT, or use -Url (the key is read from the link)."
}

$commentUri = '{0}/rest/api/1.0/projects/{1}/repos/{2}/pull-requests/{3}/comments/{4}' -f `
    $BaseUrl.TrimEnd('/'), $Project, $Repo, $PullRequestId, $CommentId

# --- HTTP -------------------------------------------------------------------------------------------
function Invoke-Bitbucket {
    param([string]$Method, [hashtable]$Body)
    $headers = @{ Accept = 'application/json'; 'Content-Type' = 'application/json' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{ Uri = $commentUri; Method = $Method; Headers = $headers; UseBasicParsing = $true }
    if ($Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 4 -Compress) }
    if ($UseDefaultCredentials) { $params['UseDefaultCredentials'] = $true }
    return Invoke-RestMethod @params
}

function Get-CommentVersion {
    try {
        return [int](Invoke-Bitbucket -Method 'GET').version
    }
    catch {
        if ("$($_.Exception.Message)" -match '404') {
            throw "Comment #$CommentId not found on PR #$PullRequestId. A 404 here usually means the id is a REPLY, not the thread root — only the root carries the thread state."
        }
        throw
    }
}

# --- Dry run ----------------------------------------------------------------------------------------
if ($DryRun) {
    Write-Output "DRY RUN — nothing will be changed. Target: PUT $commentUri"
    Write-Output (@{ version = '<current version, fetched first>'; state = $State } | ConvertTo-Json)
    return
}

if (-not $Token -and -not $UseDefaultCredentials) {
    throw "No credentials. Set `$env:BITBUCKET_PAT (with write permission) or pass -UseDefaultCredentials."
}

if (-not $PSCmdlet.ShouldProcess("comment #$CommentId on PR #$PullRequestId", "set state to $State")) { return }

# --- Fetch version, then update (retry once on a stale version) --------------------------------------
$version = Get-CommentVersion
try {
    Invoke-Bitbucket -Method 'PUT' -Body @{ version = $version; state = $State } | Out-Null
}
catch {
    if ("$($_.Exception.Message)" -notmatch '409') { throw }
    Write-Verbose "409 Conflict — the comment version was stale; re-fetching and retrying once."
    $version = Get-CommentVersion
    Invoke-Bitbucket -Method 'PUT' -Body @{ version = $version; state = $State } | Out-Null
}

Write-Output ("Comment #{0} on PR #{1} is now {2}." -f $CommentId, $PullRequestId, $State)
