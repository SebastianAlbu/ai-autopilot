<#
.SYNOPSIS
    Reads a Jira ticket from a Jira Server / Data Center instance and prints its key fields as JSON.

.DESCRIPTION
    Calls <base-url>/rest/api/2/issue/{key} (REST v2). This reader supports a
    modern Personal Access Token (Bearer) as well, and never hardcodes credentials.

    Auth precedence (highest first):
      1. -Token <pat>          -> Authorization: Bearer
      2. $env:JIRA_PAT         -> Authorization: Bearer
      3. -User + -Password     -> Authorization: Basic
      4. -UseDefaultCredentials-> domain SSO

.PARAMETER TicketKey
    The Jira issue key, e.g. PROJ-123.

.PARAMETER Url
    A Jira URL (e.g. https://jira.example.com/browse/PROJ-123); the key is extracted automatically.

.PARAMETER Fields
    Comma-separated Jira fields to request.

.EXAMPLE
    pwsh ./Get-JiraTicket.ps1 -TicketKey PROJ-123

.EXAMPLE
    pwsh ./Get-JiraTicket.ps1 -Url https://jira.example.com/browse/PROJ-123 -Token $env:JIRA_PAT
#>
[CmdletBinding(DefaultParameterSetName = 'Key')]
param(
    [Parameter(ParameterSetName = 'Key', Mandatory = $true, Position = 0)]
    [string]$TicketKey,

    [Parameter(ParameterSetName = 'Url', Mandatory = $true)]
    [string]$Url,

    [string]$BaseUrl = $(if ($env:JIRA_BASE_URL) { $env:JIRA_BASE_URL } else { 'https://jira.example.com' }),
    [string]$Token = $env:JIRA_PAT,
    [string]$User,
    [string]$Password,
    [switch]$UseDefaultCredentials,
    [string]$Fields = 'summary,description,issuetype,status,priority,labels,assignee,reporter,resolution,fixVersions,created,updated,comment'
)

$ErrorActionPreference = 'Stop'

if ($PSCmdlet.ParameterSetName -eq 'Url') {
    $m = [regex]::Match($Url, '[A-Z][A-Z0-9]+-\d+')
    if (-not $m.Success) { throw "Could not extract a Jira issue key from URL: $Url" }
    $TicketKey = $m.Value
}

$endpoint = '{0}/rest/api/2/issue/{1}?fields={2}' -f $BaseUrl.TrimEnd('/'), $TicketKey, $Fields

$headers = @{ Accept = 'application/json' }
if ($Token) {
    $headers['Authorization'] = "Bearer $Token"
}
elseif ($User -and $Password) {
    $pair = '{0}:{1}' -f $User, $Password
    $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
    $headers['Authorization'] = "Basic $b64"
}

$rest = @{ Uri = $endpoint; Headers = $headers; Method = 'GET'; UseBasicParsing = $true }
if ($UseDefaultCredentials) { $rest['UseDefaultCredentials'] = $true }

try {
    $resp = Invoke-RestMethod @rest
}
catch {
    Write-Error "Jira request failed for '$TicketKey': $($_.Exception.Message). Check the key and that JIRA_PAT (or -User/-Password) is set."
    exit 1
}

$f = $resp.fields
[pscustomobject]@{
    key         = $resp.key
    url         = '{0}/browse/{1}' -f $BaseUrl.TrimEnd('/'), $resp.key
    summary     = $f.summary
    type        = $f.issuetype.name
    status      = $f.status.name
    priority    = $f.priority.name
    resolution  = if ($f.resolution) { $f.resolution.name } else { 'Unresolved' }
    labels      = $f.labels
    assignee    = if ($f.assignee) { $f.assignee.displayName } else { 'Unassigned' }
    reporter    = if ($f.reporter) { $f.reporter.displayName } else { $null }
    created     = $f.created
    updated     = $f.updated
    description = $f.description
    comments    = @($f.comment.comments | ForEach-Object { '{0}: {1}' -f $_.author.displayName, $_.body })
} | ConvertTo-Json -Depth 8
