---
name: appconstants-audit
description: 'Check that hardcoded paths, URLs, server/UNC paths, connection strings and other configuration literals live in a centralized constants class (AppConstants.cs / Header.cs / Constants.cs / *Settings*.cs) instead of being scattered across the project. Use when reviewing C# changes for configuration centralization, magic strings, or hardcoded values that should be constants.'
argument-hint: 'path or changed files to scan'
---

# AppConstants Audit

Enforce the project convention: **all environment-specific or reused literals belong in a single constants
class**, not inline across the code base. In `mq_feedback` the constants live in
`FeedbackAsp/Functionality/Header/AppConstants.cs`, `Header.cs`, and `Constants.cs` — yet UNC paths and URLs
are still hardcoded inside `Functionality.cs`. That is exactly the smell this audit catches.

## When to Use
- Reviewing a C# diff for hardcoded paths, URLs, connection strings, IPs, or emails.
- Verifying new literals were added to a constants class rather than inline.

## What Must Be Centralized
See [appconstants-rules.md](./references/appconstants-rules.md) for the full rule set. In short, flag inline:
- UNC paths (`\\server\share\...`) and Windows drive paths (`C:\...`).
- URLs (`http://`, `https://`).
- Connection strings (`Data Source=`, `Initial Catalog=`, `Server=`, `Provider=`).
- Hardcoded IP addresses and email addresses.
- Repeated "magic" strings/numbers used as configuration.

## Procedure
1. Scan the changed files (or a folder):
   - `pwsh ./scripts/Find-HardcodedValues.ps1 -Path .\FeedbackAsp`
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
