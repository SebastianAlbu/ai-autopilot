<#
.SYNOPSIS
    Reads a Jenkins build: result and cause, pipeline stages, failed tests, or the job/build listing.

.DESCRIPTION
    Read-only CI triage. It inspects builds; it never triggers, stops or reconfigures anything.

    A TARGET is either a job path relative to $env:JENKINS_ROOT_JOB (nested folders separated by '/',
    e.g. 'MyComponent/main') or a full Jenkins URL pasted from the browser.
    A SELECTOR is a build number or a symbolic name (lastBuild, lastFailedBuild, ...). Default: lastBuild.

    Configuration (never hardcode hostnames or secrets) — see JenkinsCommon.ps1:
      JENKINS_BASE_URL, JENKINS_ROOT_JOB, JENKINS_USER + JENKINS_TOKEN (or JENKINS_AUTH='user:token'),
      JENKINS_VERIFY_SSL.

    Jenkins authenticates with HTTP Basic auth where the API token replaces the password — your real
    login password is never used. Create one under your name -> Configure -> API Token.

.PARAMETER Target
    Job path relative to the root folder, or a full Jenkins URL. Optional only with -ListJobs.

.PARAMETER Selector
    Build number or symbolic selector. Defaults to lastBuild. Ignored if the target already names a build.

.PARAMETER Stages
    List the pipeline stages and flag the FAILED/UNSTABLE one (Pipeline Stage View API).

.PARAMETER Tests
    List the failed test cases with their first error line.

.PARAMETER ListBuilds
    List recent builds of the job with their results instead of inspecting one build.

.PARAMETER ListJobs
    List the jobs in a folder (the root folder when -Target is omitted).

.PARAMETER Limit
    How many entries -ListBuilds returns. Defaults to 10.

.PARAMETER Json
    Emit raw JSON instead of the human-readable summary.

.EXAMPLE
    pwsh ./Get-JenkinsBuild.ps1 -Target MyComponent/main -Selector lastFailedBuild

.EXAMPLE
    pwsh ./Get-JenkinsBuild.ps1 -Target MyComponent/main -Selector lastFailedBuild -Stages

.EXAMPLE
    pwsh ./Get-JenkinsBuild.ps1 -Target MyComponent/main -Selector lastFailedBuild -Tests

.EXAMPLE
    pwsh ./Get-JenkinsBuild.ps1 -ListJobs
#>
[CmdletBinding()]
param(
    [string]$Target,
    [string]$Selector,
    [switch]$Stages,
    [switch]$Tests,
    [switch]$ListBuilds,
    [switch]$ListJobs,
    [int]$Limit = 10,
    [switch]$Json,

    [string]$BaseUrl,
    [string]$RootJob,
    [string]$User,
    [string]$Token
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JenkinsCommon.ps1')
Initialize-JenkinsContext -BaseUrl $BaseUrl -RootJob $RootJob -User $User -Token $Token

if (-not $Target -and -not $ListJobs) {
    throw "No -Target. Pass a job path (e.g. 'MyComponent/main') or a full Jenkins URL, or use -ListJobs to browse."
}

# --- Discovery modes --------------------------------------------------------------------------------
if ($ListJobs) {
    $data = Invoke-Jenkins -Uri ('{0}/api/json?tree=jobs[name,color,url]' -f (Get-JenkinsJobUrl -Target $Target))
    if ($Json) { return ($data | ConvertTo-Json -Depth 6) }
    if (-not $data.jobs) { return "No jobs in this folder." }
    # Jenkins encodes the last build's status in 'color': blue = ok, red = failed, yellow = unstable.
    foreach ($j in $data.jobs) {
        $status = switch -Regex ("$($j.color)") {
            '^blue'   { 'OK' }
            '^red'    { 'FAILED' }
            '^yellow' { 'UNSTABLE' }
            '^disabled|^notbuilt' { 'not built' }
            default   { "$($j.color)" }
        }
        Write-Output ('{0,-40} {1}' -f $j.name, $status)
    }
    return
}

if ($ListBuilds) {
    $uri  = '{0}/api/json?tree=builds[number,result,timestamp,duration]{{0,{1}}}' -f (Get-JenkinsJobUrl -Target $Target), $Limit
    $data = Invoke-Jenkins -Uri $uri
    if ($Json) { return ($data | ConvertTo-Json -Depth 6) }
    if (-not $data.builds) { return "No builds for this job." }
    foreach ($b in $data.builds) {
        $when = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$b.timestamp).LocalDateTime
        Write-Output ('#{0,-6} {1,-10} {2}  ({3})' -f $b.number, ($b.result ?? 'RUNNING'), $when.ToString('yyyy-MM-dd HH:mm'), (Format-JenkinsDuration -Milliseconds $b.duration))
    }
    return
}

# --- One build --------------------------------------------------------------------------------------
$buildUrl = Get-JenkinsBuildUrl -Target $Target -Selector $Selector

if ($Stages) {
    # The Pipeline Stage View API exists only for Pipeline jobs; freestyle jobs return 404.
    $wf = Invoke-Jenkins -Uri ('{0}/wfapi/describe' -f $buildUrl) -Optional
    if ($null -eq $wf) { return "No stage data — this is not a Pipeline job (or the Pipeline Stage View plugin is absent). Use -Tests or Get-JenkinsLog.ps1 instead." }
    if ($Json) { return ($wf | ConvertTo-Json -Depth 8) }
    Write-Output ("Stages of {0} [{1}]`n" -f $wf.name, $wf.status)
    foreach ($s in $wf.stages) {
        $flag = $(if ("$($s.status)" -in @('FAILED', 'UNSTABLE')) { '  <== FAILED HERE' } else { '' })
        Write-Output ('{0,-40} {1,-10} {2}{3}' -f $s.name, $s.status, (Format-JenkinsDuration -Milliseconds $s.durationMillis), $flag)
    }
    return
}

if ($Tests) {
    # No test report when the build failed before the tests ran — that is information, not an error.
    $report = Invoke-Jenkins -Uri ('{0}/testReport/api/json' -f $buildUrl) -Optional
    if ($null -eq $report) { return "No test report for this build — it probably failed before the tests ran." }
    if ($Json) { return ($report | ConvertTo-Json -Depth 8) }

    $failed = @(
        foreach ($suite in @($report.suites)) {
            foreach ($case in @($suite.cases)) {
                if ("$($case.status)" -in @('FAILED', 'REGRESSION')) { $case }
            }
        }
    )
    Write-Output ("Tests: {0} failed, {1} skipped, {2} total`n" -f $report.failCount, $report.skipCount, ($report.passCount + $report.failCount + $report.skipCount))
    if ($failed.Count -eq 0) { return }
    foreach ($c in $failed) {
        $first = (("$($c.errorDetails)" -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
        Write-Output ('FAILED {0}.{1}' -f $c.className, $c.name)
        if ($first) { Write-Output ('       {0}' -f $first.Trim()) }
    }
    return
}

$build = Invoke-Jenkins -Uri ('{0}/api/json' -f $buildUrl)
if ($Json) { return ($build | ConvertTo-Json -Depth 8) }

$causes = @(
    foreach ($action in @($build.actions)) {
        foreach ($cause in @($action.causes)) {
            if ($cause.shortDescription) { $cause.shortDescription }
        }
    }
)
$started = $(if ($build.timestamp) { [DateTimeOffset]::FromUnixTimeMilliseconds([long]$build.timestamp).LocalDateTime.ToString('yyyy-MM-dd HH:mm') } else { 'n/a' })

Write-Output ("{0}" -f $build.fullDisplayName)
Write-Output ("  result:   {0}" -f ($build.result ?? 'RUNNING'))
Write-Output ("  started:  {0}" -f $started)
Write-Output ("  duration: {0}" -f (Format-JenkinsDuration -Milliseconds $build.duration))
Write-Output ("  cause:    {0}" -f $(if ($causes.Count) { $causes -join '; ' } else { 'n/a' }))
Write-Output ("  url:      {0}" -f $build.url)
