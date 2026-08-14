<#
.SYNOPSIS
    List which Polyspace checkers a project has enabled, from its checkers-selection XML.

.DESCRIPTION
    Polyspace Bug Finder / Code Prover store the selected rule set in a
    `<polyspace_checkers_selection>` XML, usually one per variant. Each check carries a state:

      on              Polyspace reports it. A violation is a CI/quality-gate failure.
      off             deliberately not checked here — do not raise it as a MISRA finding.
      notimplemented  the rule is in scope but Polyspace CANNOT check it. Nothing catches these
                      except review, which makes them the most valuable rules for a reviewer.

    The default output is the enabled set; use -State notimplemented for the review-only gap list.
    Nothing here is site-specific: the file is located from -Path, POLYSPACE_CHECKERS_XML, or a
    search under -SearchRoot.

.PARAMETER Path
    The checkers-selection XML. Defaults to $env:POLYSPACE_CHECKERS_XML, then to a search.

.PARAMETER SearchRoot
    Folder to search when no path is given. Defaults to the current directory.

.PARAMETER State
    Which checks to list: on (default), notimplemented, off, or all.

.PARAMETER Standard
    Only this standard, e.g. 'MISRA C:2012', 'SEI CERT C'. Substring match, case-insensitive.

.PARAMETER Json
    Emit JSON instead of the text listing.

.EXAMPLE
    pwsh Get-PolyspaceCheckers.ps1 -Path variants/M437101_SMK_Touch/SMK_TOUCH.xml
    The rules this variant actually enforces.

.EXAMPLE
    pwsh Get-PolyspaceCheckers.ps1 -State notimplemented
    The rules Polyspace cannot check — review is the only gate for these.

.EXAMPLE
    pwsh Get-PolyspaceCheckers.ps1 -SearchRoot C:\repo\smk_rl78 -Json
#>
[CmdletBinding()]
param(
    [string]$Path = $env:POLYSPACE_CHECKERS_XML,
    [string]$SearchRoot = '.',
    [ValidateSet('on', 'notimplemented', 'off', 'all')]
    [string]$State = 'on',
    [string]$Standard,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

function Find-CheckersXml {
    param([Parameter(Mandatory = $true)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) { throw "Search root not found: $Root" }

    # -Depth keeps this off the deep build/ext trees an embedded repo carries.
    $candidates = Get-ChildItem -LiteralPath $Root -Filter *.xml -Recurse -Depth 5 -File -ErrorAction SilentlyContinue
    foreach ($c in $candidates) {
        if (Select-String -LiteralPath $c.FullName -Pattern 'polyspace_checkers_selection' -SimpleMatch -List -Quiet) {
            return $c.FullName
        }
    }
    return $null
}

if (-not $Path) {
    $Path = Find-CheckersXml -Root $SearchRoot
    if (-not $Path) {
        throw ("No Polyspace checkers XML found under '{0}'. Pass -Path, or set POLYSPACE_CHECKERS_XML. " +
               "It is normally variants/<variant>/<NAME>.xml and its root element is <polyspace_checkers_selection>." -f $SearchRoot)
    }
}

if (-not (Test-Path -LiteralPath $Path)) { throw "Checkers XML not found: $Path" }

try {
    $xml = [xml](Get-Content -LiteralPath $Path -Raw)
}
catch {
    throw "Not valid XML: $Path — $($_.Exception.Message)"
}

$root = $xml.polyspace_checkers_selection
if (-not $root) {
    throw "$Path is XML but not a Polyspace checkers selection (root element is not <polyspace_checkers_selection>)."
}

$rows = foreach ($std in @($root.standard)) {
    if ($Standard -and $std.name -notlike "*$Standard*") { continue }

    $checks = @($std.SelectNodes('.//check'))

    # A standard can be switched on as a whole, with no per-check nodes — SEI CERT C is normally like this.
    if ($checks.Count -eq 0) {
        if ($State -in @('all', $std.state)) {
            [pscustomobject]@{
                standard = $std.name
                section  = '(whole standard)'
                id       = '*'
                state    = $std.state
            }
        }
        continue
    }

    foreach ($section in @($std.section)) {
        foreach ($check in @($section.check)) {
            if ($State -ne 'all' -and $check.state -ne $State) { continue }
            [pscustomobject]@{
                standard = $std.name
                section  = $section.name
                id       = $check.id
                state    = $check.state
            }
        }
    }
}

$rows = @($rows)

if ($Json) {
    return ([pscustomobject]@{ source = (Resolve-Path -LiteralPath $Path).Path; state = $State; count = $rows.Count; checks = $rows } |
        ConvertTo-Json -Depth 5)
}

"Polyspace checkers: {0}" -f (Resolve-Path -LiteralPath $Path).Path
"State filter: {0} — {1} check(s)" -f $State, $rows.Count
''

if ($rows.Count -eq 0) {
    "No checks match. Try -State all to see everything the file declares."
    return
}

foreach ($group in ($rows | Group-Object standard)) {
    "== {0} ==" -f $group.Name
    foreach ($row in ($group.Group | Sort-Object section, id)) {
        "  {0,-10} {1,-16} {2}" -f $row.id, $row.state, $row.section
    }
    ''
}

if ($State -eq 'notimplemented') {
    "These are in scope but Polyspace does NOT check them — review is the only gate."
}
