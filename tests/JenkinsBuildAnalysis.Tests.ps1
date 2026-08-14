<#
    Tests for the jenkins-build-analysis skill.

    JenkinsCommon.ps1 only defines functions, so it can be dot-sourced and its URL/format helpers tested
    directly. The command scripts are invoked with & and mocked at the HTTP boundary.
#>

BeforeAll {
    $script:SkillRoot    = Join-Path $PSScriptRoot '..\.github\skills\jenkins-build-analysis\scripts'
    $script:BuildScript  = Join-Path $script:SkillRoot 'Get-JenkinsBuild.ps1'
    $script:LogScript    = Join-Path $script:SkillRoot 'Get-JenkinsLog.ps1'

    . (Join-Path $script:SkillRoot 'JenkinsCommon.ps1')
}

Describe 'JenkinsCommon URL building' {

    BeforeEach {
        Initialize-JenkinsContext -BaseUrl 'https://ci.example.com' -RootJob 'ROOT' -User 'u' -Token 't'
    }

    Context 'Get-JenkinsJobUrl' {

        It 'wraps every path segment in /job/ under the root folder' {
            Get-JenkinsJobUrl -Target 'MyComponent/main' |
                Should -Be 'https://ci.example.com/job/ROOT/job/MyComponent/job/main'
        }

        It 'returns the Jenkins root when there is no target and no root folder' {
            Initialize-JenkinsContext -BaseUrl 'https://ci.example.com' -RootJob '' -User 'u' -Token 't'
            Get-JenkinsJobUrl -Target '' | Should -Be 'https://ci.example.com'
        }

        It 'uses a full URL as given' {
            Get-JenkinsJobUrl -Target 'https://other.example.com/job/A/job/B/' |
                Should -Be 'https://other.example.com/job/A/job/B'
        }

        It 'strips the /view/<name> segments a pasted multibranch link carries' {
            Get-JenkinsJobUrl -Target 'https://ci.example.com/job/pnd/view/change-requests/job/PR-832/' |
                Should -Be 'https://ci.example.com/job/pnd/job/PR-832'
        }
    }

    Context 'Get-JenkinsBuildUrl' {

        It 'defaults to lastBuild' {
            Get-JenkinsBuildUrl -Target 'A' | Should -Be 'https://ci.example.com/job/ROOT/job/A/lastBuild'
        }

        It 'appends the requested selector' {
            Get-JenkinsBuildUrl -Target 'A' -Selector 'lastFailedBuild' |
                Should -Be 'https://ci.example.com/job/ROOT/job/A/lastFailedBuild'
        }

        It 'leaves a target that already names a build number alone' {
            Get-JenkinsBuildUrl -Target 'https://ci.example.com/job/A/431/' -Selector 'lastBuild' |
                Should -Be 'https://ci.example.com/job/A/431'
        }

        It 'leaves a target that already ends in a symbolic selector alone' {
            Get-JenkinsBuildUrl -Target 'https://ci.example.com/job/A/lastFailedBuild' |
                Should -Be 'https://ci.example.com/job/A/lastFailedBuild'
        }
    }

    Context 'Credentials' {

        It 'refuses to make a request with no token configured' {
            Initialize-JenkinsContext -BaseUrl 'https://ci.example.com' -RootJob '' -User '' -Token ''
            { Invoke-Jenkins -Uri 'https://ci.example.com/api/json' } | Should -Throw '*No Jenkins credentials*'
        }
    }
}

Describe 'JenkinsCommon log rendering' {

    BeforeAll {
        $script:log = (1..500 | ForEach-Object { "line $_" }) -join "`n"
    }

    It 'shows only the tail by default, and says so' {
        $out = Format-JenkinsLog -Text $script:log -Tail 10
        $out | Should -BeLike '*showing last 10 of 500 log lines*'
        $out | Should -BeLike '*line 500*'
        $out | Should -Not -BeLike '*line 489*'
    }

    It 'emits everything with -Full' {
        Format-JenkinsLog -Text $script:log -Full | Should -Be $script:log
    }

    It '-Grep keeps only matching lines and reports the count' {
        $out = Format-JenkinsLog -Text "ok`nERROR: boom`nok" -Grep 'error'
        $out | Should -BeLike '*1 of 3 log lines*'
        $out | Should -BeLike '*ERROR: boom*'
        $out | Should -Not -BeLike "*`nok*"
    }

    It '-Grep says so plainly when nothing matches' {
        Format-JenkinsLog -Text "a`nb" -Grep 'zzz' | Should -BeLike '*no lines match*'
    }

    It 'rejects an invalid -Grep regex with a usable message' {
        { Format-JenkinsLog -Text 'a' -Grep '[' } | Should -Throw '*Invalid -Grep regex*'
    }

    It 'strips the HTML annotation the wfapi node log returns' {
        ConvertFrom-JenkinsHtmlLog -Text '<span class="x">make: ***</span> &amp; done' |
            Should -Be 'make: *** & done'
    }

    It 'leaves plain console text untouched' {
        ConvertFrom-JenkinsHtmlLog -Text 'plain text' | Should -Be 'plain text'
    }
}

Describe 'Get-JenkinsBuild.ps1' {

    It 'requires a target unless listing jobs' {
        { & $script:BuildScript -User 'u' -Token 't' } | Should -Throw '*No -Target*'
    }

    It 'reports missing stage data instead of failing on a freestyle job' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 404 (Not Found).' }

        $out = & $script:BuildScript -Target 'A' -Stages -BaseUrl 'https://ci.example.com' -User 'u' -Token 't'

        "$out" | Should -BeLike '*not a Pipeline job*'
    }

    It 'reports a missing test report instead of failing' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 404 (Not Found).' }

        $out = & $script:BuildScript -Target 'A' -Tests -BaseUrl 'https://ci.example.com' -User 'u' -Token 't'

        "$out" | Should -BeLike '*failed before the tests ran*'
    }

    It 'flags the failed stage' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                name   = 'A'
                status = 'FAILED'
                stages = @(
                    [pscustomobject]@{ name = 'Checkout'; status = 'SUCCESS'; durationMillis = 1000 },
                    [pscustomobject]@{ name = 'Build';    status = 'FAILED';  durationMillis = 2000 }
                )
            }
        }

        $out = & $script:BuildScript -Target 'A' -Stages -BaseUrl 'https://ci.example.com' -User 'u' -Token 't'
        $joined = $out -join "`n"

        $joined | Should -BeLike '*Build*FAILED*<== FAILED HERE*'
        ($joined -split "`n" | Where-Object { $_ -like '*Checkout*' }) | Should -Not -BeLike '*FAILED HERE*'
    }

    It 'lists only the failed test cases' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{
                failCount = 1; skipCount = 0; passCount = 1
                suites = @([pscustomobject]@{ cases = @(
                    [pscustomobject]@{ className = 'T'; name = 'ok';  status = 'PASSED'; errorDetails = $null },
                    [pscustomobject]@{ className = 'T'; name = 'bad'; status = 'FAILED'; errorDetails = "expected 1`nat T.cs:9" }
                )})
            }
        }

        $joined = (& $script:BuildScript -Target 'A' -Tests -BaseUrl 'https://ci.example.com' -User 'u' -Token 't') -join "`n"

        $joined | Should -BeLike '*FAILED T.bad*'
        $joined | Should -BeLike '*expected 1*'
        $joined | Should -Not -BeLike '*T.ok*'
    }
}

Describe 'Get-JenkinsLog.ps1' {

    It 'falls back to the console log when the build has no stages' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 404 (Not Found).' }
        Mock Invoke-WebRequest { [pscustomobject]@{ Content = "a`nb`nBOOM" } }

        $out = & $script:LogScript -Target 'A' -BaseUrl 'https://ci.example.com' -User 'u' -Token 't'

        "$out" | Should -BeLike '*BOOM*'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*/consoleText' }
    }

    It 'rejects -Stage on a job that has no stage data' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 404 (Not Found).' }

        { & $script:LogScript -Target 'A' -Stage 'Build' -BaseUrl 'https://ci.example.com' -User 'u' -Token 't' } |
            Should -Throw '*not a Pipeline job*'
    }

    It 'names the stages when -Stage matches none of them' {
        Mock Invoke-RestMethod {
            [pscustomobject]@{ name = 'A'; status = 'FAILED'; stages = @(
                [pscustomobject]@{ name = 'Checkout'; status = 'SUCCESS' }
            )}
        }

        { & $script:LogScript -Target 'A' -Stage 'Deploy' -BaseUrl 'https://ci.example.com' -User 'u' -Token 't' } |
            Should -Throw '*Stages: Checkout*'
    }
}
