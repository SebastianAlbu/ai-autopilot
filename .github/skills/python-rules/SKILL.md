---
name: python-rules
description: 'The rule set for reviewing Python changes: correctness traps (mutable default arguments, late-binding closures, bare except, `is` vs `==`), typing and API shape, resource and context-manager discipline, security (subprocess/shell injection, eval, pickle, unsafe YAML, hardcoded secrets, path traversal), packaging and dependency pinning, logging, and pytest conventions. Use whenever a diff touches .py files, pyproject.toml, requirements.txt or conftest.py — including plain requests like "review my python script", "is this pythonic", "check this Flask endpoint", "why is this test flaky", or a PR review where the changed files turn out to be Python. Applies to Python anywhere: standalone services, data/ML scripts, and the Python tooling inside an embedded or SPLE repo.'
---

# Python Review Rules

Review rules for Python changes. The full rule set with IDs, severities and examples is in
**[python-rules.md](./references/python-rules.md)** (rule IDs `PY-*`) — read it before reporting, so every
finding cites a rule and a concrete fix rather than a matter of taste.

Python's failure modes are mostly *quiet*: the code runs, the tests pass, and the defect shows up as
corrupted state three releases later. A mutable default argument, a bare `except`, or a `subprocess` call
with `shell=True` all look unremarkable in a diff. That is why this rule set exists — it names the traps
that reading the diff casually will not surface.

## How to Apply

1. Read the reference and walk the diff hunk by hunk, mapping each changed region to the relevant
   categories:
   - **Correctness (`PY-CORR-*`)** — mutable defaults, late-binding closures in loops, `is` on values,
     mutating a collection while iterating it, integer/float division assumptions, shadowed builtins.
   - **Errors (`PY-ERR-*`)** — bare `except:` / `except Exception` with no re-raise, swallowed tracebacks,
     `raise` losing the cause (`from e`), control flow through exceptions.
   - **Resources (`PY-RES-*`)** — files, sockets, DB connections and locks opened without `with`;
     `subprocess` without timeouts; unclosed sessions.
   - **Typing & API (`PY-API-*`)** — type hints on public functions, `Optional` honesty, returning
     different types by branch, keyword-only arguments for booleans.
   - **Security (`PY-SEC-*`)** — `shell=True` with interpolated input, `eval`/`exec`, `pickle` on untrusted
     data, `yaml.load` without `SafeLoader`, `requests` without `verify`/timeout, secrets in source,
     unvalidated path joins.
   - **Performance (`PY-PERF-*`)** — string concatenation in loops, repeated list scans where a set works,
     N+1 queries, loading whole files when streaming would do.
   - **Tests (`PY-TEST-*`)** — pytest style, no assert-free tests, no sleeping for timing, fixtures over
       setup duplication, changed logic has coverage.
   - **Packaging (`PY-PKG-*`)** — dependencies declared and pinned, no `import *`, no
     `sys.path` manipulation, entry points declared.
2. Prefer what the repo already enforces. If `pyproject.toml` configures ruff, black, mypy or a line
   length, defer to it and do not re-litigate style the linter already owns — a review that duplicates the
   linter wastes the author's attention on things CI will tell them anyway.
3. Cite the rule ID and give a concrete fix for each finding.

## Scope

Report only on lines this change touched (see the `review-coverage-loop` skill). Reading the surrounding
module for context is expected; making untouched code the location of a finding is not.

In an SPLE / spl-core repo the `sple-standards` skill owns build wiring, variants and test *placement*;
this skill owns the Python code itself. Check both, but report each finding once — whichever rule set
describes the actual defect.

## Output Format

```
### Python Rules  <PASS | COMMENTS | CHANGES>
- [F<n>][Blocker|Major|Minor|Nit] file:line — <PY-ID> <issue>. Fix: <suggestion>.
- …
```
Any `PY-SEC-*` finding is a Blocker — those are the ones that turn into incidents. Several Major issues
also warrant CHANGES. A clean diff returns PASS.
