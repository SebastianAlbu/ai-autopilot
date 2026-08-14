---
name: review-coverage-loop
description: 'Iterative review protocol that keeps re-scanning a diff with fresh lenses until an estimated 90% of the findings have been discovered. Run repeated independent passes, measure coverage from the new-finding rate (or capture-recapture overlap between passes), and only stop when coverage >= 90% or the pass cap is hit. Use inside any reviewer agent that must not miss findings, or when asked to "review thoroughly", "find everything", "don''t miss anything", or "review until complete".'
---

# Review Coverage Loop (target: 90%)

A single review pass is not a complete review. One sweep typically surfaces the obvious findings and
misses the rest. This skill turns reviewing into a **measured loop**: scan → estimate coverage →
scan again with a different lens → stop only when the estimate reaches **90%**.

## The loop

```
pass 1 ── find ──> F1
   |
   v
pass n ── find with a NEW lens ──> new_n (findings not already in the set)
   |
   v
estimate coverage C
   |
   +-- C >= 0.90 and n >= 2 ---> STOP, report findings + coverage
   +-- n >= 5 -----------------> STOP, report findings + "not converged"
   +-- otherwise --------------> next pass
```

**Minimum 2 passes, maximum 5.** A first pass alone can never be declared 90% — there is nothing to
measure against.

## Scope: the diff, and only the diff

**Every reported finding must anchor to a line the change actually touched.** Coverage means 90% of the
findings *in this change* — not 90% of everything wrong with the repository.

- A finding's `file:line` must be an **added or modified line in the diff** (a `+` line), or a line whose
  behaviour the diff altered (e.g. a deleted guard, a changed signature).
- You may **read** as much untouched code as you need — callers, callees, the rest of the file, the base
  version of the line. That is context for judging a changed line, not a place to find new findings.
- When a changed line breaks something in untouched code, that is still in scope: anchor the finding to the
  **changed line** and name the other location as `impact:`. Example:
  `[F3][Major] src/Api.cs:88 — signature now takes a nullable id; impact: src/Jobs/Sync.cs:210 passes non-null and will not compile.`
- Anything you notice in untouched code that the change did not cause goes under **Deferred (not blocking
  this PR)** — one line, no severity, excluded from the verdict and from the coverage maths.

The author is accountable for what they changed. A review that grades the whole file is unactionable, and
it is the fastest way to make a small PR unmergeable.

## Estimating coverage

Let `T` = total distinct findings so far, `new_n` = findings that pass *n* added that no earlier pass had.

### Primary estimator — marginal discovery rate
```
C = 1 - (new_n / T)
```
If a fresh, independent sweep still turns up 3 unseen findings out of 20 total, roughly 15% of the
population is still hiding → C = 0.85 → keep going. When a pass adds nothing, C = 1.0.

### Cross-check — capture-recapture (use when two passes overlap on >= 2 findings)
For two independent passes A and B:
```
N_est = (|A| * |B|) / |A ∩ B|          # estimated true population
C     = |A ∪ B| / N_est
```
Example: pass A finds 8, pass B finds 7, 4 are the same → `N_est = 56/4 = 14`, found 11 distinct →
C = 11/14 = 0.79 → keep going.

When both estimators are available, **take the lower one**. Round to whole percent.

### Edge cases
- `T = 0` after two genuinely different passes → coverage 100%, verdict PASS, no findings.
- Only 1–2 findings total: the estimators are unstable. Require **three** passes with zero new findings
  in the last two before declaring 90%+.
- Never count a rephrasing of an existing finding as `new`. Deduplicate by `file:line + root cause`
  *before* computing anything.
- **Deferred items are not findings.** They never enter `T`, never count as `new`, and never move the
  coverage number. Otherwise off-diff noise would inflate the estimate and hide real gaps in the diff.

## Passes must be independent

Re-running the same search with the same prompt is not a second pass — it re-finds the same items and
falsely inflates coverage. Each pass must use a **different lens**. Rotate through these (pick the ones
relevant to your review domain):

| # | Lens | How to sweep |
|---|------|--------------|
| 1 | **Diff-order** | Walk the hunks top to bottom, judge each changed line in place. |
| 2 | **Symbol/callers** | For each changed function/class, search its call sites and check the contract from the *caller's* side. |
| 3 | **Failure-mode** | Ignore the diff shape; ask per change: null/empty, boundary, error path, concurrency, resource lifetime, permission. |
| 4 | **Rule sweep** | Walk your rule reference top to bottom and ask "does the diff violate this rule?" — the reverse direction of pass 1. |
| 5 | **Whole-file / adversarial** | Open each changed file in full for context, then ask "if this PR causes an incident next month, **which changed line** did it?" Report only on changed lines. |

Between passes, briefly note *why* the previous pass could have missed something — that note picks the
next lens.

## What to report

Always publish the coverage number; a review that stopped early must say so.

```
<findings on changed lines, one line each>
Deferred (not blocking this PR):
- src/Legacy.cs:200 — pre-existing; not touched by this change.
Coverage: 92% (3 passes, last pass added 1 of 24)
```
or, when the cap was hit:
```
Coverage: 78% (5 passes, not converged — last pass still added 4 of 18; likely more findings remain)
```

Never claim a coverage figure you did not compute from actual pass counts. If you ran one pass, the
honest report is `Coverage: unmeasured (1 pass)`.

## Cost control

More passes cost tokens. Keep them cheap:
- Later passes read **only** what the chosen lens needs — don't re-read the whole diff every pass.
- Carry forward a compact `file:line — root cause` list, not the full text of earlier findings.
- Stop at the first pass that reaches 90%. Do not run extra passes "to be safe".
