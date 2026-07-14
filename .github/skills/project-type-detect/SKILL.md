---
name: project-type-detect
description: 'Detect whether a Marquardt repository / pull request is a C# Visual Studio web application (.sln/.csproj/.aspx — e.g. TDST, mq_feedback) or an SPLE / spl-core embedded platform project (VS Code-based: CMake + KConfig + variants/, C/C++/Python — git.marquardt.de/projects/SPLE), so the orchestrator can route the review to the correct ruleset. Use early in a PR review to pick between the csharp-webapp-rules skill and the sple-standards skill.'
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

## When to Use
- As an **early step** in a PR review, before running the language-specific reviewer, to choose the ruleset.

## How to Apply
1. Run the detector against the checked-out repo and/or the PR's changed files and/or the Bitbucket project key:
   ```powershell
   pwsh ./scripts/Get-ProjectType.ps1 -RepoPath . -ProjectKey TDST
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
- Bitbucket project key `TDST` (Marquardt web tooling) is a supporting signal.

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
