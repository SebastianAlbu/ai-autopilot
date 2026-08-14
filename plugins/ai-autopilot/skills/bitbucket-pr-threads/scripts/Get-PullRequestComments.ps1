<#
.SYNOPSIS
    Reads the review comment threads of a Bitbucket Data Center pull request.

.DESCRIPTION
    Lists every comment thread on a PR — inline (anchored to file:line) and general — with the thread
    state (OPEN / RESOLVED / PENDING), the "task" flag, every reply, and the comment ids you need to
    reply (Add-PullRequestComment.ps1 -ReplyTo) or resolve (Set-PullRequestCommentState.ps1).

    Read-only. Point at the PR with a URL or with id+repo(+project).

    Bitbucket Server exposes comments through the PR *activities* feed
    (GET .../pull-requests/{id}/activities, action = COMMENTED). Two properties of that feed matter:
      * It emits one COMMENTED entry per comment INCLUDING replies, and every entry already carries the
        full current reply tree. A reply therefore appears twice — nested under its parent and as its own
        entry. This script keeps only thread roots (comments that are nobody's reply) so threads are not
        listed twice.
      * The ROOT comment carries the thread's state; replies do not. 'severity = BLOCKER' is what the
        Bitbucket UI calls a TASK — treat those as must-address.

    Authentication (never hardcode secrets):
      - -Token <PAT>            Authorization: Bearer (read permission is enough)
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

.PARAMETER Unresolved
    Only threads whose root state is not RESOLVED — i.e. what still needs attention.

.PARAMETER Tasks
    Only threads whose root has severity BLOCKER (the Bitbucket UI's "task").

.PARAMETER Author
    Only threads whose root comment was written by this author (substring, case-insensitive).

.PARAMETER Json
    Emit the threads as JSON instead of the human-readable listing.

.EXAMPLE
    pwsh ./Get-PullRequestComments.ps1 -Url <pr-url> -Unresolved

.EXAMPLE
    pwsh ./Get-PullRequestComments.ps1 -PullRequestId 42 -Repo my-repo -Tasks -Json
#>
[CmdletBinding(DefaultParameterSetName = 'Url')]
param(
    [Parameter(ParameterSetName = 'Url', Mandatory = $true)]
    [string]$Url,

    [Parameter(ParameterSetName = 'Ids', Mandatory = $true)]
    [int]$PullRequestId,

    [Parameter(ParameterSetName = 'Ids', Mandatory = $true)]
    [string]$Repo,

    [Parameter(ParameterSetName = 'Ids')]
    [string]$Project = $env:BITBUCKET_PROJECT,

    [switch]$Unresolved,
    [switch]$Tasks,
    [string]$Author,
    [switch]$Json,

    [string]$BaseUrl = $(if ($env:BITBUCKET_BASE_URL) { $env:BITBUCKET_BASE_URL } else { 'https://bitbucket.example.com' }),
    [string]$Token = $env:BITBUCKET_PAT,
    [switch]$UseDefaultCredentials
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

$restBase = '{0}/rest/api/1.0/projects/{1}/repos/{2}/pull-requests/{3}' -f `
    $BaseUrl.TrimEnd('/'), $Project, $Repo, $PullRequestId

# --- HTTP -------------------------------------------------------------------------------------------
function Invoke-Bitbucket {
    param([string]$Uri)
    $headers = @{ Accept = 'application/json' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $params = @{ Uri = $Uri; Headers = $headers; Method = 'GET'; UseBasicParsing = $true }
    if ($UseDefaultCredentials) { $params['UseDefaultCredentials'] = $true }
    return Invoke-RestMethod @params
}

# --- Comment tree helpers ---------------------------------------------------------------------------
function Get-ReplyId {
    <# Every comment id strictly below this one (its replies, recursively). #>
    param($Comment)
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($reply in @($Comment.comments)) {
        if (-not $reply) { continue }
        $ids.Add([int]$reply.id)
        foreach ($nested in (Get-ReplyId -Comment $reply)) { $ids.Add($nested) }
    }
    return $ids
}

function ConvertTo-CommentRow {
    <# Flatten a comment and its nested replies into display rows (depth-ordered). #>
    param($Comment, $Anchor, [int]$Depth = 0)
    $rows = New-Object System.Collections.Generic.List[object]
    $rows.Add([pscustomobject]@{
        id       = $Comment.id
        version  = $Comment.version
        depth    = $Depth
        author   = $(if ($Comment.author.displayName) { $Comment.author.displayName } else { '?' })
        state    = [string]$Comment.state       # OPEN | RESOLVED | PENDING (root carries the thread state)
        severity = [string]$Comment.severity    # NORMAL | BLOCKER (BLOCKER == "task")
        text     = ([string]$Comment.text).Trim()
        path     = $Anchor.path
        line     = $Anchor.line
        lineType = $Anchor.lineType
    })
    foreach ($reply in @($Comment.comments)) {
        if (-not $reply) { continue }
        foreach ($row in (ConvertTo-CommentRow -Comment $reply -Anchor $null -Depth ($Depth + 1))) { $rows.Add($row) }
    }
    return $rows
}

# --- Collect the threads ----------------------------------------------------------------------------
$candidates = New-Object System.Collections.Generic.List[object]
$replyIds   = New-Object System.Collections.Generic.HashSet[int]

$start = 0
do {
    $acts = Invoke-Bitbucket -Uri ("{0}/activities?limit=100&start={1}" -f $restBase, $start)
    foreach ($a in @($acts.values)) {
        if ($a.action -ne 'COMMENTED' -or -not $a.comment) { continue }
        $anchor = $(if ($a.commentAnchor) { $a.commentAnchor } else { $a.comment.anchor })
        $candidates.Add([pscustomobject]@{ comment = $a.comment; anchor = $anchor })
        foreach ($id in (Get-ReplyId -Comment $a.comment)) { [void]$replyIds.Add($id) }
    }
    $start = $acts.nextPageStart
} while (-not $acts.isLastPage)

$threads = New-Object System.Collections.Generic.List[object]
foreach ($c in $candidates) {
    if ($replyIds.Contains([int]$c.comment.id)) { continue }   # a reply, already shown under its root
    $threads.Add(@(ConvertTo-CommentRow -Comment $c.comment -Anchor $c.anchor))
}

# --- Filters ----------------------------------------------------------------------------------------
$filtered = @($threads)
if ($Unresolved) { $filtered = @($filtered | Where-Object { $_[0].state -ne 'RESOLVED' }) }
if ($Tasks)      { $filtered = @($filtered | Where-Object { $_[0].severity -eq 'BLOCKER' }) }
if ($Author)     { $filtered = @($filtered | Where-Object { $_[0].author -like "*$Author*" }) }

# --- Output -----------------------------------------------------------------------------------------
if ($Json) {
    [pscustomobject]@{ pullRequest = $PullRequestId; threads = $filtered } | ConvertTo-Json -Depth 8
    return
}

$scope = $(if ($Unresolved) { 'unresolved ' } else { '' })
if ($filtered.Count -eq 0) {
    Write-Output ("PR #{0}: no {1}review comments." -f $PullRequestId, $scope)
    return
}

Write-Output ("PR #{0}: {1} {2}comment thread(s)`n" -f $PullRequestId, $filtered.Count, $scope)
foreach ($t in $filtered) {
    $root = $t[0]
    $loc  = $(if ($root.path) { '{0}:{1}' -f $root.path, $root.line } else { 'GENERAL' })
    $tags = @()
    if ($root.severity -eq 'BLOCKER') { $tags += 'TASK' }
    $tags += $(if ($root.state) { $root.state } else { 'OPEN' })
    Write-Output ("=== [{0}] [{1}]" -f $loc, ($tags -join '/'))
    foreach ($row in $t) {
        $indent = '  ' + ('    ' * $row.depth)
        $body   = $row.text -replace "`n", ("`n" + $indent + '   ')
        Write-Output ("{0}#{1} v{2} {3}: {4}" -f $indent, $row.id, $row.version, $row.author, $body)
    }
    Write-Output ('-' * 60)
}

Write-Output ""
Write-Output "Reply:   pwsh ../../bitbucket-pr-comment/scripts/Add-PullRequestComment.ps1 -Url <pr-url> -ReplyTo <commentId> -Text '...'"
Write-Output "Resolve: pwsh ./Set-PullRequestCommentState.ps1 -Url <pr-url> -CommentId <commentId> -State RESOLVED"
