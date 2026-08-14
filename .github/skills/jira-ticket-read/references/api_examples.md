# Jira Server / Data Center REST API — reading an issue

Base URL: `$env:JIRA_BASE_URL`. REST **v2** (Server/Data Center). Jira Cloud's v3 uses ADF documents for
rich text and is *not* what this skill talks to.

Auth precedence: `-Token` → `$env:JIRA_PAT` (both `Authorization: Bearer`) → `-User` + `-Password`
(Basic) → `-UseDefaultCredentials` (domain SSO).

## Read an issue

```
GET /rest/api/2/issue/{key}?fields=summary,description,issuetype,status,priority,labels,assignee,reporter,resolution,fixVersions,created,updated,comment
```

Always pass `fields=` — the unfiltered response includes every custom field on the instance and is an order
of magnitude larger, most of it irrelevant to a review.

```jsonc
{
  "key": "PROJ-123",
  "fields": {
    "summary": "…",
    "description": "…",                  // wiki markup / plain text on Server, NOT ADF
    "issuetype": { "name": "Story" },
    "status":    { "name": "In Progress" },
    "priority":  { "name": "Major" },
    "labels":    [ "…" ],
    "assignee":  { "displayName": "…" },
    "reporter":  { "displayName": "…" },
    "resolution": null,
    "fixVersions": [ { "name": "1.4.0" } ],
    "created": "2026-01-31T09:12:00.000+0100",
    "updated": "2026-02-04T16:45:00.000+0100",
    "comment": { "comments": [ { "author": {…}, "body": "…", "created": "…" } ] }
  }
}
```

## Where acceptance criteria actually live

There is no standard field. In order of likelihood:

1. a heading inside `description` (`h2. Acceptance Criteria`, `*AC:*`, a checklist);
2. a **custom field** (`customfield_1xxxx`) — request it by id via `fields=` once you know it;
3. the comments.

Never report "no acceptance criteria" without checking the description body and the comments. Say which one
you used as the source.

## Issue keys

A key matches `[A-Z][A-Z0-9]+-\d+`. `Get-JiraTicket.ps1` extracts it from any URL shape
(`/browse/PROJ-123`, `?selectedIssue=PROJ-123`, …), so a pasted link works as well as a bare key.

## Status codes

| Code | Meaning |
|---|---|
| 401 | `JIRA_PAT` missing or expired (Jira PATs expire — often after 90 days) |
| 403 | authenticated but no *Browse Projects* permission on that project |
| 404 | no such issue key — or the token cannot see the project (Jira returns 404, not 403, for invisible issues) |

## Related fields worth requesting

`issuelinks` (blocks / is blocked by), `subtasks`, `parent` (for a sub-task's story), `components`. Add them
to `-Fields` when the review needs the wider ticket context, not by default — each one costs response size.
