#requires -Version 7.0
<#
.SYNOPSIS
    Classify a repo / pull request and route each changed file to the review rule set that
    governs it, so the PR-review orchestrator applies every ruleset the change actually needs.

.DESCRIPTION
    Answers two separate questions, because conflating them is what makes a Python file in an
    embedded repo get reviewed as firmware - or not reviewed at all:

      1. projectType - the repo family, which decides the structural/convention ruleset:
           * SPLE / spl-core  (CMake + KConfig + variants/, C/C++/Python, VS Code-based)
           * C# Visual Studio (.sln/.csproj/.aspx/Web.config, lots of .cs)
           * Python           (pyproject.toml / setup.py / requirements.txt, mostly .py)
           * Embedded C       (firmware without spl-core: .c/.h + linker scripts, HAL, no variants/)

      2. routing - per-language rule sets, derived from the CHANGED FILES. One pull request can
         touch Python and C at once, so this is a list, not a single winner. Each entry names the
         ruleset, the reviewer agent, and the files it applies to.

    Structural and language rulesets compose: an SPLE change touching .c and .py gets
    sple-standards (structure, CMake, KConfig, variants) plus embedded-c-rules and python-rules
    (the code itself). Each finding is still reported once, by whichever ruleset describes it.
    Signals come from (any combination of):
      -RepoPath          a local checkout to scan
      -ChangedFiles      an array of changed file paths (e.g. from the PR context)
      -ChangedFilesFile  a file containing newline-separated changed paths
      -ProjectKey        the Bitbucket project key (SPLE -> strong SPLE signal)

    Prints a JSON classification with projectType, confidence, scores, matched markers, the
    recommended structural skill/reviewer, and a `routing` array of per-language rulesets.

    Routing is computed from -ChangedFiles / -ChangedFilesFile when given, since those are the
    files under review. With only -RepoPath it falls back to the whole tree, which is right for
    "what is this repo" but too broad for "what should this PR be reviewed against".

.EXAMPLE
    pwsh ./Get-ProjectType.ps1 -RepoPath . -ProjectKey PROJ

.EXAMPLE
    pwsh ./Get-ProjectType.ps1 -ChangedFilesFile ./changed-files.txt -ProjectKey SPLE
#>
[CmdletBinding()]
param(
    [string]$RepoPath,
    [string[]]$ChangedFiles,
    [string]$ChangedFilesFile,
    [string]$ProjectKey,
    [int]$MaxFiles = 4000
)

$ErrorActionPreference = 'Stop'

function Add-Score {
    param(
        [hashtable]$Bag,
        [string]$Key,
        [int]$Points,
        [string]$Marker
    )
    $Bag.Scores[$Key] += $Points
    if ($Marker -and ($Bag.Markers[$Key] -notcontains $Marker)) {
        [void]$Bag.Markers[$Key].Add($Marker)
    }
}

# ---- Collect the set of relative paths we can reason about ---------------------------------
$relPaths = [System.Collections.Generic.List[string]]::new()

if ($RepoPath) {
    if (-not (Test-Path -LiteralPath $RepoPath)) {
        throw "RepoPath not found: $RepoPath"
    }
    $root = (Resolve-Path -LiteralPath $RepoPath).Path
    $count = 0
    Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|\.venv|build|out|dist|\.tox|__pycache__)[\\/]' } |
        ForEach-Object {
            if ($count -lt $MaxFiles) {
                $rel = $_.FullName.Substring($root.Length).TrimStart('\', '/').Replace('\', '/')
                $relPaths.Add($rel)
                $count++
            }
        }
}

if ($ChangedFilesFile) {
    if (-not (Test-Path -LiteralPath $ChangedFilesFile)) {
        throw "ChangedFilesFile not found: $ChangedFilesFile"
    }
    Get-Content -LiteralPath $ChangedFilesFile |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ } |
        ForEach-Object { $relPaths.Add($_.Replace('\', '/')) }
}

if ($ChangedFiles) {
    foreach ($f in $ChangedFiles) {
        if ($f) { $relPaths.Add($f.Trim().Replace('\', '/')) }
    }
}

$paths = $relPaths | Sort-Object -Unique
$lower = $paths | ForEach-Object { $_.ToLowerInvariant() }

# ---- Scoring bag --------------------------------------------------------------------------
$families = @('sple', 'csharp', 'python', 'embeddedc')
$bag = @{ Scores = @{}; Markers = @{} }
foreach ($f in $families) {
    $bag.Scores[$f] = 0
    $bag.Markers[$f] = [System.Collections.Generic.List[string]]::new()
}

function Test-AnyPath {
    # Glob match anywhere in the path list (use for extension/dir globs like '*.sln', 'variants/*').
    param([string[]]$Haystack, [string]$Pattern)
    return [bool]($Haystack | Where-Object { $_ -like $Pattern } | Select-Object -First 1)
}

function Test-AnyName {
    # Bare-filename match at repo root OR in any subdirectory (e.g. 'web.config' -> 'app/web.config').
    param([string[]]$Haystack, [string]$Name)
    return [bool]($Haystack | Where-Object { $_ -eq $Name -or $_ -like "*/$Name" } | Select-Object -First 1)
}

# ---- Bitbucket project key signals --------------------------------------------------------
if ($ProjectKey) {
    switch ($ProjectKey.ToUpperInvariant()) {
        'SPLE' { Add-Score $bag 'sple' 5 'projectKey=SPLE' }
        default { }
    }
}

# ---- SPLE / spl-core markers --------------------------------------------------------------
if (Test-AnyName $lower 'cmakelists.txt') { Add-Score $bag 'sple' 2 'CMakeLists.txt' }
if (Test-AnyName $lower 'kconfig') { Add-Score $bag 'sple' 3 'KConfig' }
if (Test-AnyPath $lower 'variants/*') { Add-Score $bag 'sple' 3 'variants/' }
if ((Test-AnyPath $lower 'components/*/src/*') -or (Test-AnyPath $lower 'components/*')) { Add-Score $bag 'sple' 2 'components/' }
if (Test-AnyName $lower 'build.ps1') { Add-Score $bag 'sple' 1 'build.ps1' }
if (Test-AnyName $lower 'build.bat') { Add-Score $bag 'sple' 1 'build.bat' }
if (Test-AnyName $lower 'pypeline.yaml') { Add-Score $bag 'sple' 2 'pypeline.yaml' }
if (Test-AnyName $lower 'bootstrap.json') { Add-Score $bag 'sple' 1 'bootstrap.json' }
if (Test-AnyName $lower 'scoopfile.json') { Add-Score $bag 'sple' 1 'scoopfile.json' }
if (Test-AnyName $lower 'poks.json') { Add-Score $bag 'sple' 1 'poks.json' }
if (Test-AnyPath $lower '.vscode/*') { Add-Score $bag 'sple' 1 '.vscode/' }
if (Test-AnyPath $lower '.devcontainer/*') { Add-Score $bag 'sple' 1 '.devcontainer/' }
if (Test-AnyName $lower 'pyproject.toml') { Add-Score $bag 'sple' 1 'pyproject.toml' }
if (Test-AnyName $lower 'pytest.ini') { Add-Score $bag 'sple' 1 'pytest.ini' }
if (Test-AnyName $lower 'parts.json') { Add-Score $bag 'sple' 2 'parts.json' }
# embedded source files
if ((Test-AnyPath $lower '*.c') -or (Test-AnyPath $lower '*.cpp') -or (Test-AnyPath $lower '*.h') -or (Test-AnyPath $lower '*.hpp')) {
    Add-Score $bag 'sple' 1 'C/C++ sources'
}

# ---- C# Visual Studio markers -------------------------------------------------------------
if (Test-AnyPath $lower '*.sln') { Add-Score $bag 'csharp' 4 '*.sln' }
if (Test-AnyPath $lower '*.csproj') { Add-Score $bag 'csharp' 4 '*.csproj' }
if (Test-AnyPath $lower '*.vbproj') { Add-Score $bag 'csharp' 3 '*.vbproj' }
if (Test-AnyName $lower 'web.config') { Add-Score $bag 'csharp' 3 'Web.config' }
if (Test-AnyName $lower 'app.config') { Add-Score $bag 'csharp' 1 'App.config' }
if ((Test-AnyPath $lower '*.aspx') -or (Test-AnyPath $lower '*.ascx') -or (Test-AnyPath $lower '*.asmx')) {
    Add-Score $bag 'csharp' 3 'ASP.NET pages'
}
if (Test-AnyName $lower 'global.asax') { Add-Score $bag 'csharp' 2 'Global.asax' }
if (Test-AnyName $lower 'packages.config') { Add-Score $bag 'csharp' 1 'packages.config' }
if (Test-AnyPath $lower '*/properties/assemblyinfo.cs') { Add-Score $bag 'csharp' 1 'AssemblyInfo.cs' }
if (Test-AnyPath $lower '*.cs') { Add-Score $bag 'csharp' 1 'C# sources' }

# ---- Standalone Python project markers ----------------------------------------------------
# Only count these as a PROJECT family when spl-core markers are absent - an SPLE repo has
# pyproject.toml for its build tooling and would otherwise look like a Python project.
if (Test-AnyName $lower 'setup.py') { Add-Score $bag 'python' 3 'setup.py' }
if (Test-AnyName $lower 'setup.cfg') { Add-Score $bag 'python' 2 'setup.cfg' }
if (Test-AnyName $lower 'requirements.txt') { Add-Score $bag 'python' 2 'requirements.txt' }
if (Test-AnyName $lower 'pipfile') { Add-Score $bag 'python' 2 'Pipfile' }
if (Test-AnyName $lower 'poetry.lock') { Add-Score $bag 'python' 2 'poetry.lock' }
if (Test-AnyName $lower 'tox.ini') { Add-Score $bag 'python' 2 'tox.ini' }
if (Test-AnyName $lower 'conftest.py') { Add-Score $bag 'python' 2 'conftest.py' }
if (Test-AnyName $lower 'manage.py') { Add-Score $bag 'python' 3 'manage.py (Django)' }
if (Test-AnyName $lower '__init__.py') { Add-Score $bag 'python' 1 'package __init__.py' }
if (Test-AnyPath $lower '*.py') { Add-Score $bag 'python' 1 'Python sources' }

# ---- Embedded C (firmware WITHOUT spl-core) -----------------------------------------------
# The distinguishing marks are toolchain and hardware artefacts, not just .c files - plain C
# also shows up in SPLE repos and in desktop tools.
if (Test-AnyPath $lower '*.ld') { Add-Score $bag 'embeddedc' 3 'linker script (*.ld)' }
if (Test-AnyPath $lower '*.icf') { Add-Score $bag 'embeddedc' 3 'linker config (*.icf)' }
if (Test-AnyPath $lower '*.hex') { Add-Score $bag 'embeddedc' 2 '*.hex' }
if (Test-AnyPath $lower '*.ioc') { Add-Score $bag 'embeddedc' 3 'STM32CubeMX (*.ioc)' }
if (Test-AnyPath $lower '*.uvprojx') { Add-Score $bag 'embeddedc' 3 'Keil project' }
if (Test-AnyPath $lower '*.cproject') { Add-Score $bag 'embeddedc' 2 'Eclipse CDT project' }
if (Test-AnyName $lower 'makefile') { Add-Score $bag 'embeddedc' 1 'Makefile' }
if (Test-AnyName $lower 'platformio.ini') { Add-Score $bag 'embeddedc' 3 'PlatformIO' }
if (Test-AnyName $lower 'sdkconfig') { Add-Score $bag 'embeddedc' 3 'ESP-IDF sdkconfig' }
if (Test-AnyName $lower 'freertosconfig.h') { Add-Score $bag 'embeddedc' 3 'FreeRTOS' }
if ((Test-AnyPath $lower '*/hal/*') -or (Test-AnyPath $lower '*hal_*.c') -or (Test-AnyPath $lower '*/drivers/*')) {
    Add-Score $bag 'embeddedc' 2 'HAL/driver layer'
}
if ((Test-AnyPath $lower '*/cmsis/*') -or (Test-AnyPath $lower '*startup_*.s') -or (Test-AnyPath $lower '*.s')) {
    Add-Score $bag 'embeddedc' 2 'CMSIS / startup assembly'
}
if ((Test-AnyPath $lower '*.c') -or (Test-AnyPath $lower '*.h')) { Add-Score $bag 'embeddedc' 1 'C sources' }

# ---- Decide the project family -----------------------------------------------------------
# spl-core markers win over the generic Python/embedded ones they subsume: an SPLE repo has
# pyproject.toml AND .c files, and calling it "python" or "embedded-c" would drop the variant
# and KConfig rules that only sple-standards knows about.
$sple  = [int]$bag.Scores.sple
$cs    = [int]$bag.Scores.csharp
$py    = [int]$bag.Scores.python
$ec    = [int]$bag.Scores.embeddedc

$strongSple = ($sple -ge 5)
if ($strongSple) { $py = [math]::Max(0, $py - 3); $ec = [math]::Max(0, $ec - 3) }

$ranked = @(
    [pscustomobject]@{ Family='sple-platform';        Score=$sple; Skill='sple-standards';     Reviewer='sple-standards-reviewer' },
    [pscustomobject]@{ Family='csharp-visualstudio';  Score=$cs;   Skill='csharp-webapp-rules'; Reviewer='csharp-webapp-reviewer' },
    [pscustomobject]@{ Family='embedded-c';           Score=$ec;   Skill='embedded-c-rules';    Reviewer='embedded-c-reviewer' },
    [pscustomobject]@{ Family='python';               Score=$py;   Skill='python-rules';        Reviewer='python-reviewer' }
) | Sort-Object -Property Score -Descending

$top = $ranked[0]
$second = $ranked[1]

$type = 'other'; $confidence = 'low'; $skill = 'none'; $reviewer = 'none'
if ($top.Score -le 0) {
    $type = 'other'
}
elseif (($top.Score - $second.Score) -le 2 -and $second.Score -gt 0) {
    # Too close to call. Say so rather than guessing - routing below still covers the files.
    $type = 'mixed'
}
else {
    $type = $top.Family; $skill = $top.Skill; $reviewer = $top.Reviewer
    $confidence = if ($top.Score -ge 6) { 'high' } elseif ($top.Score -ge 3) { 'medium' } else { 'low' }
}

# ---- Route each changed file to the rule set that governs it ------------------------------
# This is the part that makes multi-language PRs work. Structural rules follow the repo family;
# language rules follow the file extension, so a diff touching .py and .c gets both.
$routingSource = if ($ChangedFiles -or $ChangedFilesFile) { 'changed-files' } else { 'repo-scan' }

$langMap = @(
    @{ Ruleset='csharp-webapp-rules'; Reviewer='csharp-webapp-reviewer'; Patterns=@('*.cs','*.aspx','*.ascx','*.asmx','*.cshtml','*.vb') },
    @{ Ruleset='python-rules';        Reviewer='python-reviewer';        Patterns=@('*.py','*.pyi') },
    @{ Ruleset='embedded-c-rules';    Reviewer='embedded-c-reviewer';    Patterns=@('*.c','*.h','*.cpp','*.hpp','*.cc','*.cxx') }
)

$routing = [System.Collections.Generic.List[object]]::new()
foreach ($entry in $langMap) {
    $matched = @($lower | Where-Object { $path = $_; ($entry.Patterns | Where-Object { $path -like $_ }).Count -gt 0 })
    if ($matched.Count -gt 0) {
        [void]$routing.Add([pscustomobject]@{
            ruleset   = $entry.Ruleset
            reviewer  = $entry.Reviewer
            fileCount = $matched.Count
            files     = @($matched | Select-Object -First 25)
        })
    }
}

# The structural ruleset applies to the repo as a whole whenever the family was identified,
# even if no file of "its" language changed - a CMakeLists or variant edit is exactly that case.
$structural = $null
if ($type -in @('sple-platform', 'csharp-visualstudio')) {
    $structural = [pscustomobject]@{ ruleset = $skill; reviewer = $reviewer; scope = 'repo-structure-and-conventions' }
    if ($type -eq 'csharp-visualstudio' -and -not ($routing | Where-Object { $_.ruleset -eq 'csharp-webapp-rules' })) {
        [void]$routing.Add([pscustomobject]@{ ruleset='csharp-webapp-rules'; reviewer='csharp-webapp-reviewer'; fileCount=0; files=@() })
    }
}

# In an SPLE repo, C and Python files are still governed by the language rules - sple-standards
# covers structure, CMake, KConfig and variants, not whether a memcpy is bounds-checked.
$notes = switch ($type) {
    'sple-platform'       { "SPLE / spl-core project. Apply sple-standards for structure, CMake, KConfig and variants, plus the language rulesets in `routing` for the code itself." }
    'csharp-visualstudio' { "C# Visual Studio web app. Apply csharp-webapp-rules (coding guidelines + web-app security/reliability)." }
    'python'              { "Standalone Python project. Apply python-rules." }
    'embedded-c'          { "Embedded firmware project without spl-core. Apply embedded-c-rules." }
    'mixed'               { "Top two families scored within 2 points. State the assumption before reviewing; `routing` still lists every ruleset the changed files need." }
    default               { "No strong project markers. Fall back to `routing`, which is derived from the changed-file extensions." }
}
if ($routing.Count -eq 0) {
    $notes += " No changed file matched a language ruleset - the diff may be docs, config or build-only."
}

[pscustomobject]@{
    projectType         = $type
    confidence          = $confidence
    scores              = [pscustomobject]@{ sple = $sple; csharp = $cs; python = $py; embeddedc = $ec }
    matchedMarkers      = [pscustomobject]@{
        sple      = @($bag.Markers.sple)
        csharp    = @($bag.Markers.csharp)
        python    = @($bag.Markers.python)
        embeddedc = @($bag.Markers.embeddedc)
    }
    recommendedSkill    = $skill
    recommendedReviewer = $reviewer
    structuralRuleset   = $structural
    routing             = @($routing)
    routingSource       = $routingSource
    filesInspected      = $paths.Count
    notes               = $notes
} | ConvertTo-Json -Depth 6
