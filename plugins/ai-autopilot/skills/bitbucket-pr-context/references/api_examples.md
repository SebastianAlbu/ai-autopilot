# Bitbucket Server REST API — pull request context

Base URL: `$env:BITBUCKET_BASE_URL` + `/rest/api/1.0` (or the host of a pasted PR link).
Auth: `Authorization: Bearer <PAT>` (HTTP access token), or domain SSO via `-UseDefaultCredentials`.
All paths below are prefixed with `projects/{projectKey}/repos/{repoSlug}/pull-requests/{id}`.

Read-only — every call here is a `GET`. Posting is `bitbucket-pr-comment`; reading and resolving reviewer
threads is `bitbucket-pr-threads`.

## PR metadata

```
GET  (the PR itself)
```

```jsonc
{
  "id": 42,
  "title": "…",
  "description": "…",
  "state": "OPEN",                       // OPEN | MERGED | DECLINED
  "fromRef": { "displayId": "feature/X", "latestCommit": "a1b2c3d…" },
  "toRef":   { "displayId": "develop" },
  "author":  { "user": { "displayName": "…" } },
  "reviewers": [ { "user": {…}, "approved": false, "status": "UNAPPROVED" } ],
  "links": { "self": [ { "href": "https://…/pull-requests/42" } ] }
}
```

`fromRef.latestCommit` is the PR **head** — the commit a review round records so the next round can compute
the incremental diff.

## Changed files

```
GET  /changes?limit=1000&start={n}
```

Paginated (`values[]`, `isLastPage`, `nextPageStart`). Each value carries `path.toString` and `type`
(`ADD` | `MODIFY` | `DELETE` | `MOVE` | `COPY`).

## Unified diff

```
GET  .diff?contextLines={n}
```

Returns **plain text**, not JSON — request it raw. `contextLines` trades context for size; the review flow
needs enough to reason about the surrounding code but not the whole file.

## Activity feed

```
GET  /activities?limit=100&start={n}
```

Paginated. `action` is `OPENED` | `UPDATED` | `APPROVED` | `COMMENTED` | `MERGED` | `DECLINED` | `RESCOPED`.

`Get-PullRequestContext.ps1` keeps only `COMMENTED` entries whose text is one of **this system's own**
comments (`<!-- ai-autopilot` marker, or a `# PR Review` heading) — that is how a follow-up round finds its
previous report. **Human reviewer comments are deliberately excluded here**; read those with
`bitbucket-pr-threads`, which understands thread roots, replies and resolution state.

## Branch fallback

With no token, or when REST fails, the skill diffs the local checkout instead:

```
git diff --unified=<n> <target>...<source>
git diff --name-status <target>...<source>
```

The three-dot form diffs against the merge base, which is what Bitbucket shows — a two-dot diff would also
include commits the target branch gained since the PR was opened.

## Status codes

| Code | Meaning |
|---|---|
| 401 | `BITBUCKET_PAT` missing, expired, or malformed |
| 403 | the PAT is valid but lacks read access to that project/repo |
| 404 | wrong project key, repo slug or PR id — or the PAT cannot see the repo at all (Bitbucket hides what you may not read) |
