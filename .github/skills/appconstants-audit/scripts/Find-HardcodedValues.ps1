<#
.SYNOPSIS
    Flags hardcoded paths, URLs, connection strings and other literals that belong in a
    centralized constants class (AppConstants / Header / Constants) instead of inline.

.DESCRIPTION
    Scans C# files for risky string literals and reports file:line findings. Literals found inside
    recognized constants files are treated as compliant; the same literal elsewhere is a violation.
    Designer/generated files are skipped.

.PARAMETER Path
    One or more files or folders to scan. Accepts pipeline input (e.g. from `git diff --name-only`).

.EXAMPLE
    pwsh ./Find-HardcodedValues.ps1 -Path .\FeedbackAsp

.EXAMPLE
    git diff --name-only origin/develop... | pwsh ./Find-HardcodedValues.ps1
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true, Position = 0)]
    [string[]]$Path = '.',

    [string[]]$ConstantsFilePattern = @('*Constants*.cs', 'Header.cs', 'AppConstants.cs', '*Settings*.cs'),
    [string[]]$ExcludePattern = @('*.designer.cs', '*.Designer.cs', 'AssemblyInfo.cs', '*.g.cs', '*.g.i.cs')
)

begin {
    $patterns = @(
        @{ Name = 'UNC path';           Regex = '@?"\\\\[^"\r\n]+"' },
        @{ Name = 'Windows drive path'; Regex = '@?"[A-Za-z]:\\\\[^"\r\n]+"' },
        @{ Name = 'URL';                Regex = '"https?://[^"\r\n]+"' },
        @{ Name = 'Connection string';  Regex = '"[^"\r\n]*(Data Source|Initial Catalog|Server=|Provider=)[^"\r\n]*"' },
        @{ Name = 'IP address';         Regex = '"[^"\r\n]*\b\d{1,3}(\.\d{1,3}){3}\b[^"\r\n]*"' },
        @{ Name = 'Secret / pass-key';  Regex = '(?i)(passkey|password|passphrase|secret|apikey|api_key|token)\s*=\s*@?"[^"\r\n]+"' }
    )
    $files = New-Object System.Collections.Generic.List[string]
}

process {
    foreach ($p in $Path) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path $p -PathType Container) {
            Get-ChildItem -Path $p -Recurse -Include *.cs -File | ForEach-Object { $files.Add($_.FullName) }
        }
        elseif (Test-Path $p -PathType Leaf) {
            if ($p -like '*.cs') { $files.Add((Resolve-Path $p).Path) }
        }
    }
}

end {
    $findings = foreach ($file in ($files | Sort-Object -Unique)) {
        $leaf = Split-Path $file -Leaf
        if ($ExcludePattern | Where-Object { $leaf -like $_ }) { continue }
        $isConstantsFile = [bool]($ConstantsFilePattern | Where-Object { $leaf -like $_ })

        $lineNo = 0
        foreach ($line in (Get-Content -LiteralPath $file)) {
            $lineNo++
            if ($line -match '^\s*//') { continue }   # skip comment lines
            foreach ($pat in $patterns) {
                if ($line -match $pat.Regex) {
                    $isSecret = $pat.Name -eq 'Secret / pass-key'
                    [pscustomobject]@{
                        Severity        = if ($isSecret) { 'Blocker' } elseif ($isConstantsFile) { 'Info' } else { 'Major' }
                        Rule            = $pat.Name
                        File            = $file
                        Line            = $lineNo
                        Code            = $line.Trim()
                        InConstantsFile = $isConstantsFile
                        IsSecret        = $isSecret
                    }
                }
            }
        }
    }

    # Violations = anything outside a constants file, plus ALL secrets (secrets are never OK in source).
    $violations = $findings | Where-Object { (-not $_.InConstantsFile) -or $_.IsSecret }

    if ($violations) {
        $violations | Sort-Object Severity, Rule, File, Line |
            Format-Table Severity, Rule, File, Line, Code -AutoSize -Wrap
    }
    else {
        Write-Output "No hardcoded literals found outside constants files."
    }

    Write-Output ''
    Write-Output ('Summary: {0} violation(s) ({1} secret/blocker).' -f `
            @($violations).Count, @($violations | Where-Object IsSecret).Count)
}
