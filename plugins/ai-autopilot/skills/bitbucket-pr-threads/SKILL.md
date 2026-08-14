---
name: bitbucket-pr-threads
description: 'Read, reply to and resolve the review comment threads on a Bitbucket Server pull request — inline (file:line) and general comments, with thread state, the TASK/blocker flag, replies and the comment ids. Use whenever reviewer feedback is in play: "what did the reviewers say", "read the PR comments", "show unresolved comments", "reply to that comment", "mark it resolved", "address the review feedback", or before writing a review, so findings a human already raised are not reported twice. Reading is read-only; replying and resolving are write actions.'
argument-hint: 'PR URL (or id+repo), optionally a comment id to reply to / resolve'
---

# Bitbucket Pull Request Comment Threads

The **incoming** side of a review, complementing `bitbucket-pr-comment` (which only posts). Base URL from
`$env:BITBUCKET_BASE_URL`; the host and project key are read from a pasted PR link when you use `-Url`.

## What you get
- Every comment **thread** on the PR: inline ones anchored to `path:line`, and `GENERAL` ones.
- Per thread: state (`OPEN` / `RESOLVED` / `PENDING`), the `TASK` flag, and every reply, indented.
- The **comment id** of each entry — required to reply or resolve.

```
=== [src/Services/OrderService.cs:36] [TASK/OPEN]
  #1234 v0 Fabian: This UNC path should live in AppConstants.
      #1240 v0 You: Moved to AppConstants.WWW_DIR in 9f3ac21.
------------------------------------------------------------
```

## Procedure

### Read
```powershell
pwsh ./scripts/Get-PullRequestComments.ps1 -Url <pr-url>                 # every thread
pwsh ./scripts/Get-PullRequestComments.ps1 -Url <pr-url> -Unresolved     # what still needs work
pwsh ./scripts/Get-PullRequestComments.ps1 -Url <pr-url> -Tasks          # blockers only
pwsh ./scripts/Get-PullRequestComments.ps1 -Url <pr-url> -Json           # machine-readable
```
Also `-Author <name>`, and id mode: `-PullRequestId 42 -Repo my-repo [-Project KEY]`.

### Reply
Reuses the poster from the `bitbucket-pr-comment` skill — `-ReplyTo` threads it under an existing comment:
```powershell
pwsh ../bitbucket-pr-comment/scripts/Add-PullRequestComment.ps1 `
    -Url <pr-url> -ReplyTo 1234 -Text "Fixed in 9f3ac21 — moved to AppConstants.WWW_DIR."
```

### Resolve / reopen
```powershell
pwsh ./scripts/Set-PullRequestCommentState.ps1 -Url <pr-url> -CommentId 1234 -State RESOLVED
pwsh ./scripts/Set-PullRequestCommentState.ps1 -Url <pr-url> -CommentId 1234 -State OPEN
```
Write action — needs a **write-scoped** `BITBUCKET_PAT`. `-DryRun` previews without changing anything.

## The Review Loop
When the user says reviewers left comments:

1. **Read.** `-Unresolved` first. Each thread shows the file and line (or `GENERAL`), whether it is a `TASK`
   (a blocker the reviewer expects addressed), its state, every reply, and the comment id.
2. **Understand before changing.** Open each referenced file at the given line. A reviewer comment is a
   request to understand intent, not a literal patch spec. If a comment is unclear or you disagree, say so in
   a reply instead of guessing — surfacing the disagreement is more useful than a wrong fix.
3. **Fix.** Change the working tree. Group related comments into coherent commits and reference the ticket
   key in the message, matching the repo's convention.
4. **Reply, then resolve.** Reply describing what changed (name the short sha once pushed), then resolve.
   Resolve only once the change is actually made.
5. **Push and report.** Say which comments you addressed, which you pushed back on, and what still needs the
   user's input.

**Never resolve a partially addressed comment.** Half-fixing and then resolving hides the remainder from the
reviewer — worse than leaving the thread open. Prefer letting the reviewer resolve threads where they asked a
*question* rather than requested a change; when unsure, reply and leave it open.

## Using it while reviewing
- **Before writing a review:** read the existing threads. A finding a human reviewer already raised is not a
  new finding — reference the thread instead of reporting it again.
- **In follow-up rounds (`review-followup`):** the previous round's findings are the agenda. Reply to each
  finding's thread with its verdict and resolve the ones verified `FIXED`, so the PR converges visibly in
  Bitbucket instead of only in chat.

## Notes
- Comments come from the PR **activities** feed (`action = COMMENTED`), which emits an entry for every
  comment *including replies*, each carrying the full reply tree. The script keeps only thread roots, so a
  reply is never listed as its own thread.
- The **root** comment carries the thread's `state`; `severity = BLOCKER` is what the UI calls a **task**.
- Resolving edits the comment and therefore needs its current `version`; the script fetches it first and
  retries once on `409` (stale version). A `404` on resolve usually means the id is a reply, not the root.
- Endpoints and response shapes: [references/bitbucket-comments-api.md](./references/bitbucket-comments-api.md)
- Scripts: [Get-PullRequestComments.ps1](./scripts/Get-PullRequestComments.ps1),
  [Set-PullRequestCommentState.ps1](./scripts/Set-PullRequestCommentState.ps1)
