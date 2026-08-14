# Bitbucket Server REST API — PR comment threads

Base URL: `$env:BITBUCKET_BASE_URL` + `/rest/api/1.0` (or the host of a pasted PR link).
Auth: `Authorization: Bearer <PAT>` (HTTP access token), or domain SSO via `-UseDefaultCredentials`.
All paths below are prefixed with `projects/{projectKey}/repos/{repoSlug}`.

## Read comments

```
GET /pull-requests/{id}/activities?limit=100&start={n}
```

Paginated: the response carries `values[]`, `isLastPage` and `nextPageStart`.

Keep entries with `action == "COMMENTED"`. Each one has:

- `comment`
  - `id`, `version`, `text`, `author.displayName`
  - `state` — `OPEN` | `RESOLVED` | `PENDING`. Only the **thread root** carries a meaningful state.
  - `severity` — `NORMAL` | `BLOCKER`. `BLOCKER` is what the UI calls a **task**.
  - `comments[]` — nested replies, recursive, each with the same shape.
- `commentAnchor` (inline comments only) — `path`, `line`, `lineType` (`ADDED` / `REMOVED` / `CONTEXT`),
  `fileType`. General PR comments have no anchor.

> **Gotcha.** The feed emits a `COMMENTED` entry for *every* comment, replies included, and each entry
> already carries the full current reply tree. A reply therefore appears twice — nested under its parent and
> again as its own entry. Collect all nested ids first, then keep only comments that are nobody's reply.

## Post a comment / reply

```
POST /pull-requests/{id}/comments
{ "text": "..." }                              # general comment
{ "text": "...", "parent": { "id": <id> } }    # reply inside a thread
{ "text": "...", "anchor": { "path": "...", "line": 42,
                             "lineType": "ADDED", "fileType": "TO",
                             "diffType": "EFFECTIVE" } }   # inline comment
```

Handled by `bitbucket-pr-comment/scripts/Add-PullRequestComment.ps1` (`-Text` / `-File` / `-InlineFindings` /
`-ReplyTo`).

## Resolve / reopen a thread

Resolving edits the comment, so the current `version` is required — fetch it first:

```
GET /pull-requests/{id}/comments/{commentId}      -> { "version": N, ... }
PUT /pull-requests/{id}/comments/{commentId}
{ "version": N, "state": "RESOLVED" }             # or "OPEN" to reopen
```

- `409 Conflict` — the `version` is stale (the thread changed in between). Re-fetch and retry.
- `404 Not Found` — usually the id is a **reply**, not the thread root. Only roots have a state.
- `401` / `403` — the PAT is missing, expired, or read-only. Resolving needs *Repository: Write*.
