# SPLE Platform Standards (spl-core)

Detailed rules for reviewing **SPLE / spl-core** projects (Marquardt `projects/SPLE`, upstream
[avengineers/spl-core](https://github.com/avengineers/spl-core) + [SPLed](https://github.com/avengineers/SPLed)).
Cite the rule ID (e.g. `SPL-CMAKE-02`). Severities: **Blocker**, **Major**, **Minor**, **Nit**.

> **Authoritative sources to defer to** when in doubt: the project's own `AGENTS.md`, the
> `sple-sca-ruleset` repo (static-analysis rules & code metrics), and `spl-core.readthedocs.io`. If the repo's
> `AGENTS.md` or SCA ruleset disagrees with a rule here, the repo wins — note the discrepancy.

## 0. First, Confirm It's an SPLE Project
Do **not** apply these rules to a Visual Studio C# app. Confirm SPLE markers: root `CMakeLists.txt` using
spl-core, `KConfig`, `variants/`, `components/`, `build.ps1`, `pypeline.yaml`, `.vscode/`. If unsure, run the
`project-type-detect` skill. Languages: C/C++/Python/CMake/PowerShell.

## 1. Project & Component Structure (SPL-STRUCT)
- SPL-STRUCT-01 — Code belongs to a **component** under `components/<name>/` (or `src/<name>/`) with a clear
  `src/` and `test/`. New code outside a component is a smell. (Major)
- SPL-STRUCT-02 — A component has a **single responsibility**; don't pile unrelated features into one component. (Major)
- SPL-STRUCT-03 — **No variant-specific code** baked into a shared component — variability goes through KConfig
  features, not hardcoded branches. (Major)
- SPL-STRUCT-04 — Public component interface lives in its header(s); keep internal details in `src`. (Minor)
- SPL-STRUCT-05 — Don't reach across components by relative path; depend via the component's declared interface. (Major)

## 2. Variants & KConfig (SPL-KCONFIG)
- SPL-KCONFIG-01 — New configurable behavior is a **KConfig feature**, not a magic constant or copy-pasted file. (Major)
- SPL-KCONFIG-02 — Variant selection/config lives in `variants/<group>/<name>/config.txt` (and `parts.json`),
  not in component source. (Major)
- SPL-KCONFIG-03 — Avoid `#ifdef` sprawl: prefer a KConfig feature + clean conditional compilation at one place
  over scattered preprocessor branches. (Minor→Major if widespread)
- SPL-KCONFIG-04 — Every new KConfig symbol has a help text and a sensible default; don't break existing variants. (Minor)
- SPL-KCONFIG-05 — If a change adds a feature, the relevant **variant(s)** must be updated/validated. (Major)

## 3. CMake / Build (SPL-CMAKE)
- SPL-CMAKE-01 — Use **spl-core CMake functions** (e.g. `spl_add_component`, `spl_create_component`,
  `add_variants`); don't hand-roll target plumbing spl-core provides. (Major)
- SPL-CMAKE-02 — Declare sources **explicitly**; do **not** `file(GLOB ...)` source files. (Major)
- SPL-CMAKE-03 — **No absolute paths** or machine-specific paths in CMake; use project-relative and toolchain vars. (Major)
- SPL-CMAKE-04 — Link/depend via **component names**, not raw file paths. (Minor)
- SPL-CMAKE-05 — Keep toolchain specifics in `tools/toolchains/`, not inline in component CMake. (Minor)
- SPL-CMAKE-06 — Don't bypass the `build.ps1`/pypeline flow with ad-hoc build steps. (Minor)

## 4. C / C++ Embedded Code (SPL-CPP)
- SPL-CPP-01 — Use **fixed-width types** (`uint8_t`, `int32_t`) from `<stdint.h>`, not bare `int`/`char` for
  hardware-facing data. (Major)
- SPL-CPP-02 — **No dynamic allocation** (`malloc`/`new`) on embedded/firmware paths unless explicitly allowed. (Major)
- SPL-CPP-03 — **`const`-correctness**: mark read-only params/pointers `const`; avoid non-const globals. (Minor)
- SPL-CPP-04 — **No magic numbers**: use named constants/enums/`#define` with units; (cross-ref appconstants idea). (Minor)
- SPL-CPP-05 — **Header guards** (`#ifndef`/`#define`/`#endif` or `#pragma once`); no definitions in headers. (Major)
- SPL-CPP-06 — Initialize all variables; check return codes; no implicit fallthrough; brace all control statements. (Major)
- SPL-CPP-07 — **MISRA-leaning**: no undefined/implementation-defined behavior, no pointer arithmetic surprises,
  explicit casts, no recursion in firmware. Flag obvious violations; defer specifics to the SCA ruleset. (Major)
- SPL-CPP-08 — Keep functions short and single-purpose; document non-obvious logic with comments. (Minor)
- SPL-CPP-09 — Avoid global mutable state; prefer passing context; ensure ISR/concurrency safety where relevant. (Major)

## 5. Tests & Quality Gates (SPL-TEST)
- SPL-TEST-01 — C/C++ changes need **GoogleTest** unit tests in the component's `test/`; Python changes need
  **pytest** tests. New/changed logic without tests is a finding. (Major)
- SPL-TEST-02 — Follow the **two-dimensional marker strategy**: a *type* marker (what to test) + a *gate* marker
  (when, e.g. `gate_develop_pr`, `gate_develop_push`). Tests must be assigned to the correct gate. (Minor→Major)
- SPL-TEST-03 — Don't weaken/disable tests or gates to make CI pass; fix the cause. (Blocker if it hides a defect)
- SPL-TEST-04 — Tests are deterministic and isolated (no hidden hardware/network/order dependencies). (Major)
- SPL-TEST-05 — Mock hardware/dependencies (GoogleMock) rather than touching real peripherals in unit tests. (Minor)

## 6. Static Code Analysis (SPL-SCA)
- SPL-SCA-01 — Code must pass the project's **`sple-sca-ruleset`** (cppcheck/clang) with **no new warnings**. (Major)
- SPL-SCA-02 — Don't add blanket suppressions; any suppression needs an inline justification and is narrowly scoped. (Major)
- SPL-SCA-03 — Respect configured **code metrics** (complexity, function/file size) from the SCA ruleset. (Minor→Major)
- SPL-SCA-04 — Keep `.editorconfig`, `ruff`, and `pre-commit` clean — formatting/lint must pass. (Minor)

## 7. Python & PowerShell Tooling (SPL-PY)
- SPL-PY-01 — Python is **ruff-clean**, **type-hinted**, and tested with pytest; follow `pyproject.toml` config. (Minor→Major)
- SPL-PY-02 — No hardcoded paths/secrets in tooling; use config/env and project-relative paths. (Major)
- SPL-PY-03 — PowerShell follows the existing `build.ps1`/bootstrap patterns; `[CmdletBinding()]`, param blocks,
  `$ErrorActionPreference='Stop'`, approved verbs. (Minor)
- SPL-PY-04 — Update Sphinx docs (`docs/`, `conf.py`) when behavior/usage changes. (Minor)

## Verdict Guidance
- A broken build/variant, failing or removed tests, unsafe firmware, or new SCA errors → **CHANGES-REQUESTED**
  (Blocker).
- Several Major structural/KConfig/CMake/C++ issues → **CHANGES-REQUESTED**.
- Mostly Minor/Nit → **PASS-WITH-COMMENTS**.
- Always prefer the repo's own `AGENTS.md` / `sple-sca-ruleset` when it is more specific than this file.
