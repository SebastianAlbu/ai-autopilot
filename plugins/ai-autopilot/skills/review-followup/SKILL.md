---
name: review-followup
description: 'Re-review mode for a pull request that has already been reviewed and has since received new commits. Keeps the original findings as the agenda — verify each one as Fixed / Partial / Not fixed / Regressed — instead of opening a fresh set of unrelated topics every round. Use whenever a PR already has a review comment, when the author says "I fixed it", "please re-review", "check my changes", or when new commits landed after a previous review.'
---

# Follow-up Review (round 2+)

A second review that raises a brand-new set of topics is worse than useless: the author fixes what you
asked for, gets a different list back, and the PR never converges. **A follow-up review is an audit of the
previous review's findings, not a new review.**

## Detect the mode first

You are in **follow-up mode** if any of these hold:
- The PR already has a review comment from this system (check the PR comments in the context).
- A previous report file exists for this branch (e.g. `review-<branch>.md`).
- The user says "re-review", "I fixed it", "check my changes", "round 2", or points at new commits.
- The PR head commit differs from the one recorded in the previous review.

Otherwise you are in **first-review mode** — run the normal full review with the `review-coverage-loop`.

State which mode you are in, in one line, at the top of the report.

## Stable finding IDs

Round 1 assigns every finding an ID: `F1`, `F2`, `F3`… **IDs never change and are never reused.** Every
later round refers to the same finding by the same ID. Without stable IDs there is no way to prove a
follow-up addressed the original list.

- Round 1 emits `[F7][Major] src/Foo.cs:42 — …`.
- Round 2 emits `[F7] FIXED` or `[F7] NOT FIXED — the null check guards the wrong branch`.
- A genuinely new finding in round 2 continues the numbering: `F8`, `F9`.

Record the ID list in the report so the next round can read it back from the posted PR comment.

## What a follow-up review does

1. **Load the previous findings** — from the posted PR comment or the saved report. This list is your
   **agenda**. If you cannot recover it, say so explicitly and fall back to a first-review; do not
   silently improvise a new agenda.
   The mechanism is the **`bitbucket-pr-threads`** skill: `Get-PullRequestComments.ps1 -Url <link>` returns
   every thread with its **comment id**, state and replies — both this system's round-1 comment and anything
   a human reviewer added since. Human threads count as part of the agenda: a reviewer's open comment is a
   finding, even though it has no `F<n>` id.
2. **Get the incremental diff** — what changed *since the reviewed commit*, not the whole PR diff again.
3. **Verify each original finding** against the new code. Exactly one verdict each:

   | Verdict | Meaning |
   |---------|---------|
   | `FIXED` | The problem is gone and the fix is correct. |
   | `PARTIAL` | Addressed in one place but not all, or the fix is incomplete. |
   | `NOT FIXED` | Unchanged, or the change does not actually address the finding. |
   | `REGRESSED` | The fix introduced a new problem — cite it and keep the ID. |
   | `WITHDRAWN` | You were wrong in round 1. Say so plainly and drop it. |

   `FIXED` requires evidence — the line that now does the right thing. Never mark something fixed because
   the author said so.
4. **Only then** look for new findings, under a strict filter (below).
5. **Close the loop in Bitbucket.** A verdict that only exists in a chat report leaves the PR looking
   untouched. For every finding that has a comment thread, reply with the verdict and resolve the ones that
   earned it (`bitbucket-pr-threads`):

   ```powershell
   pwsh ../bitbucket-pr-comment/scripts/Add-PullRequestComment.ps1 -Url <link> -ReplyTo <id> `
       -Text "[F1] FIXED — null check added at src/Foo.cs:44 (9f3ac21)."
   pwsh ../bitbucket-pr-threads/scripts/Set-PullRequestCommentState.ps1 -Url <link> -CommentId <id> -State RESOLVED
   ```

   Resolve **only** `FIXED` and `WITHDRAWN`. `PARTIAL`, `NOT FIXED` and `REGRESSED` get a reply and stay
   open — resolving a half-addressed thread hides the remainder from the reviewer, which is worse than
   leaving it open. Threads a human raised as a *question* are theirs to close: reply, don't resolve.

## The new-findings filter

This is the rule that stops topic drift. It **narrows** the first-review scope rule (findings anchor to
changed lines) from "the whole PR diff" down to "the new commits". In follow-up mode a new finding is
reportable **only** if:

- it anchors to a line **touched by the new commits**, **or**
- it is a **regression** caused by one of the fixes, **or**
- it is a **Blocker** (security, data loss, broken build) on a line the PR changed — those are always
  reportable, whenever found.

**Do NOT** report anything else. Specifically:
- Nothing on code the PR never touched — that was out of scope in round 1 and still is.
- Nothing newly raised on code that was in the round-1 diff and that you did not flag then. You reviewed it;
  you passed it. Raising it now is moving the goalposts, and it is the single most common way an AI review
  makes a PR unmergeable.

If you notice such an issue and it genuinely matters, hold it: list it under **Deferred (not blocking this
PR)** at the end, with one line each and no severity — visible to the author, but explicitly not part of
the verdict.

## Coverage in follow-up mode

Do **not** restart the `review-coverage-loop` from zero. The baseline finding set carries over.

- The coverage loop runs on the **incremental diff only**.
- The 90% target applies to that delta, not to the whole PR again.
- Verifying the original findings is not a "pass" — it is mandatory and happens before any pass.
- Report it as `Coverage: <n>% (delta since <short-sha>, <p> passes)` so it can't be confused with a
  full-PR figure.

Typically 1–2 passes are enough here, because the surface is small. Do not spend 5 passes on a two-line
fix commit.

## Verdict rules for a follow-up

- Any original **Blocker** still `NOT FIXED` or `PARTIAL` → **CHANGES REQUESTED**.
- Any `REGRESSED` finding → **CHANGES REQUESTED**.
- All originals `FIXED`/`WITHDRAWN`, only Minor/Nit remaining → **APPROVE WITH COMMENTS**.
- All originals `FIXED`/`WITHDRAWN`, nothing new → **APPROVE**. Say so in one line and stop — a clean
  follow-up should be short.

## Output shape

The visual conventions come from `review-report-format` — same title line, same bolded severities, same
`---` + Status footer. Only the middle differs, and finding IDs **are** visible here, because in a
follow-up they *are* the agenda:

```
<!-- ai-autopilot: round=2 head=9f3ac21 ids=F1-F8 -->
# PR Review — <title> (<source> → <target>)

Round: 2   |   Previously reviewed: a1b2c3d   |   Findings carried over: 5   |   Verdict: **CHANGES REQUESTED**

## Previous findings
- **F1** FIXED — null check added at src/Foo.cs:44
- **F3** NOT FIXED — src/Foo.cs:88 still concatenates the SQL string
- **F4** PARTIAL — fixed in OrderService, same pattern remains in InvoiceService:120
- **F5** REGRESSED — the using block now disposes the stream before the caller reads it (src/Bar.cs:31)
- **F2** WITHDRAWN — the framework already encodes this; round 1 was wrong

## New findings (new commits only)
- **Major** src/Bar.cs:57 — ParseHeader: … Fix: …

## Deferred (not blocking this PR)
- src/Legacy.cs:200 — pre-existing; worth a separate ticket.

Resolved: 2 of 5   |   Coverage: 94% (delta since a1b2c3d, 2 passes)

---

**Status: REVIEW COMPLETE. Verdict: CHANGES REQUESTED**

<!-- ai-autopilot-findings: F8 Functionality src/Bar.cs:57 Major -->
```

Keep it short. A follow-up where everything is fixed is three lines, not a re-run of the first report.
