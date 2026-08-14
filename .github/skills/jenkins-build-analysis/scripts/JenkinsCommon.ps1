<#
.SYNOPSIS
    Shared helpers for the Jenkins build-analysis scripts. Dot-source it; it runs nothing on its own.

.DESCRIPTION
    URL building, authentication, HTTP and log rendering for Get-JenkinsBuild.ps1 and Get-JenkinsLog.ps1.

    Configuration (never hardcode hostnames or secrets):
      JENKINS_BASE_URL   Jenkins root, e.g. https://jenkins.example.com
      JENKINS_ROOT_JOB   optional folder every relative target hangs under, e.g. 'SPLE' or 'team/ci'
      JENKINS_USER +     Jenkins uses HTTP Basic auth where the API TOKEN replaces the password
      JENKINS_TOKEN      (your real login password is never used)
      JENKINS_AUTH       alternative single value, 'user:token'
      JENKINS_VERIFY_SSL set to 'false' to skip TLS verification (corporate CA not in the trust store)
#>

$script:JenkinsBaseUrl = $null
$script:JenkinsRootJob = $null
$script:JenkinsHeaders = $null
$script:JenkinsSkipCertCheck = $false

$script:JenkinsKnownSelectors = @(
    'lastBuild', 'lastCompletedBuild', 'lastFailedBuild',
    'lastStableBuild', 'lastSuccessfulBuild', 'lastUnsuccessfulBuild'
)

function Initialize-JenkinsContext {
    <# Resolve base URL, root folder and credentials once, before any request. #>
    param(
        [string]$BaseUrl,
        [string]$RootJob,
        [string]$User,
        [string]$Token
    )

    $script:JenkinsBaseUrl = $(
        if ($BaseUrl) { $BaseUrl }
        elseif ($env:JENKINS_BASE_URL) { $env:JENKINS_BASE_URL }
        else { 'https://jenkins.example.com' }
    ).TrimEnd('/')

    $script:JenkinsRootJob = $(if ($PSBoundParameters.ContainsKey('RootJob') -and $null -ne $RootJob) { $RootJob } else { $env:JENKINS_ROOT_JOB })

    if (-not $User)  { $User  = $env:JENKINS_USER }
    if (-not $Token) { $Token = $env:JENKINS_TOKEN }
    if ((-not $User -or -not $Token) -and $env:JENKINS_AUTH -match '^([^:]+):(.+)$') {
        $User  = $Matches[1]
        $Token = $Matches[2]
    }

    $script:JenkinsHeaders = @{ Accept = 'application/json' }
    if ($User -and $Token) {
        $pair = '{0}:{1}' -f $User.Trim(), $Token.Trim()
        $b64  = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($pair))
        $script:JenkinsHeaders['Authorization'] = "Basic $b64"
    }

    $script:JenkinsSkipCertCheck = ($env:JENKINS_VERIFY_SSL -in @('false', 'False', '0', 'no'))
}

function Assert-JenkinsCredential {
    if (-not $script:JenkinsHeaders.ContainsKey('Authorization')) {
        throw "No Jenkins credentials. Set `$env:JENKINS_USER + `$env:JENKINS_TOKEN, or `$env:JENKINS_AUTH='user:token'. The token is created in Jenkins under your name -> Configure -> API Token."
    }
}

function Get-JenkinsJobUrl {
    <#
    Resolve a target to a job/folder URL.

    A full URL is used as is, minus any '/view/<name>' segments: pasted UI links to multibranch jobs carry
    view filters (.../job/pnd/view/change-requests/job/PR-832/) that are not part of the REST path.
    Otherwise the target is a path relative to JENKINS_ROOT_JOB, each segment wrapped in /job/.
    #>
    param([string]$Target)

    if ($Target -match '^https?://') {
        return ($Target -replace '/view/[^/]+', '').TrimEnd('/')
    }

    $segments = @(
        @($script:JenkinsRootJob -split '/'; $Target -split '/') |
            Where-Object { $_ -and $_.Trim() } |
            ForEach-Object { $_.Trim() }
    )
    # No target and no root folder: the Jenkins root itself, which is a valid folder to list.
    if ($segments.Count -eq 0) { return $script:JenkinsBaseUrl }

    return '{0}/job/{1}' -f $script:JenkinsBaseUrl, ($segments -join '/job/')
}

function Get-JenkinsBuildUrl {
    <#
    Resolve a target + selector to a build URL. A target that already ends in a build number or a symbolic
    selector is used as is; otherwise the selector (default 'lastBuild') is appended.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Selector
    )
    $base = (Get-JenkinsJobUrl -Target $Target).TrimEnd('/')
    $leaf = $base.Split('/')[-1]
    if ($leaf -in $script:JenkinsKnownSelectors -or $leaf -match '^\d+$') { return $base }
    if (-not $Selector) { $Selector = 'lastBuild' }
    return '{0}/{1}' -f $base, $Selector
}

function Invoke-Jenkins {
    <#
    GET a Jenkins URL. Returns parsed JSON, or raw text with -Raw.

    With -Optional a 404 returns $null instead of throwing — used for endpoints that may legitimately be
    absent (no stage API on a freestyle job, no test report when the build failed before the tests ran).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [switch]$Raw,
        [switch]$Optional
    )
    Assert-JenkinsCredential
    $params = @{ Uri = $Uri; Headers = $script:JenkinsHeaders; Method = 'GET'; UseBasicParsing = $true }
    if ($script:JenkinsSkipCertCheck) { $params['SkipCertificateCheck'] = $true }
    try {
        if ($Raw) { return (Invoke-WebRequest @params).Content }
        return Invoke-RestMethod @params
    }
    catch {
        $message = "$($_.Exception.Message)"
        $status  = $null
        if ($_.Exception.PSObject.Properties.Name -contains 'Response' -and $_.Exception.Response) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($status -eq 404 -or $message -match '\b404\b') {
            if ($Optional) { return $null }
            throw "HTTP 404 — no such job or build: $Uri"
        }
        if ($status -eq 401 -or $message -match '\b401\b') { throw "HTTP 401 — check `$env:JENKINS_USER and the API token." }
        if ($status -eq 403 -or $message -match '\b403\b') { throw "HTTP 403 — the API token lacks permission for this job." }
        throw
    }
}

function Format-JenkinsDuration {
    param([double]$Milliseconds)
    if (-not $Milliseconds) { return 'n/a' }
    $ts = [TimeSpan]::FromMilliseconds($Milliseconds)
    if ($ts.TotalHours -ge 1) { return '{0}h {1}m' -f [int]$ts.TotalHours, $ts.Minutes }
    if ($ts.TotalMinutes -ge 1) { return '{0}m {1}s' -f [int]$ts.TotalMinutes, $ts.Seconds }
    return '{0}s' -f [int]$ts.TotalSeconds
}

function ConvertFrom-JenkinsHtmlLog {
    <# The wfapi node-log endpoint returns HTML-annotated lines; /consoleText does not. #>
    param([string]$Text)
    if (-not $Text -or $Text -notmatch '<') { return $Text }
    return [System.Net.WebUtility]::HtmlDecode(($Text -replace '<[^>]+>', ''))
}

function Format-JenkinsLog {
    <#
    Render a log body: grep-filtered, full, or tail-limited (the default).
    Small by default on purpose — a console log can be megabytes, and dumping it buries the actual error.
    #>
    param(
        [string]$Text,
        [int]$Tail = 200,
        [switch]$Full,
        [string]$Grep
    )
    $lines = @(($Text -replace "`r`n", "`n") -split "`n")
    $total = $lines.Count

    if ($Grep) {
        try { $rx = [regex]::new($Grep, 'IgnoreCase') }
        catch { throw "Invalid -Grep regex '$Grep': $($_.Exception.Message)" }
        $matched = @($lines | Where-Object { $rx.IsMatch($_) })
        if ($matched.Count -eq 0) { return "(no lines match /$Grep/ in $total-line log)" }
        return ("# {0} of {1} log lines match /{2}/`n`n{3}" -f $matched.Count, $total, $Grep, ($matched -join "`n"))
    }

    if ($Full) { return $Text }

    $shown = @($lines | Select-Object -Last $Tail)
    $header = $(if ($total -gt $Tail) { "# showing last $Tail of $total log lines (use -Full or -Grep to see more)`n`n" } else { '' })
    return $header + ($shown -join "`n")
}
