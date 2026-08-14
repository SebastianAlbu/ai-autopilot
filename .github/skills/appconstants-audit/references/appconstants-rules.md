# AppConstants Centralization Rules

The goal: a reviewer can look at one place and know every path, endpoint and secret-bearing string the
application depends on. Scattered literals make environment changes risky and error-prone.

## Where Constants Live
Match the existing project structure. Typically these are:

| File | Purpose |
|------|---------|
| `Functionality/Header/AppConstants.cs` | Server dirs, DB name/connection, team lists |
| `Header.cs` | Cross-cutting endpoints (e.g. `JIRA`), template/attachment paths, limits |
| `Constants.cs` | UI/label text and template fragments |
| `*Settings*.cs` / `App.config` / `Web.config` | Per-environment configuration |

A new project should have an equivalent single `AppConstants` (or `Constants`) class.

## Must Be Centralized (flag if inline elsewhere)
1. **UNC paths** — `\\mqde01sdss01\ToolLogs\...`
2. **Windows drive paths** — `C:\repo\...`, `D:\data\...`
3. **URLs / endpoints** — `https://jira.example.com/`, `https://bitbucket.example.com/`, `https://docs.example.com/...`
4. **Connection strings** — anything with `Data Source=`, `Initial Catalog=`, `Server=`, `Provider=`.
5. **Server / host names** — `mqde01sdss01`.
6. **IP addresses** — `10.x.x.x`, `192.168.x.x`, etc.
7. **Email addresses / distribution lists** used as configuration.
8. **Repeated magic strings/numbers** — labels, status names, limits used in more than one place.

## Naming & Style
- `public static` (or `const` for compile-time constants) using `UPPER_SNAKE_CASE`, matching the existing files.
- Build derived values by composing other constants (the project already does this, e.g.
  `TOOLS_LOGS_DIR = SERVER_DIR + @"ToolLogs\"`).
- Group related constants with a short comment header.

## Acceptable Exceptions (do NOT flag)
- Literals **inside** a constants file (`AppConstants.cs`, `Header.cs`, `Constants.cs`, `*Settings*.cs`).
- Auto-generated / designer files (`*.designer.cs`, `*.g.cs`, `AssemblyInfo.cs`).
- Pure framework URLs in comments or scaffolding (e.g. `https://go.microsoft.com/fwlink/...`).
- Test fixtures and sample data clearly scoped to a unit test.
- Format strings / placeholders with no environment meaning (e.g. `"{0}-{1}"`).

## Secrets — escalate, don't just relocate
If a literal is a **credential, password, API token, or pass-phrase** (e.g. a hardcoded pass-key), do not
merely suggest moving it to a constant. Flag it as a **Blocker**: secrets must come from a secret store,
encrypted file, environment variable, or protected configuration — never from source, including a constants
class. (See `GlobalData.cs` / `SecureConfigurationManager.cs` for the encrypted-credential pattern already
used in the project.)

## How to Word a Finding
> `[Major] Functionality.cs:36 — UNC path hardcoded inline ("\\mqde01sdss01\Y\WWW\leftmenu.html"). Move to AppConstants (e.g. AppConstants.WWW_DIR + "leftmenu.html").`

Always name the suggested constant and the target class so the author can act immediately.
