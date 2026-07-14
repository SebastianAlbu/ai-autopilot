#requires -Version 7.0
<#
.SYNOPSIS
    Detect whether a repo / pull request is a C# Visual Studio web app or an SPLE / spl-core
    embedded platform project, so the PR-review orchestrator can pick the right ruleset.

.DESCRIPTION
    Scores the repository against two marker sets:
      * SPLE / spl-core  (CMake + KConfig + variants/, C/C++/Python, VS Code-based)
      * C# Visual Studio (.sln/.csproj/.aspx/Web.config, lots of .cs)
    Signals come from (any combination of):
      -RepoPath          a local checkout to scan
      -ChangedFiles      an array of changed file paths (e.g. from the PR context)
      -ChangedFilesFile  a file containing newline-separated changed paths
      -ProjectKey        the Bitbucket project key (SPLE -> strong SPLE signal; TDST -> supporting C#)

    Prints a JSON classification with projectType, confidence, scores, matched markers and the
    recommended skill/reviewer to route to.

.EXAMPLE
    pwsh ./Get-ProjectType.ps1 -RepoPath . -ProjectKey TDST

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
$bag = @{
    Scores  = @{ sple = 0; csharp = 0 }
    Markers = @{ sple = [System.Collections.Generic.List[string]]::new(); csharp = [System.Collections.Generic.List[string]]::new() }
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
        'TDST' { Add-Score $bag 'csharp' 2 'projectKey=TDST' }
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

# ---- Decide ------------------------------------------------------------------------------
$sple = [int]$bag.Scores.sple
$cs = [int]$bag.Scores.csharp

$type = 'other'
$confidence = 'low'
$skill = 'none'
$reviewer = 'none'

if ($sple -eq 0 -and $cs -eq 0) {
    $type = 'other'; $confidence = 'low'
}
elseif ($sple -gt 0 -and $cs -gt 0 -and ([math]::Abs($sple - $cs) -le 2)) {
    $type = 'mixed'; $confidence = 'low'
}
elseif ($sple -ge $cs) {
    $type = 'sple-platform'
    $skill = 'sple-standards'; $reviewer = 'sple-standards-reviewer'
    $confidence = if ($sple -ge 5) { 'high' } elseif ($sple -ge 3) { 'medium' } else { 'low' }
}
else {
    $type = 'csharp-visualstudio'
    $skill = 'csharp-webapp-rules'; $reviewer = 'csharp-webapp-reviewer'
    $confidence = if ($cs -ge 5) { 'high' } elseif ($cs -ge 3) { 'medium' } else { 'low' }
}

$notes = switch ($type) {
    'sple-platform' { "Detected SPLE / spl-core embedded project (CMake/KConfig/variants, C/C++/Python). Apply SPLE standards." }
    'csharp-visualstudio' { "Detected C# Visual Studio web app (.sln/.csproj/.aspx). Apply C# coding guidelines + web-app rules." }
    'mixed' { "Markers for both SPLE and C# found and scores are close. Inspect changed files and state the assumption before reviewing." }
    default { "No strong markers found. Inspect changed-file extensions: .cs/.aspx => C#; .c/.cpp/.h/CMakeLists.txt/KConfig => SPLE." }
}

[pscustomobject]@{
    projectType        = $type
    confidence         = $confidence
    scores             = [pscustomobject]@{ sple = $sple; csharp = $cs }
    matchedMarkers     = [pscustomobject]@{ sple = @($bag.Markers.sple); csharp = @($bag.Markers.csharp) }
    recommendedSkill   = $skill
    recommendedReviewer = $reviewer
    filesInspected     = $paths.Count
    notes              = $notes
} | ConvertTo-Json -Depth 5
