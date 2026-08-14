<#
    Tests for embedded-c-rules/scripts/Get-PolyspaceCheckers.ps1.

    The script's only input is a file, so these build minimal checkers XMLs in TestDrive rather than
    mocking anything. What is worth testing is the state filtering, the whole-standard case (a standard
    switched on with no per-check nodes), discovery, and the error messages.
#>

BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..\.github\skills\embedded-c-rules\scripts\Get-PolyspaceCheckers.ps1'

    # -Path defaults to this variable; a developer machine that has it set would bypass the discovery tests.
    $script:SavedCheckersXml = $env:POLYSPACE_CHECKERS_XML
    $env:POLYSPACE_CHECKERS_XML = $null

    function New-CheckersXml {
        param([Parameter(Mandatory = $true)][string]$Path)

        @'
<?xml version="1.0" encoding="UTF-8"?>
<polyspace_checkers_selection revision="1.0">
  <standard name="MISRA C:2012">
    <section name="9 Initialization">
      <check id="9.1" state="on"/>
      <check id="9.6" state="notimplemented"></check>
      <check id="9.2" state="off"/>
    </section>
    <section name="22 Resources">
      <check id="22.2" state="on"/>
      <check id="22.12" state="notimplemented"></check>
    </section>
  </standard>
  <standard name="SEI CERT C" state="on"/>
  <standard name="AUTOSAR C++14" state="off"/>
</polyspace_checkers_selection>
'@ | Set-Content -LiteralPath $Path -Encoding UTF8
        return $Path
    }
}

AfterAll {
    $env:POLYSPACE_CHECKERS_XML = $script:SavedCheckersXml
}

Describe 'Get-PolyspaceCheckers.ps1' {

    BeforeEach {
        $script:Xml = New-CheckersXml -Path (Join-Path $TestDrive 'SMK.xml')
    }

    Context 'State filtering' {

        It 'lists the enabled checks by default, and the whole-standard entry with them' {
            $out = (& $script:Script -Path $script:Xml) -join "`n"

            $out | Should -BeLike '*9.1*'
            $out | Should -BeLike '*22.2*'
            $out | Should -BeLike '*SEI CERT C*'
            $out | Should -Not -BeLike '*9.6*'      # notimplemented
            $out | Should -Not -BeLike '*9.2*'      # off
            $out | Should -Not -BeLike '*AUTOSAR*'  # standard is off
        }

        It '-State notimplemented lists only what Polyspace cannot check, and says so' {
            $out = (& $script:Script -Path $script:Xml -State notimplemented) -join "`n"

            $out | Should -BeLike '*9.6*'
            $out | Should -BeLike '*22.12*'
            $out | Should -Not -BeLike '*9.1*'
            $out | Should -BeLike '*Polyspace does NOT check them*'
        }

        It '-Standard narrows to one standard' {
            $json = (& $script:Script -Path $script:Xml -State all -Standard 'MISRA' -Json) | ConvertFrom-Json

            $json.checks.standard | Should -Not -Contain 'SEI CERT C'
            $json.checks.Count | Should -Be 5
        }

        It '-Json reports the source file and the count' {
            $json = (& $script:Script -Path $script:Xml -Json) | ConvertFrom-Json

            $json.state | Should -Be 'on'
            $json.count | Should -Be 3           # 9.1, 22.2, SEI CERT C
            $json.source | Should -BeLike '*SMK.xml'
        }

        It 'keeps the section name with each check, for grouping in a report' {
            $json = (& $script:Script -Path $script:Xml -Json) | ConvertFrom-Json

            ($json.checks | Where-Object id -eq '9.1').section | Should -Be '9 Initialization'
        }
    }

    Context 'Discovery' {

        It 'finds the checkers XML under -SearchRoot when no path is given' {
            $variant = Join-Path $TestDrive 'variants\M1'
            New-Item -ItemType Directory -Path $variant -Force | Out-Null
            New-CheckersXml -Path (Join-Path $variant 'M1.xml') | Out-Null

            $json = (& $script:Script -SearchRoot $TestDrive -Json) | ConvertFrom-Json

            $json.source | Should -BeLike '*.xml'
            $json.count | Should -BeGreaterThan 0
        }

        It 'says where to look when there is no checkers XML anywhere' {
            $empty = Join-Path $TestDrive 'empty'
            New-Item -ItemType Directory -Path $empty -Force | Out-Null

            { & $script:Script -SearchRoot $empty } | Should -Throw '*POLYSPACE_CHECKERS_XML*'
        }
    }

    Context 'Bad input' {

        It 'rejects a missing file by name' {
            { & $script:Script -Path (Join-Path $TestDrive 'nope.xml') } | Should -Throw '*not found*'
        }

        It 'rejects XML that is not a checkers selection' {
            $other = Join-Path $TestDrive 'other.xml'
            '<project><name>x</name></project>' | Set-Content -LiteralPath $other -Encoding UTF8

            { & $script:Script -Path $other } | Should -Throw '*not a Polyspace checkers selection*'
        }

        It 'rejects a file that is not XML at all' {
            $junk = Join-Path $TestDrive 'junk.xml'
            'not xml' | Set-Content -LiteralPath $junk -Encoding UTF8

            { & $script:Script -Path $junk } | Should -Throw '*Not valid XML*'
        }
    }
}
