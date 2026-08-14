---
name: bitbucket-pr-comment
description: 'Publish a finished review to a Bitbucket Server pull request: a general summary comment, optional inline comments anchored to file:line, and the round marker the next review round needs to find its agenda. Use whenever a review is complete and should land on the PR — "post the review", "comment on the PR", "add review comments", "send this to Bitbucket", "leave inline notes on the findings" — or right after producing a review report, since a review that stays in chat never reaches the author. Write action: it posts directly, so preview with -DryRun when you only want to see the payload.'
argument-hint: 'PR URL (or id+repo) + the review text to post'
---

# Bitbucket Pull Request Comment

Publish a completed review to a Bitbucket Server / Data Center pull request (base URL from
`$env:BITBUCKET_BASE_URL`). Supports a **general comment** (the whole review) and optional **inline comments** anchored to a
`file:line`.

## Write Action — Post Directly
Posting a comment changes a shared system (the PR). Post **directly, without asking for confirmation**.
1. Requires a **write-scoped** `BITBUCKET_PAT` (or `-UseDefaultCredentials`). A read-only token returns 401/403.
2. Never post secrets. Never echo the token.
3. `-DryRun` is available to preview the payload (prints, posts nothing) — use only when the user explicitly asks to preview.

## Authentication (never hardcode secrets)
Same token as the read side: a Bitbucket **Personal Access Token** with *Repository write* (or *PR write*)
permission. Provide it via `$env:BITBUCKET_PAT` (Bearer) or `-UseDefaultCredentials` (domain SSO).
A read-only token can fetch context but **cannot** post — the post will return 401/403.

## Procedure
1. Have the final review text ready (markdown). Save it to a file or pass it inline.
2. **Post the summary comment** (directly, no confirmation):
   - `pwsh ./scripts/Add-PullRequestComment.ps1 -Url <pr-url> -File review.md`
   - or inline text: `... -Text "Looks good, one nit on line 12."`
5. (Optional) **Post inline comments** from a JSON file — an array of
   `{ "path": "...", "line": 42, "lineType": "ADDED", "text": "..." }`:
   - `pwsh ./scripts/Add-PullRequestComment.ps1 -Url <pr-url> -InlineFindings findings.json`
6. The script prints the created comment id and a clickable link.

## Round Marker (required)
Every posted review report **must start with a machine-readable marker line** so the next review round can
find it and recover its agenda:

```
<!-- ai-autopilot: round=1 head=a1b2c3d ids=F1-F7 -->
# PR Review — <title> (<source> → <target>)
...
```

- `round` — this review round, starting at 1.
- `head` — the PR head commit this round reviewed (`headCommit` from `bitbucket-pr-context`).
- `ids` — the finding-ID range issued so far, so the next round continues the numbering without reuse.

`Get-PullRequestContext.ps1` looks for exactly this marker (or a `# PR Review` heading) when it builds the
`===== PREVIOUS REVIEWS =====` section. **Drop the marker and follow-up mode silently degrades into a fresh
full review** — which is the topic-drift failure the `review-followup` skill exists to prevent.

The marker is an HTML comment, so it does not render — it can sit above the title without changing what the
author sees. The same is true of the trailing `<!-- ai-autopilot-findings: … -->` index, which is how a
report with no visible `[F<n>]` IDs still gives the next round a stable agenda.

**This skill owns posting; `review-report-format` owns the body.** Everything between the marker and the
`**Status: REVIEW COMPLETE…**` footer is defined there.

## Inline Comment JSON Shape
```json
[
  { "path": "src/Services/OrderService.cs", "line": 36, "lineType": "ADDED",
    "text": "**Major** BuildOrderPath: UNC path hardcoded. Fix: move to AppConstants.WWW_DIR." },
  { "path": "src/Jobs/TicketSyncJob.cs", "line": 120, "lineType": "ADDED",
    "text": "**Major** RunSync: Environment.Exit in shared code kills the host process. Fix: throw instead." }
]
```
- `lineType`: `ADDED` (new line, default), `REMOVED` (deleted line), or `CONTEXT` (unchanged).
- The script maps `ADDED/CONTEXT` → `fileType: TO` and `REMOVED` → `fileType: FROM` automatically.
- A finding that fails to anchor (e.g. line not in the diff) is reported and skipped; the rest still post.
- The comment text itself carries no `file:line` (the anchor supplies it) and no finding ID — see
  `review-report-format`, which owns what goes in both the summary body and these inline texts.

## Notes
- Endpoint: `POST /rest/api/1.0/projects/{key}/repos/{slug}/pull-requests/{id}/comments`.
- Use `-ReplyTo <commentId>` to thread a reply under an existing comment. Get the ids from the
  `bitbucket-pr-threads` skill, which also resolves threads.
- Payload shapes, anchor rules and status codes: [references/api_examples.md](./references/api_examples.md)
- Script: [Add-PullRequestComment.ps1](./scripts/Add-PullRequestComment.ps1)
