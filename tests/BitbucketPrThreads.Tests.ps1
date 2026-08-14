<#
    Tests for the bitbucket-pr-threads skill.

    Mocked at the HTTP boundary (Invoke-RestMethod), so nothing here needs a server, a token or a network.
    The scripts are invoked with & from inside It blocks: they run in a child scope of the test session
    state, so the mock defined in BeforeAll applies inside them.
#>

BeforeAll {
    $script:SkillRoot = Join-Path $PSScriptRoot '..\.github\skills\bitbucket-pr-threads\scripts'
    $script:ReadScript  = Join-Path $script:SkillRoot 'Get-PullRequestComments.ps1'
    $script:StateScript = Join-Path $script:SkillRoot 'Set-PullRequestCommentState.ps1'
    $script:PrUrl = 'https://bitbucket.example.com/projects/PROJ/repos/my-repo/pull-requests/42/overview'

    function New-Comment {
        param(
            [int]$Id,
            [string]$Text,
            [string]$Author = 'Reviewer',
            [string]$State = 'OPEN',
            [string]$Severity = 'NORMAL',
            [object[]]$Replies = @()
        )
        return [pscustomobject]@{
            id       = $Id
            version  = 0
            text     = $Text
            author   = [pscustomobject]@{ displayName = $Author }
            state    = $State
            severity = $Severity
            comments = $Replies
        }
    }

    function New-Activity {
        param($Comment, $Anchor)
        return [pscustomobject]@{ action = 'COMMENTED'; comment = $Comment; commentAnchor = $Anchor }
    }

    function New-Anchor {
        param([string]$Path, [int]$Line)
        return [pscustomobject]@{ path = $Path; line = $Line; lineType = 'ADDED' }
    }
}

Describe 'Get-PullRequestComments.ps1' {

    Context 'PR coordinate resolution' {

        It 'derives project, repo, id and host from a pasted PR URL' {
            Mock Invoke-RestMethod { [pscustomobject]@{ values = @(); isLastPage = $true; nextPageStart = $null } }

            & $script:ReadScript -Url $script:PrUrl -Token 'x' | Out-Null

            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Uri -like 'https://bitbucket.example.com/rest/api/1.0/projects/PROJ/repos/my-repo/pull-requests/42/activities*'
            }
        }

        It 'rejects a URL that is not a pull request link' {
            Mock Invoke-RestMethod { throw 'should not be called' }
            { & $script:ReadScript -Url 'https://bitbucket.example.com/dashboard' -Token 'x' } |
                Should -Throw '*Could not parse a Bitbucket PR URL*'
        }

        It 'requires a project key in id mode when none is configured' {
            Mock Invoke-RestMethod { throw 'should not be called' }
            { & $script:ReadScript -PullRequestId 42 -Repo 'my-repo' -Project '' -Token 'x' } |
                Should -Throw '*No Bitbucket project key*'
        }
    }

    Context 'Thread collection' {

        BeforeEach {
            # The activities feed emits an entry per comment INCLUDING replies, and each entry carries the
            # full reply tree — so #2 appears both nested under #1 and as its own entry.
            $reply  = New-Comment -Id 2 -Text 'Fixed in 9f3ac21.' -Author 'Author'
            $root   = New-Comment -Id 1 -Text 'Move this to AppConstants.' -Severity 'BLOCKER' -Replies @($reply)
            $second = New-Comment -Id 3 -Text 'Nit: typo.' -State 'RESOLVED' -Author 'Other'

            $script:page0 = [pscustomobject]@{
                values = @(
                    (New-Activity -Comment $root  -Anchor (New-Anchor -Path 'src/Foo.cs' -Line 36)),
                    (New-Activity -Comment $reply -Anchor $null)
                )
                isLastPage    = $false
                nextPageStart = 2
            }
            $script:page1 = [pscustomobject]@{
                values        = @((New-Activity -Comment $second -Anchor $null))
                isLastPage    = $true
                nextPageStart = $null
            }
        }

        It 'pages through the activities feed and lists a reply only under its root' {
            Mock Invoke-RestMethod {
                if ($Uri -match 'start=0') { return $script:page0 }
                return $script:page1
            }

            $result = & $script:ReadScript -Url $script:PrUrl -Token 'x' -Json | ConvertFrom-Json

            Should -Invoke Invoke-RestMethod -Times 2 -Exactly
            $result.threads.Count | Should -Be 2                    # not 3 — #2 is a reply, not a thread
            $result.threads[0].Count | Should -Be 2                 # root + its reply
            $result.threads[0][0].id | Should -Be 1
            $result.threads[0][1].id | Should -Be 2
            $result.threads[0][1].depth | Should -Be 1
        }

        It 'keeps the inline anchor on the thread root' {
            Mock Invoke-RestMethod { if ($Uri -match 'start=0') { $script:page0 } else { $script:page1 } }

            $result = & $script:ReadScript -Url $script:PrUrl -Token 'x' -Json | ConvertFrom-Json

            $result.threads[0][0].path | Should -Be 'src/Foo.cs'
            $result.threads[0][0].line | Should -Be 36
            $result.threads[1][0].path | Should -BeNullOrEmpty     # general comment
        }

        It '-Unresolved drops threads whose root is RESOLVED' {
            Mock Invoke-RestMethod { if ($Uri -match 'start=0') { $script:page0 } else { $script:page1 } }

            $result = & $script:ReadScript -Url $script:PrUrl -Token 'x' -Unresolved -Json | ConvertFrom-Json

            $result.threads.Count | Should -Be 1
            $result.threads[0][0].id | Should -Be 1
        }

        It '-Tasks keeps only BLOCKER threads' {
            Mock Invoke-RestMethod { if ($Uri -match 'start=0') { $script:page0 } else { $script:page1 } }

            $result = & $script:ReadScript -Url $script:PrUrl -Token 'x' -Tasks -Json | ConvertFrom-Json

            $result.threads.Count | Should -Be 1
            $result.threads[0][0].severity | Should -Be 'BLOCKER'
        }

        It '-Author matches the root comment author case-insensitively' {
            Mock Invoke-RestMethod { if ($Uri -match 'start=0') { $script:page0 } else { $script:page1 } }

            $result = & $script:ReadScript -Url $script:PrUrl -Token 'x' -Author 'other' -Json | ConvertFrom-Json

            $result.threads.Count | Should -Be 1
            $result.threads[0][0].id | Should -Be 3
        }

        It 'ignores non-comment activities' {
            Mock Invoke-RestMethod {
                [pscustomobject]@{
                    values = @(
                        [pscustomobject]@{ action = 'APPROVED'; comment = $null },
                        [pscustomobject]@{ action = 'RESCOPED'; comment = $null }
                    )
                    isLastPage    = $true
                    nextPageStart = $null
                }
            }

            $result = & $script:ReadScript -Url $script:PrUrl -Token 'x' -Json | ConvertFrom-Json
            @($result.threads).Count | Should -Be 0
        }
    }
}

Describe 'Set-PullRequestCommentState.ps1' {

    It '-DryRun prints the target and never calls the API' {
        Mock Invoke-RestMethod { throw 'should not be called' }

        $out = & $script:StateScript -Url $script:PrUrl -CommentId 1234 -State RESOLVED -DryRun -Token 'x'

        ($out -join "`n") | Should -BeLike '*DRY RUN*comments/1234*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'fetches the current version before updating the state' {
        Mock Invoke-RestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ id = 1234; version = 7 } }
            return [pscustomobject]@{ id = 1234; version = 8; state = 'RESOLVED' }
        }

        & $script:StateScript -Url $script:PrUrl -CommentId 1234 -State RESOLVED -Token 'x' -Confirm:$false | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and $Body -like '*"version":7*' -and $Body -like '*RESOLVED*'
        }
    }

    It 'retries once when the version went stale (409)' {
        Mock Invoke-RestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ id = 1234; version = 7 } }
            $script:putCount++
            if ($script:putCount -eq 1) { throw 'Response status code does not indicate success: 409 (Conflict).' }
            return [pscustomobject]@{ id = 1234; version = 8 }
        }
        $script:putCount = 0

        & $script:StateScript -Url $script:PrUrl -CommentId 1234 -State RESOLVED -Token 'x' -Confirm:$false | Out-Null

        Should -Invoke Invoke-RestMethod -Times 2 -Exactly -ParameterFilter { $Method -eq 'PUT' }
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly -ParameterFilter { $Method -eq 'GET' }
    }

    It 'explains that a 404 usually means the id is a reply, not a thread root' {
        Mock Invoke-RestMethod { throw 'Response status code does not indicate success: 404 (Not Found).' }

        { & $script:StateScript -Url $script:PrUrl -CommentId 9999 -State RESOLVED -Token 'x' -Confirm:$false } |
            Should -Throw '*REPLY, not the thread root*'
    }

    It 'refuses to run without credentials' {
        Mock Invoke-RestMethod { throw 'should not be called' }

        { & $script:StateScript -Url $script:PrUrl -CommentId 1234 -Token '' -Confirm:$false } |
            Should -Throw '*No credentials*'
    }
}
