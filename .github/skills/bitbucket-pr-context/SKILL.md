---
name: bitbucket-pr-context
description: 'Collect the full context of a Bitbucket Server pull request for the Marquardt TDST projects (git.marquardt.de): unified diff, changed files, PR title/description, source and target branch, and any linked Jira keys. Use when reviewing a pull request, fetching a PR diff, or starting a code review. Paste a PR URL to pull everything over the REST API, or fall back to local git.'
argument-hint: 'PR URL, or PR id + repo, or source/target branch'
---

# Bitbucket Pull Request Context

Gather everything a reviewer needs about a pull request on `https://git.marquardt.de` (project key `TDST`).
A pull request always comes **from a branch** and is tied to **a Jira ticket** — this skill extracts both.

## When to Use
- Starting a review of a Bitbucket pull request.
- You need the diff, changed file list, PR description, branches, or linked Jira key.
- The orchestrator needs a single, structured context blob to hand to reviewer sub-agents.

## How a PR Review Works Here
There is **no native Bitbucket Server integration** in VS Code, so this skill fetches the context itself. The
best path is to **paste the pull request link** — with a token, the script reads the metadata, the changed
files AND the unified diff straight from the Bitbucket Data Center REST API. No checkout required.

1. **REST (preferred — "give it a link").** From a PR URL the script parses project/repo/id and calls:
   - `/rest/api/1.0/.../pull-requests/{id}` → title, description, branches, author, reviewers
   - `/rest/api/1.0/.../pull-requests/{id}/changes` → changed files
   - `/rest/api/1.0/.../pull-requests/{id}.diff` → the unified diff
   Requires a Personal Access Token (`$env:BITBUCKET_PAT`) or domain SSO (`-UseDefaultCredentials`).
2. **Local git fallback.** If REST is unavailable (no token / offline), the script diffs the source branch
   against the target in a local checkout (`-RepoPath`) using the merge-base — the "diff available by git"
   workflow. Works with no credentials.

```mermaid
flowchart LR
    A[PR URL or id] -->|token| B[Get-PullRequestContext.ps1]
    B -->|Bitbucket REST| C[Metadata + changed files + unified diff]
    A2[branch / no token] --> B
    B -->|fallback| D[local git merge-base diff]
    C & D --> E[Structured context for reviewers]
```

## Procedure
1. Pick the input — any one of:
   - **URL mode (recommended):** the full PR link, e.g.
     `https://git.marquardt.de/projects/TDST/repos/my-repo/pull-requests/42/overview`.
   - **PR id mode:** the pull request id + repo slug.
   - **Branch mode:** the source branch (and target, default `develop`) against a local checkout.
2. For REST modes, make sure a token is set: `$env:BITBUCKET_PAT = '<pat>'` (or use `-UseDefaultCredentials`).
   For branch/fallback mode, ensure the checkout is fetched: `git fetch origin`.
3. Run the context script:
   - URL mode: `pwsh ./scripts/Get-PullRequestContext.ps1 -Url https://git.marquardt.de/projects/TDST/repos/my-repo/pull-requests/42/overview`
   - PR id mode: `pwsh ./scripts/Get-PullRequestContext.ps1 -PullRequestId 42 -Repo my-repo`
   - Branch mode: `pwsh ./scripts/Get-PullRequestContext.ps1 -SourceBranch feature/TDST-123 -TargetBranch develop -RepoPath C:\path\to\checkout`
4. Read the script output. It prints four labelled sections:
   - `===== PR METADATA =====` (JSON: title, description, branches, author, reviewers, `jiraKeys`, `source`)
   - `===== CHANGED FILES =====` (status + path)
   - `===== DIFFSTAT =====`
   - `===== UNIFIED DIFF =====`
5. Pass the **diff**, **changed files**, **description**, and **`jiraKeys`** to the reviewer sub-agents.

## Notes
- `source` in the metadata tells you where the diff came from: `bitbucket-rest` or `local-git`.
- The local diff uses the merge-base (`git diff base...source`), matching what Bitbucket shows in the PR.
- `jiraKeys` are extracted by regex (`[A-Z][A-Z0-9]+-\d+`) from the title, description and branch name.
- Use `-NoRestDiff` to force the local-git diff (e.g. to review uncommitted work) even when a token is set.
- Never hardcode or echo tokens. Provide them via environment variables only.
- Script: [Get-PullRequestContext.ps1](./scripts/Get-PullRequestContext.ps1)
