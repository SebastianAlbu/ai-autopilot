---
name: sple-standards
description: 'The rule set for reviewing SPLE (Software Product Line Engineering) platform projects built on avengineers/spl-core — CMake + KConfig + variants, components in C/C++ with GoogleTest, Python with ruff/pytest, PowerShell build scripts. Covers component and variant structure, KConfig feature modelling, CMake patterns, embedded C/C++ safety, unit tests and quality gates, and cppcheck static analysis. Use whenever a diff touches CMakeLists.txt, KConfig, variants/, components/, build.ps1 or pypeline.yaml, or on requests like "review this embedded change", "check my component", "does this break the other variants". For Visual Studio C# web apps, use csharp-webapp-rules instead.'
argument-hint: 'changed files in an SPLE/spl-core project'
---

# SPLE Platform Review Rules

Standards for **SPLE platform** projects (based on the
open-source [avengineers/spl-core](https://github.com/avengineers/spl-core) and the
[SPLed](https://github.com/avengineers/SPLed) demonstrator). These are **embedded software product lines** —
C/C++ firmware organized into reusable components and configured into product **variants** via **KConkig**,
built with **CMake** through `spl-core`, tested with **GoogleTest** (C/C++) and **pytest** (Python), and
developed in **VS Code**. This is a different world from the Visual Studio C# web apps — use this skill, not
`csharp-webapp-rules`, when the project is an SPLE project.

## How to Apply
1. Read the full rule set: [sple-standards.md](./references/sple-standards.md).
2. Confirm the project is SPLE (don't apply these rules to a Visual Studio C# repo).
3. Walk the diff. Map each change to the right category: component code, variant config, build, tests, tooling.
4. Report findings with severity + concrete fix, citing `file:line` and the rule ID (`SPL-*`).

## SPLE Project Markers (how you know it's SPLE)
A repo is an SPLE/spl-core project if several of these are present:
- Root `CMakeLists.txt` that uses spl-core (`spl_add_component`, `spl_create_component`, `add_variants`, …).
- A `KConfig` file and a `variants/<group>/<name>/` tree with `config.txt` and/or `parts.json`.
- `build.ps1` / `build.bat` / `build.sh` wrappers, `pypeline.yaml`, `bootstrap.json`, `scoopfile.json`, `poks.json`.
- `components/` (each with `src/`, `test/`), `tools/toolchains/`, `.vscode/`, `.devcontainer/`, `AGENTS.md`.
- Python tooling: `pyproject.toml`, `poetry.lock`, `pytest.ini`, `conf.py` (Sphinx), `ruff`, `.pre-commit-config.yaml`.
- Languages are **C, C++, Python, CMake, PowerShell** (no `.sln`/`.csproj`/`.aspx`).

## Rule Categories (summary)
- **Structure (SPL-STRUCT):** component layout (`src`/`test`), one concern per component, no cross-variant leakage.
- **Variants & KConfig (SPL-KCONFIG):** features in KConfig, variant config in `variants/.../config.txt`, no
  hardcoded variant logic, no `#ifdef` sprawl where a KConfig feature belongs.
- **CMake (SPL-CMAKE):** use spl-core functions, declare sources/deps explicitly, no absolute paths, no globbing
  of sources, link via component names.
- **C/C++ embedded (SPL-CPP):** MISRA-leaning safety, fixed-width types (`uint8_t`), no dynamic allocation in
  firmware paths, `const`-correctness, no magic numbers, guard headers, no undefined behavior.
- **Tests & quality gates (SPL-TEST):** GoogleTest for C/C++ and pytest for Python; tests live in the
  component's `test/`; use the marker strategy (type + gate, e.g. `gate_develop_pr`); changes need test coverage.
- **Static analysis (SPL-SCA):** respect the `sple-sca-ruleset` (cppcheck/clang); no new warnings; don't suppress
  without justification.
- **Python/PowerShell tooling (SPL-PY):** ruff-clean, type hints, pytest; PowerShell follows the build-script patterns.

## Output
For each issue: `[Severity] file:line — <SPL-ID>: <issue>. Fix: <suggestion>.`
Severities: **Blocker** (build/test break, unsafe firmware, broken variant), **Major**, **Minor**, **Nit**.
End with a verdict for this category: PASS / PASS-WITH-COMMENTS / CHANGES-REQUESTED.

Reference: [sple-standards.md](./references/sple-standards.md)
