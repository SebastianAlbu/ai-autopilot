---
name: jenkins-build-analysis
description: 'Investigate a Jenkins build from the terminal — result and cause, pipeline stages with the failed one flagged, failed test cases, and the console or per-stage log filtered by regex. Use whenever CI comes up: "why did the build fail", "check the Jenkins job", "what broke in the pipeline", "show the build log", "which tests failed", or to confirm CI status while reviewing a pull request instead of guessing. Read-only — it never triggers, stops or reconfigures a build.'
argument-hint: 'job path or Jenkins URL, optionally a build number / selector and a stage name'
---

# Jenkins Build Analysis

Read-only CI triage. Two scripts, both configured entirely through environment variables — no hostname or
credential is baked in.

## Configuration
| Variable | Meaning |
|---|---|
| `JENKINS_BASE_URL` | Jenkins root, e.g. `https://jenkins.example.com` |
| `JENKINS_ROOT_JOB` | optional folder every relative target hangs under, e.g. `SPLE` or `team/ci` |
| `JENKINS_USER` + `JENKINS_TOKEN` | Basic auth — the **API token replaces the password** (your login password is never used). Create it under *your name → Configure → API Token*. |
| `JENKINS_AUTH` | alternative single value, `user:token` |
| `JENKINS_VERIFY_SSL` | `false` to skip TLS verification (corporate CA not in the trust store) |

A **target** is either a job path relative to `JENKINS_ROOT_JOB` (`MyComponent/main`) or a full URL pasted
from the browser — `/view/<name>` segments in pasted multibranch links are stripped automatically.
A **selector** is a build number or `lastBuild` / `lastFailedBuild` / `lastSuccessfulBuild` / … (default
`lastBuild`). A target that already ends in a build number or selector is used as is.

## Procedure — summary first, then detail

```powershell
# 1. Confirm the failure and its cause
pwsh ./scripts/Get-JenkinsBuild.ps1 -Target MyComponent/main -Selector lastFailedBuild

# 2. Locate WHERE it broke
pwsh ./scripts/Get-JenkinsBuild.ps1 -Target MyComponent/main -Selector lastFailedBuild -Stages

# 3. Read only that stage's log (the failed stage is the default)
pwsh ./scripts/Get-JenkinsLog.ps1 -Target MyComponent/main -Selector lastFailedBuild
pwsh ./scripts/Get-JenkinsLog.ps1 -Target MyComponent/main -Selector lastFailedBuild -Grep 'error|failed|undefined reference'

# 4. If tests are the failure, list them
pwsh ./scripts/Get-JenkinsBuild.ps1 -Target MyComponent/main -Selector lastFailedBuild -Tests
```

Discovery when you don't know the path: `-ListJobs` (root folder, or a folder with `-Target`) and
`-ListBuilds [-Limit 20]`. `-Json` on `Get-JenkinsBuild.ps1` emits the raw API payload.

**Never start with `-Full`.** A console log is routinely megabytes; dumping it buries the actual error and
burns the context window. `Get-JenkinsLog.ps1` shows the last 200 lines by default — narrow with `-Grep`,
widen with `-Tail`, and reach for `-Full` only when the failure genuinely isn't in either.

## Explain, don't quote
The value you add is the diagnosis. Report:
1. **What failed** — the stage, the step, the test.
2. **Why** — the actual error, quoted as the few relevant lines, not the surrounding log.
3. **What to do** — the concrete fix, or the specific thing that still needs investigating.

A reply that is a wall of log with "looks like it failed" on top is worse than no reply.

## Using it in a PR review
When a PR has a red or linked CI build, read it rather than asserting build status from the diff:
- A failure in the changed component is a **finding** — name the stage and the error.
- A failure unrelated to the change (infra, flaky, a different component) is worth **mentioning as context**,
  not raising as a finding against the author.
- Failed tests found via `-Tests` map directly to code paths in the diff — that is the strongest evidence a
  functional review can cite.

## Notes
- Stage data comes from the Pipeline Stage View API (`/wfapi/describe`) and exists only for Pipeline jobs.
  A freestyle job reports "no stage data" and falls back to the console log — that is expected, not an error.
- No test report usually means the build failed *before* the tests ran.
- The stage log is assembled from the stage's child flow nodes; that endpoint returns HTML-annotated text,
  which the script strips.
- Endpoints and response shapes: [references/jenkins-api.md](./references/jenkins-api.md)
- Scripts: [Get-JenkinsBuild.ps1](./scripts/Get-JenkinsBuild.ps1), [Get-JenkinsLog.ps1](./scripts/Get-JenkinsLog.ps1),
  [JenkinsCommon.ps1](./scripts/JenkinsCommon.ps1) (shared helpers, dot-sourced)
