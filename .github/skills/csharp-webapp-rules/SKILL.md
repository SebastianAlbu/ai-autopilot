---
name: csharp-webapp-rules
description: 'Review rules for C# web applications (ASP.NET Web Forms / .NET Framework) as used in the Marquardt TDST and mq_feedback projects. Covers the C# Coding Guidelines & Best Practices v1.0 (naming conventions, control prefixes, indentation/comments, good programming practices, N-tier architecture) PLUS security (OWASP Top 10, SQL injection, XSS, secrets), error handling, resource disposal/using, async correctness, configuration, input validation, logging and naming. Use when reviewing C# / ASP.NET (Visual Studio) code in a pull request.'
argument-hint: 'changed C# files to review'
---

# C# Web Application Review Rules

Review rules for C#/ASP.NET (Visual Studio) changes. Two reference sets, applied together:
1. **[C# Coding Guidelines & Best Practices v1.0](./references/csharp-coding-guidelines.md)** — naming,
   formatting, good practices, architecture (rule IDs `CS-*`).
2. **[Web-app baseline rules](./references/csharp-webapp-rules.md)** — security, error handling, resources,
   async, reliability (rule IDs `SEC-*`, `ERR-*`, `RES-*`, `ASY-*`, `REL-*`, `MNT-*`).

These are tuned to what the codebase uses (ASP.NET Web Forms, LINQ-to-SQL / ADO.NET, RestSharp, file IO,
custom crypto). Apply to the changed lines; don't demand churn of untouched legacy code.

## When to Use
- Reviewing a **C# / ASP.NET (Visual Studio)** diff in a pull request (`.sln`/`.csproj`/`*.cs`/`*.aspx`).
- Checking naming/style/architecture **and** security, resource leaks, error-handling and async problems.
- (For embedded **SPLE / VS Code** projects — CMake/C/C++/Python — use the `sple-standards` skill instead.)

## How to Apply
1. Read both rule sets:
   - [csharp-coding-guidelines.md](./references/csharp-coding-guidelines.md) (CS-* naming/style/architecture).
   - [csharp-webapp-rules.md](./references/csharp-webapp-rules.md) (SEC/ERR/RES/ASY/REL/MNT).
2. Walk the diff hunk by hunk. For each changed file, check the relevant rule categories below.
3. Report findings with a severity and a concrete fix. Cite `file:line` and the rule ID.

## Rule Categories (summary)
- **Naming & style (Major/Minor/Nit — CS-NAME/CS-FMT):** PascalCase types/methods, `I`-prefixed interfaces,
  camelCase locals, `_`-prefixed private fields, `is/has/can` booleans, UI control prefixes (`lbl`,`txt`,`btn`…),
  one statement per line, XML doc comments, `#region` ordering.
- **Good practices (Major/Minor — CS-PRAC):** method ≤ 40–50 lines, class ≤ 600–700 lines, single
  responsibility, language aliases (`int`/`string`), `String.Empty`, enums over magic values, null checks,
  `using` over try/finally+Dispose, specific exceptions, `StringBuilder` in loops, `Any()` over `Count>0`,
  `IEnumerable<T>`/`IList<T>` over concrete lists, thin event handlers, brace all control statements.
- **Architecture (Major/Minor — CS-ARCH):** N-tier separation, no DB from UI, stored procedures + transactions,
  SOLID/DRY, no large objects in Session/ViewState.
- **Security (Blocker/Major):** parameterized queries (no string-concatenated SQL), encode output (XSS),
  validate/whitelist input, no secrets in source, validate redirects, safe deserialization, CSRF protection.
- **Error handling (Major):** no empty `catch`, don't swallow exceptions, no `Environment.Exit` in library
  code, fail loud with context, don't catch `Exception` just to log-and-continue silently.
- **Resource management (Major):** `using` / `await using` for `IDisposable` (streams, DB connections,
  HttpClient/RestClient handling), no leaked file handles.
- **Async (Major):** no `async void` (except event handlers), no `.Result`/`.Wait()` blocking on async,
  flow `CancellationToken`, `ConfigureAwait` where relevant in library code.
- **Configuration (Major):** environment values come from config/constants (see `appconstants-audit`),
  not inline literals.
- **Reliability (Minor/Major):** null-checks on external data, guard against `NullReferenceException`,
  validate collection access, dispose/scope database contexts.

## Output
For each issue:
`[Severity] file:line — <rule>: <what's wrong>. Fix: <concrete suggestion>.`

Severities: **Blocker** (security/data loss), **Major** (bug/leak/maintainability risk), **Minor**, **Nit**.
End with a short verdict: PASS / PASS-WITH-COMMENTS / CHANGES-REQUESTED for this category.
