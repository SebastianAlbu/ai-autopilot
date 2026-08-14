# AGENTS.md — working in this repository

Guidance for AI agents (and humans) contributing to **AI Autopilot**. Read this before adding or changing a
skill, an agent, or a script.

## What this repo is

A pull-request review system: an orchestrator agent that delegates to specialist reviewer sub-agents, plus
the PowerShell skills they run on. It is installed **globally** onto a developer machine — it is not a
library you import, and it does not run in CI.

```
.github/skills/<name>/     SKILL.md (+ scripts/, references/)   <- the capabilities
.github/agents/*.agent.md  the agents                            <- who uses them
Install-AiAutopilot.ps1    copy-installs both, globally
Build-Plugin.ps1           regenerates plugins/ from .github/
plugins/                   GENERATED — never hand-edit
tests/                     Pester tests (mock at the HTTP boundary)
```

`.github/skills` and `.github/agents` are the **source of truth**. The installer auto-discovers them: a new
skill folder or `*.agent.md` needs no registration anywhere. After changing either, run
`pwsh ./Build-Plugin.ps1` so the plugin tree matches.

## Hard rules

**No hardcoded hostnames.** Every server address comes from an environment variable with a documented
`example.com` fallback — `BITBUCKET_BASE_URL`, `JIRA_BASE_URL`, `JENKINS_BASE_URL`, `POLYSPACE_ACCESS_URL`.
This repo is shared across teams and instances; a baked-in hostname breaks everyone but its author.

**No secrets, ever.** Tokens come from `BITBUCKET_PAT`, `JIRA_PAT`, `JENKINS_TOKEN`, or `-UseDefaultCredentials`.
Never write one into a file, a default parameter value, an example, or an error message. Do not echo a token
in output even when debugging.

**Write actions are opt-in and previewable.** Any script that changes remote state (posting a comment,
resolving a thread) declares `[CmdletBinding(SupportsShouldProcess = $true)]`, honours `ShouldProcess`, and
offers `-DryRun` that prints the payload and exits.

**Reviewers do not edit code.** Reviewer agents get `tools: [read, search, execute]`. The only agent allowed
to change a working tree is `pr-feedback-responder`.

## Skills

```
.github/skills/<kebab-case-name>/
  SKILL.md          required — frontmatter + the procedure
  scripts/*.ps1     optional — the mechanics
  references/*.md   optional — API detail, rule sets, anything long
```

`SKILL.md` frontmatter:

```yaml
---
name: kebab-case-name          # must equal the folder name
description: 'What it does, then the phrases that should trigger it — "review a PR", "why did the build fail".'
argument-hint: 'what the user typically supplies'   # optional
---
```

The `description` is the only thing a model sees when deciding whether to load the skill. Write it with the
user's actual words in it, not a summary of the implementation.

Keep `SKILL.md` about **procedure and judgement** — what to do, in what order, and what not to do. Push REST
payloads, field tables and rule catalogues into `references/`; they cost context on every load otherwise.

## PowerShell scripts

- PowerShell **7+**, cross-platform. It is the repo's only prerequisite — do not introduce Python, `uv`,
  Node or any other runtime.
- `Verb-Noun.ps1`, approved verbs (`Get-`, `Set-`, `Add-`, `Invoke-`, `New-`, `Test-`).
- Comment-based help at the top: `.SYNOPSIS`, `.DESCRIPTION`, one `.PARAMETER` per parameter, and at least
  two `.EXAMPLE` blocks.
- `$ErrorActionPreference = 'Stop'` immediately after `param()`.
- Parameter surface consistent with the sibling scripts — `-Url` **or** ids, `-BaseUrl`, `-Token`,
  `-UseDefaultCredentials`, `-Json`.
- Translate HTTP failures into an actionable message. `401` says which variable to set; `404` on a resolve
  says the id is probably a reply, not a thread root. A raw `Invoke-RestMethod` exception is not a diagnosis.
- Shared logic goes in a dot-sourced `*Common.ps1` in the same `scripts/` folder.
- Comment the **non-obvious** — why the activities feed duplicates replies, why `/view/` must be stripped
  from a Jenkins URL. Do not narrate what the next line plainly does.

## Agents

`.github/agents/<slug>.agent.md`, frontmatter `description` / `name` / `tools`, optionally `agents` and
`argument-hint`. The body is the system prompt: what it owns, an explicit **Constraints** list of what it
must not do, and the exact output format. Existing agents are the template — match their shape.

## Tests

`tests/*.Tests.ps1`, run with Pester 5. Mock at the **HTTP boundary** (`Mock Invoke-RestMethod`) so tests
need no server, no token and no network. Test the logic that is easy to get wrong: URL and argument parsing,
pagination, thread de-duplication, filtering, retry-on-conflict, and error messages.

```powershell
Invoke-Pester ./tests -Output Detailed
Invoke-ScriptAnalyzer -Path .github/skills -Recurse
```

## Commits

Conventional Commits, with the ticket key where the work has one:

```
feat: add bitbucket-pr-threads skill (TDST-1234)
fix: strip /view/ segments from pasted Jenkins URLs
docs: document JENKINS_* configuration
```

Keep a change to one concern. Do not commit `plugins/` edits separately from the `.github/` change that
produced them — regenerate and commit both together.
