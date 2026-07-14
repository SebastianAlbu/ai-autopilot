---
name: bitbucket-pr-comment
description: 'Post a review back to a Bitbucket Server pull request for the Marquardt TDST projects (git.marquardt.de): a general summary comment and/or inline file:line comments, via the Bitbucket REST API. Use after a PR review to publish the findings, or when asked to "post the review", "comment on the PR", or "add review comments". Write action — preview first and confirm before posting.'
argument-hint: 'PR URL (or id+repo) + the review text to post'
---

# Bitbucket Pull Request Comment

Publish a completed review to a Bitbucket Data Center pull request on `https://git.marquardt.de` (project key
`TDST`). Supports a **general comment** (the whole review) and optional **inline comments** anchored to a
`file:line`.

## ⚠️ This Is a Write Action
Posting a comment changes a shared system (the PR). Always:
1. **Preview first** with `-DryRun` (prints the exact payload, posts nothing).
2. **Confirm with the user** before posting for real.
3. Never post secrets. Never echo the token.

## When to Use
- The PR Review Orchestrator (or a user) has a finished review and wants it on the PR.
- You need to add inline comments for specific findings.

## Authentication (never hardcode secrets)
Same token as the read side: a Bitbucket **Personal Access Token** with *Repository write* (or *PR write*)
permission. Provide it via `$env:BITBUCKET_PAT` (Bearer) or `-UseDefaultCredentials` (domain SSO).
A read-only token can fetch context but **cannot** post — the post will return 401/403.

## Procedure
1. Have the final review text ready (markdown). Save it to a file or pass it inline.
2. **Preview** (no post):
   - `pwsh ./scripts/Add-PullRequestComment.ps1 -Url <pr-url> -File review.md -DryRun`
3. Confirm the content with the user.
4. **Post the summary comment**:
   - `pwsh ./scripts/Add-PullRequestComment.ps1 -Url <pr-url> -File review.md`
   - or inline text: `... -Text "Looks good, one nit on line 12."`
5. (Optional) **Post inline comments** from a JSON file — an array of
   `{ "path": "...", "line": 42, "lineType": "ADDED", "text": "..." }`:
   - `pwsh ./scripts/Add-PullRequestComment.ps1 -Url <pr-url> -InlineFindings findings.json`
6. The script prints the created comment id and a clickable link.

## Inline Comment JSON Shape
```json
[
  { "path": "FeedbackAsp/Functionality/Source/Functionality.cs", "line": 36, "lineType": "ADDED",
    "text": "[Major] UNC path hardcoded — move to AppConstants.WWW_DIR." },
  { "path": "FeedbackCreateTickets/Functionality.cs", "line": 120, "lineType": "ADDED",
    "text": "[Major] Environment.Exit in shared code — throw instead." }
]
```
- `lineType`: `ADDED` (new line, default), `REMOVED` (deleted line), or `CONTEXT` (unchanged).
- The script maps `ADDED/CONTEXT` → `fileType: TO` and `REMOVED` → `fileType: FROM` automatically.
- A finding that fails to anchor (e.g. line not in the diff) is reported and skipped; the rest still post.

## Notes
- Endpoint: `POST /rest/api/1.0/projects/{key}/repos/{slug}/pull-requests/{id}/comments`.
- Use `-ReplyTo <commentId>` to thread a reply under an existing comment.
- Script: [Add-PullRequestComment.ps1](./scripts/Add-PullRequestComment.ps1)
