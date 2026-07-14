---
name: jira-ticket-read
description: 'Read a Jira ticket from Marquardt Jira (jira.marquardt.de) using the same REST v2 mechanism the mq_feedback app uses to create and read tickets. Use when a pull request links a Jira key (e.g., TDST-123), when you need the ticket summary, description, type, status, acceptance criteria, or Definition of Done to compare against code changes. Extracts the issue key from a key or a browse URL.'
argument-hint: 'Jira key (TDST-123) or browse URL'
---

# Jira Ticket Read

Fetch a Jira issue so a reviewer can check whether the code change actually does what the ticket asked.
This mirrors the `mq_feedback` application (see `FeedbackJiraandDBUpdate/Functionality.cs`), which talks to
`https://jira.marquardt.de/rest/api/2/issue/{key}` with HTTP Basic auth. The feedback app **creates** these
tickets; this skill **reads** them back for review.

## When to Use
- A PR / branch / commit references a Jira key (pattern `[A-Z][A-Z0-9]+-\d+`, e.g. `TDST-123`).
- You need the ticket's summary, description, issue type, status, labels, priority, or comments.
- You want to verify the diff satisfies the ticket's intent and Definition of Done.

## Authentication (never hardcode secrets)
The feedback app stores encrypted Basic-auth credentials. For the agent, prefer a **Personal Access Token**:

| Method | How |
|--------|-----|
| PAT (recommended) | `-Token <pat>` or `$env:JIRA_PAT` → sent as `Authorization: Bearer` |
| Basic (parity with mq_feedback) | `-User <u> -Password <p>` → `Authorization: Basic` |
| Domain SSO | `-UseDefaultCredentials` |

Do not commit tokens. Do not print credentials.

## Procedure
1. Get the issue key. If you only have a URL like `https://jira.marquardt.de/browse/TDST-123`,
   the script extracts the key automatically.
2. Run the reader:
   - `pwsh ./scripts/Get-JiraTicket.ps1 -TicketKey TDST-123`
   - or `pwsh ./scripts/Get-JiraTicket.ps1 -Url https://jira.marquardt.de/browse/TDST-123`
3. Read the JSON output: `summary`, `type`, `status`, `priority`, `labels`, `assignee`, `description`, `comments`.
4. From the `description`, extract the **acceptance criteria** and the **Definition of Done** checklist
   (the feedback app templates use lines like `( ) Code changes completed and reviewed`,
   `( ) Tests written and passing`, `( ) CI pipeline passing`, `( ) Documentation updated`).
5. Compare the ticket intent against the diff and report alignment / gaps.

## Output Mapping
The script returns the same fields the feedback app reads/writes, so a reviewer can map:
- ticket `summary` + `description` → expected behavior
- issue `type` (Bug / Improvement / Support) → expected kind of change
- `status` / `resolution` → whether the ticket is still open

Script: [Get-JiraTicket.ps1](./scripts/Get-JiraTicket.ps1)
