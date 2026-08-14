---
name: project-type-detect
description: 'Classify a repository and route each changed file to the review rule set that governs it. Recognises four families — C# Visual Studio web apps, SPLE / spl-core product lines, standalone Python projects, and bare-metal embedded C — and returns both the structural ruleset for the repo and a per-language routing list, because one pull request can touch Python and C at once and needs both reviewed. Use as an early step in any PR review before picking language reviewers, and whenever the project type is unstated or ambiguous — mixed-language diffs, an unfamiliar repo, a pasted PR link with no context, or when a review seems to be applying rules that do not fit the code. Guessing from a few file extensions is how a C# review ends up on embedded firmware, or how the Python half of a diff goes unreviewed.'
argument-hint: 'repo path, and/or changed-file list, and/or Bitbucket project key'
---

# Project Type Detection

Classifies a repository/PR as one of:
- **`csharp-visualstudio`** → Visual Studio C# web app (ASP.NET Web Forms / .NET Framework). Route to the
  **`csharp-webapp-rules`** skill / **`csharp-webapp-reviewer`** agent.
- **`sple-platform`** → SPLE / spl-core embedded SPL (VS Code-based, CMake + KConfig + variants, C/C++/Python).
  Route to the **`sple-standards`** skill / **`sple-standards-reviewer`** agent.
- **`other`** / **`mixed`** → unknown or both; review with judgment and tell the user what was found.

The user framed this as: *"check it is **not** a VS Code project — if it's from SPLE then the changed code
should respect those standards."* So: **Visual Studio C# repos** get the C# guidelines; **SPLE / VS Code
embedded repos** get the SPLE standards.

## What It Returns

Two answers, deliberately separate — conflating them is what makes a Python file in an embedded repo get
reviewed as firmware, or not reviewed at all:

| Field | Meaning | How to use it |
|-------|---------|---------------|
| `projectType` | Repo family: `csharp-visualstudio`, `sple-platform`, `python`, `embedded-c`, `mixed`, `other` | Context, and picks the structural ruleset |
| `structuralRuleset` | Repo-wide conventions reviewer, or null | Run it whenever present |
| `routing` | One entry per language in the **changed files**: `{ruleset, reviewer, fileCount, files}` | Run **every** entry, giving each only its own files |
| `routingSource` | `changed-files` or `repo-scan` | `repo-scan` means routing covers the whole tree, not the PR |
| `confidence`, `scores`, `matchedMarkers` | Why it decided that | State low confidence in the report |

Pass `-ChangedFilesFile` (or `-ChangedFiles`) whenever reviewing a PR. With only `-RepoPath` the routing
describes the entire repository, which answers "what is this project" but over-answers "what should this PR
be reviewed against".

Structural and language rulesets **compose**. An SPLE change touching `.c` and `.py` routes to
sple-standards (structure, CMake, KConfig, variants) *plus* embedded-c-rules and python-rules (the code
itself). Report each finding once, under whichever ruleset actually describes it.

spl-core markers deliberately outrank the generic Python and embedded-C ones they subsume: an SPLE repo has
`pyproject.toml` and `.c` files too, and calling it "python" would drop the variant and KConfig rules that
only sple-standards knows about.

## How to Apply
1. Run the detector against the checked-out repo and/or the PR's changed files and/or the Bitbucket project key:
   ```powershell
   pwsh ./scripts/Get-ProjectType.ps1 -RepoPath . -ProjectKey PROJ
   # or, from PR context (no checkout):
   pwsh ./scripts/Get-ProjectType.ps1 -ChangedFilesFile ./changed-files.txt -ProjectKey SPLE
   ```
2. Read the `projectType` and `recommendedSkill` from the JSON it prints.
3. Route the review accordingly. If `mixed`/`other`, fall back to inspecting the changed files' extensions
   (`.cs`/`.aspx` → C#; `.c`/`.cpp`/`.h`/`CMakeLists.txt`/`KConfig` → SPLE) and state the assumption.

## Detection Markers
**SPLE / spl-core (sple-platform):**
- Bitbucket project key `SPLE` (strong signal).
- Root `CMakeLists.txt` referencing spl-core (`spl_add_component`, `add_variants`, `spl_create_component`).
- `KConfig`, `variants/` tree, `components/<name>/{src,test}`.
- `build.ps1`/`build.bat`/`build.sh`, `pypeline.yaml`, `bootstrap.json`, `scoopfile.json`, `poks.json`.
- `.vscode/`, `.devcontainer/`, `AGENTS.md`, `pyproject.toml` + `poetry.lock`, `pytest.ini`, `conf.py`.
- Source languages C/C++/Python/CMake/PowerShell; **no** `.sln`/`.csproj`.

**C# Visual Studio (csharp-visualstudio):**
- `*.sln`, `*.csproj` (or `*.vbproj`), `Web.config`/`App.config`, `*.aspx`/`*.ascx`/`*.asmx`, `Global.asax`.
- `packages.config` / NuGet, `Properties/AssemblyInfo.cs`, lots of `*.cs`.
- The Bitbucket project key is a supporting signal only (`SPLE` → embedded platform); file markers win.

## Output
The script prints a JSON object:
```json
{
  "projectType": "sple-platform | csharp-visualstudio | mixed | other",
  "confidence": "high | medium | low",
  "scores": { "sple": 7, "csharp": 0 },
  "matchedMarkers": { "sple": ["CMakeLists.txt", "KConfig", "variants/"], "csharp": [] },
  "recommendedSkill": "sple-standards | csharp-webapp-rules | none",
  "recommendedReviewer": "sple-standards-reviewer | csharp-webapp-reviewer | none",
  "notes": "human-readable explanation"
}
```
Use `recommendedReviewer` to decide which agent to dispatch.

Reference detector: [scripts/Get-ProjectType.ps1](./scripts/Get-ProjectType.ps1)
