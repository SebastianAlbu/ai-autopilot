# Bitbucket Server REST API — posting PR comments

Base URL: `$env:BITBUCKET_BASE_URL` + `/rest/api/1.0`. Auth: `Authorization: Bearer <PAT>` with **write**
permission, or domain SSO via `-UseDefaultCredentials`.

```
POST projects/{projectKey}/repos/{repoSlug}/pull-requests/{id}/comments
Content-Type: application/json
```

## The three payload shapes

**General comment** — appears in the PR's Overview tab:

```json
{ "text": "# PR Review\n\n…markdown…" }
```

**Reply** — threads under an existing comment. `parent.id` is the id of the comment being replied to
(any comment in the thread; Bitbucket nests under exactly that one):

```json
{ "text": "Fixed in 9f3ac21.", "parent": { "id": 1234 } }
```

**Inline comment** — anchored to a line in the diff:

```json
{
  "text": "[F3][Major] Null check guards the wrong branch. Fix: …",
  "anchor": {
    "path": "src/Services/OrderService.cs",
    "line": 42,
    "lineType": "ADDED",
    "fileType": "TO",
    "diffType": "EFFECTIVE"
  }
}
```

### Getting the anchor right
| Field | Value |
|---|---|
| `path` | repo-relative, forward slashes, exactly as `/changes` reports it |
| `line` | line number **in the side named by `fileType`**, not a diff-hunk offset |
| `lineType` | `ADDED` (new line) · `REMOVED` (deleted line) · `CONTEXT` (unchanged line shown in the diff) |
| `fileType` | `TO` for `ADDED`/`CONTEXT`, `FROM` for `REMOVED` — mismatching these is the usual cause of a 400 |
| `diffType` | `EFFECTIVE` — the diff Bitbucket displays for the PR |

An anchor whose `path`/`line` does not exist in the PR diff is rejected with `400`. When that happens, post
the finding in the summary comment instead of dropping it.

## Response

```jsonc
{ "id": 1234, "version": 0, "text": "…", "author": { "displayName": "…" }, "createdDate": 1710000000000 }
```

The comment link is `{base}/projects/{key}/repos/{slug}/pull-requests/{id}/overview?commentId={id}`.

## Status codes

| Code | Meaning |
|---|---|
| 400 | malformed anchor — bad `path`, a `line` not in the diff, or a `lineType`/`fileType` mismatch |
| 401 | `BITBUCKET_PAT` missing or expired |
| 403 | the PAT is read-only — posting needs *Repository: Write* |
| 404 | wrong project/repo/PR id, or `parent.id` is not a comment on this PR |

## Related

- Reading threads, and resolving them: [`bitbucket-pr-threads`](../../bitbucket-pr-threads/references/bitbucket-comments-api.md)
- Reading the PR itself: [`bitbucket-pr-context`](../../bitbucket-pr-context/references/api_examples.md)
