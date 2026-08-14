<#
.SYNOPSIS
    Posts a review to a Bitbucket Data Center pull request: a general comment and/or inline comments.

.DESCRIPTION
    Calls POST /rest/api/1.0/projects/{key}/repos/{slug}/pull-requests/{id}/comments on
    a Bitbucket Server / Data Center instance. Point at the PR with a URL or with id+repo(+project).

    THIS IS A WRITE ACTION. Use -DryRun to preview the exact payload without posting. The script also
    supports -WhatIf/-Confirm (ShouldProcess). Always preview and confirm before posting for real.

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

.PARAMETER Text
    The comment body (markdown). Mutually usable with -File (one of them for a summary comment).

.PARAMETER File
    Path to a file whose contents become the comment body.

.PARAMETER InlineFindings
    Path to a JSON file: an array of { path, line, lineType (ADDED|REMOVED|CONTEXT), text }.
    Each becomes an inline comment anchored to that file:line.

.PARAMETER ReplyTo
    Optional parent comment id, to post the comment as a threaded reply.

.PARAMETER DryRun
    Print the payload(s) that WOULD be posted and exit without calling the API.

.EXAMPLE
    pwsh ./Add-PullRequestComment.ps1 -Url <pr-url> -File review.md -DryRun

.EXAMPLE
    pwsh ./Add-PullRequestComment.ps1 -Url <pr-url> -File review.md

.EXAMPLE
    pwsh ./Add-PullRequestComment.ps1 -PullRequestId 42 -Repo my-repo -InlineFindings findings.json
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High', DefaultParameterSetName = 'Url')]
param(
    [Parameter(ParameterSetName = 'Url', Mandatory = $true)]
    [string]$Url,

    [Parameter(ParameterSetName = 'Ids', Mandatory = $true)]
    [int]$PullRequestId,

    [Parameter(ParameterSetName = 'Ids', Mandatory = $true)]
    [string]$Repo,

    [Parameter(ParameterSetName = 'Ids')]
    [string]$Project = $env:BITBUCKET_PROJECT,

    [string]$Text,
    [string]$File,
    [string]$InlineFindings,
    [int]$ReplyTo,

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

$endpoint = '{0}/rest/api/1.0/projects/{1}/repos/{2}/pull-requests/{3}/comments' -f `
    $BaseUrl.TrimEnd('/'), $Project, $Repo, $PullRequestId
$overview = '{0}/projects/{1}/repos/{2}/pull-requests/{3}/overview' -f `
    $BaseUrl.TrimEnd('/'), $Project, $Repo, $PullRequestId

# --- Load the comment text --------------------------------------------------------------------------
if ($File) {
    if (-not (Test-Path -LiteralPath $File)) { throw "Comment file not found: $File" }
    $Text = Get-Content -LiteralPath $File -Raw
}

$inline = @()
if ($InlineFindings) {
    if (-not (Test-Path -LiteralPath $InlineFindings)) { throw "Inline findings file not found: $InlineFindings" }
    $inline = @(Get-Content -LiteralPath $InlineFindings -Raw | ConvertFrom-Json)
}

if (-not $Text -and $inline.Count -eq 0) {
    throw "Nothing to post. Provide -Text, -File, or -InlineFindings."
}

# --- Build the payloads -----------------------------------------------------------------------------
function New-CommentPayload {
    param([string]$Body, [hashtable]$Anchor, [int]$Parent)
    $payload = @{ text = $Body }
    if ($Anchor) { $payload['anchor'] = $Anchor }
    if ($Parent) { $payload['parent'] = @{ id = $Parent } }
    return $payload
}

$jobs = New-Object System.Collections.Generic.List[hashtable]

if ($Text) {
    $jobs.Add(@{ Label = 'summary comment'; Payload = (New-CommentPayload -Body $Text -Parent $ReplyTo) })
}

foreach ($f in $inline) {
    $lineType = if ($f.lineType) { ([string]$f.lineType).ToUpper() } else { 'ADDED' }
    $fileType = if ($lineType -eq 'REMOVED') { 'FROM' } else { 'TO' }
    $anchor = @{
        diffType = 'EFFECTIVE'
        line     = [int]$f.line
        lineType = $lineType
        fileType = $fileType
        path     = [string]$f.path
    }
    $jobs.Add(@{ Label = ('inline {0}:{1}' -f $f.path, $f.line); Payload = (New-CommentPayload -Body $f.text -Anchor $anchor) })
}

# --- Auth / request helper --------------------------------------------------------------------------
function Invoke-Post {
    param([hashtable]$Body)
    $headers = @{ Accept = 'application/json'; 'Content-Type' = 'application/json' }
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }
    $json = $Body | ConvertTo-Json -Depth 8 -Compress
    $params = @{ Uri = $endpoint; Method = 'POST'; Headers = $headers; Body = $json; UseBasicParsing = $true }
    if ($UseDefaultCredentials) { $params['UseDefaultCredentials'] = $true }
    return Invoke-RestMethod @params
}

# --- Dry run: show, don't post ----------------------------------------------------------------------
if ($DryRun) {
    Write-Output "DRY RUN — nothing will be posted. Target: $endpoint"
    foreach ($j in $jobs) {
        Write-Output ("`n--- {0} ---" -f $j.Label)
        $j.Payload | ConvertTo-Json -Depth 8
    }
    Write-Output ("`n{0} comment(s) would be posted." -f $jobs.Count)
    return
}

if (-not $Token -and -not $UseDefaultCredentials) {
    throw "No credentials. Set `$env:BITBUCKET_PAT (with write permission) or pass -UseDefaultCredentials."
}

# --- Post -------------------------------------------------------------------------------------------
$posted = 0; $failed = 0
foreach ($j in $jobs) {
    if (-not $PSCmdlet.ShouldProcess($j.Label, "POST comment to PR #$PullRequestId")) { continue }
    try {
        $resp = Invoke-Post -Body $j.Payload
        $posted++
        Write-Output ("Posted {0} (commentId={1}) -> {2}?commentId={1}" -f $j.Label, $resp.id, $overview)
    }
    catch {
        $failed++
        Write-Warning ("Failed to post {0}: {1}" -f $j.Label, $_.Exception.Message)
    }
}

Write-Output ("`nDone: {0} posted, {1} failed." -f $posted, $failed)
if ($failed -gt 0) { exit 1 }
