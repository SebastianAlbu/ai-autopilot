# Worked example

A round-1 review of a C# migration PR, showing every section. Copy the *shape*, not the content.
Placeholders (`<vault-key>`, `db.example.internal`) stand in for real values on purpose — a review report
is a public artefact and must never quote a live secret back into the PR, even one it is reporting as a
finding. Cite the location and name the kind of secret; never reproduce its value.

---

````markdown
<!-- ai-autopilot: round=1 head=a1b2c3d ids=F1-F14 -->
# PR Review — Bugfix/ABC-1234 workers not functioning after migration (bugfix/ABC-1234-workers → master)

Jira: ABC-1234   |   Files changed: 115   |   Project type: csharp-visualstudio   |   Verdict: **CHANGES REQUESTED**

## Summary

This PR migrates the ticket integration from the deprecated vendor SDK to direct REST calls over
`HttpClient`. The refactoring meets the core requirement, but the implementation introduces **resource
leaks** (`HttpResponseMessage` and `StreamContent` never disposed), **async/await anti-patterns**
(`.GetAwaiter().GetResult()` on the main call chain), **missing null validation** on deep property chains,
and **hardcoded configuration** including a credential in source. These issues must be resolved before merge.

## Findings by Area

### Functionality            **CHANGES**
- **Blocker** Program.cs:537 — ResolveAssigneeAccountId: `HttpResponseMessage` never disposed; the early
  returns leak the connection. Fix: wrap the response in a `using` statement.
- **Blocker** Program.cs:615 — FindExistingIssue: response from `PostAsync()` never disposed; the exception
  path leaks. Fix: use a `using (response)` block.
- **Major** Program.cs:773 — UploadAttachments: the `FileStream` from `File.OpenRead()` inside
  `StreamContent` has no lifecycle management, so an exception mid-loop leaks it, and the
  `HttpRequestMessage` is never disposed either. Fix: wrap both in try-finally.
- **Major** Program.cs:810-815 — silent `catch` with a bare `return` swallows the error; a failed upload
  looks identical to a successful one. Fix: log the exception before returning.
- **Minor** Program.cs:569 — returns `null` on resolution failure, and the caller silently skips the
  assignee. Fix: log a warning so the skip is visible.

### PR Description Match      **COMMENTS**
- **Major** GlobalData.cs deletion undisclosed: the file holding the encryption logic is deleted, and the
  description does not say where credential handling moved. Clarify the migration strategy.
- **Major** Authentication redesigned: `Main()` replaces `Authenticate()` with `AuthenticateAsync()` using
  OAuth2 client credentials. The description says "replaced SDK", not that authentication changed shape.
- **Minor** CreateTicket signature changed: a new `HttpClient client` parameter is not mentioned.

### Jira Ticket Alignment     **COMMENTS**
- ✅ Core requirement met: the vendor SDK is replaced with REST calls over `HttpClient`.
- ✅ OAuth2 client-credentials authentication implemented.
- ✅ Proxy configuration support added — critical for the enterprise network post-migration.
- ⚠️ **Incomplete refactoring**: Functionality.cs:73 still imports the removed SDK namespace.
- ⚠️ **Assignee email assumption**: Program.cs:1003-1005 assumes every user has an email; no fallback if null.

### AppConstants / Config     **CHANGES**
- **Blocker** Configuration/SecretGenerator.cs:13 — an encrypted database password is embedded as a string
  literal in source. **Security violation** — it is in git history from this commit onward. Fix: remove it
  entirely and read the credential from the vault or the environment; rotate the password, since committing
  it counts as disclosure.
- **Major** Configuration/SecureConfigurationManager.cs:14 — database server `"db.example.internal"`
  hardcoded. Fix: use the `Header.SERVER_NAME` constant.
- **Major** Program.cs:271 — proxy URL hardcoded. Fix: move to `Header.DEFAULT_PROXY_URL`.
- **Major** Program.cs:371, 394, 420, 428 — OAuth token endpoint hardcoded in four places. Fix: move to
  `Header.AUTH_TOKEN_URL`.
- **Minor** Program.cs:136, 156 — document-format literals (`"paragraph"`, `"doc"`, `"text"`) hardcoded.
  Fix: move to `Header.ADF_TYPE_*` constants.

### Coding Standards (C# Web App Rules)  **CHANGES**
- **Blocker** Program.cs:1125 — Main calls `AuthenticateAsync().GetAwaiter().GetResult()`, defeating
  async/await and risking a deadlock. Fix: make `Main` an `async Task` and await properly.
- **Major** Program.cs:1010 — no null validation on the chained access `ticket.Application.User.Project`.
  Fix: guard each hop, or use null-conditional access with an explicit failure path.
- **Major** Program.cs:835 — inconsistent null-safety: `String.IsNullOrEmpty()` after `TrimStart()` here,
  `IsNullOrWhiteSpace()` elsewhere. Fix: pick one pattern.
- **Minor** Program.cs:901 — indentation inconsistent with the file. Fix: 4-space indents.

## Blockers (must fix before merge)

1. **Hardcoded credential in SecretGenerator.cs** (Configuration/SecretGenerator.cs:13) — the password must
   be removed from source and read from the vault or environment. Because the value is now in git history,
   removing the line is not sufficient: rotate the credential too.

2. **HttpResponseMessage resource leaks** (Program.cs:537, 615, 648, 671, 693, 706, 780) — every HTTP
   response must be disposed in a `using` statement or try-finally. Without disposal the TCP connections
   stay held until GC, which is what exhausts the connection pool under load.

3. **Async/await anti-pattern with blocking calls** (Program.cs:1060, 1125) — the `.GetAwaiter().GetResult()`
   calls block the async chain and can deadlock. Convert `Main` to `async Task` and await through.

4. **Hardcoded API endpoints and proxy URL** (Program.cs:177, 271, 371, 394, 412, 413, 420, 428) — base
   URL, OAuth endpoints, audience and grant type are all literals. Move them to `Header.cs` constants so
   the deployment environment is configurable.

5. **Missing null validation on property chains** (Program.cs:1010) — `ticket.Application.User` and
   `ticket.Variant.Spl.User.email` will throw on any incomplete record. Add guards.

## Nice-to-have

- Consider an `IHttpClientFactory` / dependency-injected `HttpClient` to remove the repeated instantiation
  and disposal boilerplate.
- Add logging around the attachment retry so post-migration success rates are measurable.
- Add unit tests for the OAuth2 flow and the proxy fallback — the two paths that only fail in production.

---

**Status: REVIEW COMPLETE. Verdict: CHANGES REQUESTED**

<!-- ai-autopilot-findings:
F1 Functionality Program.cs:537 Blocker
F2 Functionality Program.cs:615 Blocker
F3 Functionality Program.cs:773 Major
F4 Functionality Program.cs:810 Major
F5 Functionality Program.cs:569 Minor
F6 Description GlobalData.cs Major
F7 Description Program.cs:1125 Major
F8 Description Program.cs:648 Minor
F9 AppConstants Configuration/SecretGenerator.cs:13 Blocker
F10 AppConstants Configuration/SecureConfigurationManager.cs:14 Major
F11 AppConstants Program.cs:271 Major
F12 Standards Program.cs:1125 Blocker
F13 Standards Program.cs:1010 Major
F14 Standards Program.cs:835 Major
-->
<!-- ai-autopilot-coverage: overall=94% lowest=Standards passes=3 -->
````

---

## What to notice

**Twelve Functionality findings, five listed.** The example is trimmed; a real report lists them all. What
does not change is that seven `HttpResponseMessage` leaks collapse into **one** numbered blocker.

**The Blockers section is not a copy.** Compare blocker 2 with F1/F2: the per-finding lines say what and
where, the blocker says *why it matters* ("exhausts the connection pool under load") and covers all seven
locations at once. Blocker 1 adds an action the per-finding line did not have — rotate the credential.

**Severity is about consequence, not category.** The undisposed response is a Blocker because it leaks a
connection on every call; the inconsistent indentation is a Minor because nothing breaks. Two findings in
the same file, four severities apart.

**The Jira section never says "Blocker".** It says whether each ticket requirement is met. A defect found
while checking the ticket belongs in Functionality, not here.

**Findings not tied to a line still carry a file.** `GlobalData.cs deletion undisclosed` has no line —
correct, the file is gone. It gets no inline comment, only the summary entry.
