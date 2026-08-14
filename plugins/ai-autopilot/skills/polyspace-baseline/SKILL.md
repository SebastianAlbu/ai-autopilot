---
name: polyspace-baseline
description: 'Download a Polyspace baseline from Polyspace Access so local static-analysis findings can be compared against a reference analysis. Use for "download polyspace baseline", "get the baseline from PR-XXX", "compare against baseline", "switch baseline project", or when triaging whether a Polyspace finding is new or pre-existing. Detects the active CMake variant and analysis step, builds the project path, temporarily updates the VS Code settings and triggers the download — reverting the settings only on success.'
argument-hint: 'branch or PR reference (e.g. PR-315, develop), optionally "step <name>"'
---

# Polyspace Baseline Download

A baseline turns "Polyspace reports 40 findings" into "this change *added* 2". Without one, a static-analysis
review cannot separate the author's findings from the ones that were already there.

## Prerequisites
- Polyspace as You Code extension (`mathworks.polyspace`) installed in VS Code.
- Network access to the Polyspace Access server.
- A configured CMake variant, and `variants/<variant>/static_analysis.json` for it.

## Configuration
No server URL is hardcoded. The Access server comes from, in order:

1. `polyspace.baseline.polyspaceAccessUrl` already in `.vscode/settings.json` — use it as is;
2. `$env:POLYSPACE_ACCESS_URL`;
3. otherwise ask the user, and write it into the workspace settings once.

The **project-path pattern** is likewise per-project. The usual shape is:

```
<root>/<program>/<component>/<branch-or-PR>/<VARIANT>_<STEP>
```

Read the existing `polyspace.baseline.project` value to learn the project's actual prefix rather than
assuming one — the leading segments (visibility root, program, component) are stable per repository, and only
the last two vary.

## Path construction
- **`<branch-or-PR>`** — `develop`, `main`, `release/X.Y.Z`, or a PR reference such as `PR-315`.
- **`<VARIANT>`** — the active variant with `/` replaced by `_` (a `MMA/EIS` variant becomes `MMA_EIS`).
- **`<STEP>`** — a `steps[].name` from `variants/<variant>/static_analysis.json`, e.g.
  `hand_written_components`, `matlab_models_MQ`.

Example: PR-315, variant `DEMOCAR`, step `hand_written_components`
→ `<prefix>/PR-315/DEMOCAR_hand_written_components`.

## Accepted user input
A full project path (used verbatim), a PR reference (`PR-315`), a branch name, or either plus
`step <name>`. If no path is given, ask. If the variant defines several steps and none was named, ask which —
do not guess, the wrong step silently baselines against unrelated code.

## Procedure
1. **Detect the variant** — read `cmake.buildDirectory` in `.vscode/settings.json` and take the `${variant}`
   value; replace `/` with `_`.
2. **Read the steps** from `variants/<variant>/static_analysis.json` → `steps[].name`.
3. **Resolve the path** from the user input plus the existing project prefix (ask if ambiguous).
4. **Store the current settings** — `polyspace.baseline.project` and
   `polyspace.baseline.showBaselineInformation`. You will need them to revert.
5. **Ensure baseline visibility.** The download is a no-op while
   `polyspace.baseline.showBaselineInformation` is `"Show local findings only"`; set it to
   `"Show local findings and baseline info"` first.
6. **Set `polyspace.baseline.project`** to the resolved path.
7. **Trigger** the VS Code command `polyspace.downloadBaseline`.
8. **Warn about the credential prompt** before triggering (see below).
9. **Revert conditionally:**
   - **Success** → restore the stored settings and confirm to the user.
   - **Failure** (auth timeout, network error, cancellation) → **leave the settings in place** so a retry is
     one command instead of a full reconfiguration. Say explicitly that they were kept.

## Credential prompt race
When the password prompt appears, a corporate "same password used in multiple places" policy warning can
steal focus and clear the field. Copy the password to the clipboard *before* triggering the download so it
can be pasted immediately. If the warning does interrupt, just retry — the settings are still configured.

## Settings reference
```jsonc
{
  "polyspace.baseline.polyspaceAccessUrl": "<from settings, $POLYSPACE_ACCESS_URL, or ask>",
  "polyspace.baseline.project": "<prefix>/<branch-or-PR>/<VARIANT>_<STEP>",
  "polyspace.baseline.polyspaceAccessLogin": "<username>",
  "polyspace.baseline.showBaselineInformation": "Show local findings and baseline info"
}
```
Never write a password or token into settings — the extension prompts for it.

## Using it in a review
When reviewing an SPLE change with static-analysis impact, baseline against the **target branch**
(`develop`/`main`), not against the PR's own branch — otherwise the PR's findings baseline away themselves.
Then report only the delta: findings the change introduces are findings; pre-existing ones are context.

This skill owns the **baseline** (which run the findings are compared against). Which *rules* the project
checks at all lives in its checkers-selection XML — see `embedded-c-rules`
(`scripts/Get-PolyspaceCheckers.ps1` and `references/polyspace-misra.md`), which also covers the rules the
selection keeps in scope but Polyspace cannot check.

## Troubleshooting
| Symptom | What to do |
|---|---|
| Credential warning steals focus | Retry immediately — the settings are still configured |
| Authentication timeout | Settings preserved; re-run the download command |
| Download appears to do nothing | `showBaselineInformation` is set to "Show local findings only" |
| Extension command not found | Install `mathworks.polyspace` |
| Wrong findings shown | Wrong step or wrong variant in the path — re-check `static_analysis.json` |
