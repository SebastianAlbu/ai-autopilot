---
name: appconstants-audit
description: 'Find configuration literals that were hardcoded inline instead of centralized in a constants class — server/UNC paths, URLs and endpoints, connection strings, hosts, IPs, emails, ports, and any credential in source (always a blocker). Use when reviewing C# changes for configuration centralization, and also on softer phrasings that mean the same thing: "magic strings", "hardcoded values", "these paths should be constants", "is anything environment-specific in here", "any secrets committed", or a general C# review where paths and URLs appear in the diff. The regex scanner alone misses composed and interpolated strings, so this skill pairs it with the manual passes that catch them.'
argument-hint: 'path or changed files to scan'
---

# AppConstants Audit

Enforce the project convention: **all environment-specific or reused literals belong in a single constants
class**, not inline across the code base. Typically the constants live in a file such as `AppConstants.cs`,
`Header.cs`, `Constants.cs` or `*Settings*.cs` — yet server/UNC paths, URLs and connection strings keep
getting hardcoded in business and UI code anyway. That is exactly the smell this audit catches.

## What Must Be Centralized
See [appconstants-rules.md](./references/appconstants-rules.md) for the full rule set. In short, flag inline:
- UNC paths (`\\server\share\...`) and Windows drive paths (`C:\...`).
- URLs (`http://`, `https://`).
- Connection strings (`Data Source=`, `Initial Catalog=`, `Server=`, `Provider=`).
- Hardcoded IP addresses and email addresses.
- Repeated "magic" strings/numbers used as configuration.

## Procedure
1. Scan the changed files (or a folder):
   - `pwsh ./scripts/Find-HardcodedValues.ps1 -Path .\src`
   - or pipe changed files: `git diff --name-only origin/develop... | pwsh ./scripts/Find-HardcodedValues.ps1`
2. The script reports `file:line` findings and ignores designer/generated files and the constants files
   themselves (a literal *inside* `AppConstants.cs` is fine; the same literal in `Functionality.cs` is not).
3. For each finding, confirm whether the value is environment-specific or reused. If so, it is a violation.
4. Recommend the fix: move the literal into the appropriate constants class using `UPPER_SNAKE_CASE`
   (matching the existing style) and reference it from the call site.

## Output
Report each violation as:
`[Major] <file>:<line> — <kind> hardcoded inline; move to AppConstants (e.g. AppConstants.SOME_NAME)`

Then a one-line summary count. Treat values already inside a constants file as compliant (Info, not a finding).

Script: [Find-HardcodedValues.ps1](./scripts/Find-HardcodedValues.ps1)
