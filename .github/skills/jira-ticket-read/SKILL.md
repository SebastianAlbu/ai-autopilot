---
name: jira-ticket-read
description: 'Read a Jira ticket from a Jira Server / Data Center instance over REST v2 and return its summary, type, status, description, acceptance criteria, Definition of Done checklist, labels, priority and comments. Use whenever a key like PROJ-123 appears in a branch name, PR title, description or commit message, or when asked to "check the ticket", "does this match the ticket", "what does PROJ-123 say", "read the acceptance criteria", or to verify a change satisfies what was asked. Accepts a bare key or a browse URL. Reading the ticket beats inferring intent from the diff — the acceptance criteria and DoD are usually the only place the real requirements are written down.'
argument-hint: 'Jira key (PROJ-123) or browse URL'
---

# Jira Ticket Read

Fetch a Jira issue so a reviewer can check whether the code change actually does what the ticket asked.
It talks to `<jira-base-url>/rest/api/2/issue/{key}` (base URL from `$env:JIRA_BASE_URL`) with a PAT or
HTTP Basic auth. Ticketing/feedback tooling typically **creates** these
tickets; this skill **reads** them back for review.

## Authentication (never hardcode secrets)
The feedback app stores encrypted Basic-auth credentials. For the agent, prefer a **Personal Access Token**:

| Method | How |
|--------|-----|
| PAT (recommended) | `-Token <pat>` or `$env:JIRA_PAT` → sent as `Authorization: Bearer` |
| Basic | `-User <u> -Password <p>` → `Authorization: Basic` |
| Domain SSO | `-UseDefaultCredentials` |

Do not commit tokens. Do not print credentials.

## Procedure
1. Get the issue key. If you only have a URL like `https://jira.example.com/browse/PROJ-123`,
   the script extracts the key automatically.
2. Run the reader:
   - `pwsh ./scripts/Get-JiraTicket.ps1 -TicketKey PROJ-123`
   - or `pwsh ./scripts/Get-JiraTicket.ps1 -Url https://jira.example.com/browse/PROJ-123`
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
