# C# Web Application Review Rules (baseline)

Tuned for ASP.NET Web Forms / .NET Framework projects. Each rule has an ID,
a severity, what to look for, and the fix to suggest. Severities: **Blocker**, **Major**, **Minor**, **Nit**.

## 1. Security (OWASP-aligned)

### SEC-01 SQL injection — Blocker
- **Look for:** SQL built by string concatenation/interpolation with user or external input;
  `new SqlCommand("... " + value)`; dynamic LINQ from raw strings.
- **Fix:** Use parameterized queries (`SqlParameter`), or the existing LINQ-to-SQL data context
  (`DBFeedbackDataContext`) with strongly-typed queries. Never concatenate input into SQL.

### SEC-02 Cross-site scripting (XSS) — Blocker
- **Look for:** Writing user input to the page without encoding (`Response.Write`, `<%= %>`,
  `Literal.Text`, `innerHTML`), disabled request validation, `Server.HtmlEncode` missing.
- **Fix:** HTML-encode output (`Server.HtmlEncode` / `HttpUtility.HtmlEncode`), use `<%: %>` instead of
  `<%= %>`, keep request validation enabled.

### SEC-03 Secrets in source — Blocker
- **Look for:** Hardcoded passwords, pass-keys, API tokens, connection passwords (e.g. a literal
  `passkey = "..."`). The project already has an encrypted-credential pattern (`GlobalData.cs`,
  `SecureConfigurationManager.cs`) — new secrets must use it.
- **Fix:** Move to the encrypted store / protected config / environment variable. Never commit secrets.

### SEC-04 Weak cryptography — Major
- **Look for:** `RijndaelManaged`/`MD5`/`SHA1` for new code, hardcoded IV/salt, low PBKDF2 iteration counts,
  ECB mode.
- **Fix:** Prefer `Aes`, per-value random salt/IV (already done in `GlobalData.cs`), modern iteration counts,
  CBC/GCM. Flag *new* weak usage; don't churn working legacy crypto without reason.

### SEC-05 Open redirect / SSRF — Major
- **Look for:** `Response.Redirect`/`HttpClient`/`RestClient` targets built from unvalidated input.
- **Fix:** Whitelist allowed hosts/paths; validate the URL before use.

### SEC-06 CSRF — Major
- **Look for:** State-changing POST handlers without anti-forgery protection / ViewState MAC disabled.
- **Fix:** Keep ViewState MAC enabled; add anti-forgery tokens for state-changing actions.

### SEC-07 Insecure deserialization / XXE — Major
- **Look for:** `BinaryFormatter`, `XmlDocument`/`XmlReader` with DTD processing enabled on untrusted input.
- **Fix:** Avoid `BinaryFormatter`; set `XmlResolver = null` / `DtdProcessing.Prohibit`.

## 2. Error Handling

### ERR-01 Swallowed exceptions — Major
- **Look for:** empty `catch { }`, `catch (Exception) { }` that hides failures, catch-and-continue with no log.
- **Fix:** Handle meaningfully or rethrow; log with context. Don't hide failures.

### ERR-02 Process kill in shared code — Major
- **Look for:** `Environment.Exit(...)` inside library/business code.
- **Fix:** Throw a meaningful exception and let the host decide; reserve `Exit` for the executable entry point.

### ERR-03 Catch too broad / lost context — Minor
- **Look for:** `catch (Exception e)` logging only `e.Message`.
- **Fix:** Log the full exception (`ToString()` / stack trace); catch the narrowest type that applies.

## 3. Resource Management

### RES-01 Undisposed IDisposable — Major
- **Look for:** `StreamReader`/`StreamWriter`/`FileStream`/`SqlConnection`/`HttpClient` created without
  `using`; data contexts not disposed.
- **Fix:** Wrap in `using` / `using var`; scope the DB context per unit of work.

### RES-02 HttpClient/RestClient per-call — Minor
- **Look for:** Creating a new `HttpClient` per request in a hot path.
- **Fix:** Reuse a shared client where appropriate; dispose short-lived ones.

## 4. Async / Threading

### ASY-01 async void — Major
- **Look for:** `async void` methods that are not UI event handlers.
- **Fix:** Return `Task`; let callers await and observe exceptions.

### ASY-02 Sync-over-async deadlock — Major
- **Look for:** `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` on async calls in request context.
- **Fix:** `await` the call; make the chain async end-to-end.

### ASY-03 Fire-and-forget — Minor
- **Look for:** awaitable tasks started and not awaited; unobserved exceptions.
- **Fix:** Await, or explicitly handle/observe the task.

## 5. Configuration & Constants

### CFG-01 Hardcoded configuration — Major
- **Look for:** inline UNC paths, URLs, server names, connection strings (see the `appconstants-audit` skill).
- **Fix:** Centralize in `AppConstants`/`Header`/`Constants` or `Web.config`/`App.config`.

### CFG-02 Environment coupling — Minor
- **Look for:** machine-specific assumptions (drive letters, share names) baked into logic.
- **Fix:** Read from configuration; provide sensible defaults.

## 6. Reliability & Correctness

### REL-01 Null / missing data — Major
- **Look for:** dereferencing results of `FirstOrDefault()`, `[i]`, dictionary lookups, REST responses without
  null/empty checks (common around the LINQ-to-SQL and RestSharp calls).
- **Fix:** Null-check and handle the empty/None case explicitly.

### REL-02 Unvalidated external input — Major
- **Look for:** request fields, file contents, REST payloads used without validation.
- **Fix:** Validate type/range/format at the boundary before use.

### REL-03 Resource/threading on shared statics — Minor
- **Look for:** mutable `public static` state shared across requests (e.g. a static `Jira` client) used
  without care.
- **Fix:** Ensure thread safety or scope per request.

## 7. Maintainability

### MNT-01 Naming — Nit
- PascalCase for types/methods/properties; camelCase for locals/params; `UPPER_SNAKE_CASE` for the project's
  constants. Flag clearly inconsistent names.

### MNT-02 Dead/commented code — Nit
- Remove commented-out blocks and unreachable code introduced by the change.

### MNT-03 Duplication — Minor
- Repeated logic (e.g. the same REST setup copied across methods) should be extracted to a helper.

### MNT-04 Method size / clarity — Minor
- Very long methods doing many things — suggest splitting when it aids review and testing.

## Verdict Guidance
- Any **Blocker** → CHANGES-REQUESTED.
- Multiple **Major** or an unaddressed bug/leak → CHANGES-REQUESTED.
- Only **Minor/Nit** → PASS-WITH-COMMENTS.
- Nothing of substance → PASS.
