---
name: review-followup
description: 'Re-review mode for a pull request that has already been reviewed and has since received new commits. Audits the previous round''s Blockers only — verify each as Fixed / Partial / Not fixed / Regressed — instead of opening a fresh set of unrelated topics or re-blocking on non-blockers. Runs end to end without asking. Use whenever a PR already has a review comment, when the author says "I fixed it", "please re-review", "check my changes", "review again", or when new commits landed after a previous review.'
---

# Follow-up Review (round 2+)

A second review that raises a brand-new set of topics is worse than useless: the author fixes what you
asked for, gets a different list back, and the PR never converges. **A follow-up review is an audit of the
previous review's Blockers, not a new review.**

## The two rules that define this mode

1. **Blockers only.** The agenda for round 2+ is the round-1 **Blockers** plus open human reviewer threads.
   Majors, Minors and Nits from round 1 are carried over as information — they are *never* re-verified in
   depth and *never* affect the verdict.
2. **Nothing new becomes blocking.** A finding that was not a Blocker in a previous round cannot become one
   now. The only new blocking items allowed are a genuine **regression** caused by one of the fixes, or a
   true **Blocker** (security, data loss, broken build) introduced by the new commits.

Escalating a Major to a Blocker in round 2 — or blocking on an untouched hardcoded constant the author was
never asked to treat as a blocker — is the failure mode this skill exists to prevent. If in doubt, it is
not a blocker.

## Run it without asking

Follow-up mode is **fully autonomous**. When the user says "review again", "re-review", "check my changes",
"round 2", or just re-runs the review on a PR that already has one:

- Do **not** ask which mode to use, what to verify, whether to post, or offer a menu of options. Detect the
  mode, do the work, post the comment, reply to and resolve the threads that earned it, then report the
  comment link in one or two lines.
- Do **not** stop after drafting the report to request confirmation. Drafting and posting are one step.
- The only acceptable questions are for missing inputs you cannot derive (no PR link and no branch) or a
  hard failure (401/403 on posting — say the token lacks write permission).

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

1. **Load the previous findings** — from the posted PR comment or the saved report. Split them in two:
   the **Blockers** (your agenda) and **everything else** (carry-over information). If you cannot recover
   the list, say so explicitly and fall back to a first-review; do not silently improvise a new agenda.
   The mechanism is the **`bitbucket-pr-threads`** skill: `Get-PullRequestComments.ps1 -Url <link>` returns
   every thread with its **comment id**, state and replies — both this system's round-1 comment and anything
   a human reviewer added since. Open human threads are part of the agenda regardless of severity: a
   reviewer's own request is theirs, not yours to downgrade.
2. **Get the incremental diff** — what changed *since the reviewed commit*, not the whole PR diff again.
3. **Verify each previous Blocker** against the new code. Exactly one verdict each:

   | Verdict | Meaning |
   |---------|---------|
   | `FIXED` | The problem is gone and the fix is correct. |
   | `PARTIAL` | Addressed in one place but not all, or the fix is incomplete. |
   | `NOT FIXED` | Unchanged, or the change does not actually address the finding. |
   | `REGRESSED` | The fix introduced a new problem — cite it and keep the ID. |
   | `WITHDRAWN` | You were wrong in round 1. Say so plainly and drop it. |

   `FIXED` requires evidence — the line that now does the right thing. Never mark something fixed because
   the author said so.
4. **Carry over the non-blockers without re-litigating them.** Do not re-read files, dispatch reviewers or
   spend passes on round-1 Majors/Minors/Nits. Repeat each as a single line under **Still open (not
   blocking)**, unchanged. Only two things can change that line:
   - the incremental diff touches the exact line — then mark it `FIXED` if it plainly is, and drop it;
   - the author replied on its thread — then answer the reply.
   A non-blocker that is still unaddressed stays a non-blocker. It never becomes CHANGES REQUESTED.
5. **Only then** look for new findings, under the strict filter below.
6. **Close the loop in Bitbucket.** A verdict that only exists in a chat report leaves the PR looking
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
   Do all of this without asking for confirmation.

## The new-findings filter

This is the rule that stops topic drift. In follow-up mode a new **blocking** finding is reportable **only**
if:

- it is a **regression** caused by one of the fixes, **or**
- it is a genuine **Blocker** (security, data loss, broken build) on a line the **new commits** touched.

Everything else is not reportable as a finding at all. Specifically:
- Nothing on code the PR never touched — that was out of scope in round 1 and still is.
- Nothing newly raised on code that was in the round-1 diff and that you did not flag then. You reviewed it;
  you passed it. Raising it now is moving the goalposts, and it is the single most common way an AI review
  makes a PR unmergeable.
- No promotion of a previous Major/Minor to Blocker because it is "still not fixed". Its severity was set in
  round 1 and is frozen.
- A non-blocker issue genuinely introduced by the new commits is worth one line under **Nice-to-have**, with
  its severity, and no effect on the verdict.

If you notice an issue that fails this filter and it genuinely matters, hold it: list it under **Deferred
(not blocking this PR)** at the end, with one line each and no severity — visible to the author, but
explicitly not part of the verdict.

## Coverage in follow-up mode

Do **not** restart the `review-coverage-loop` from zero. The baseline finding set carries over.

- The coverage loop runs on the **incremental diff only**, and only for the Blocker agenda plus the
  regression check. Carried-over non-blockers are not part of the coverage denominator.
- The 90% target applies to that delta, not to the whole PR again.
- Verifying the previous Blockers is not a "pass" — it is mandatory and happens before any pass.
- Report it as `Coverage: <n>% (delta since <short-sha>, <p> passes)` so it can't be confused with a
  full-PR figure. Also report `Blockers resolved: <x> of <y>` — that, not coverage, is the number that
  says whether the PR can merge.

Typically 1–2 passes are enough here, because the surface is small. Do not spend 5 passes on a two-line
fix commit.

## Verdict rules for a follow-up

Only Blockers decide the verdict:

- Any previous **Blocker** still `NOT FIXED` or `PARTIAL` → **CHANGES REQUESTED**.
- Any `REGRESSED` finding, or a new Blocker introduced by the new commits → **CHANGES REQUESTED**.
- All previous Blockers `FIXED`/`WITHDRAWN`, with round-1 Majors/Minors still open → **APPROVE WITH
  COMMENTS**. Say the remaining items are non-blocking and were not re-verified.
- All previous Blockers `FIXED`/`WITHDRAWN` and nothing new qualifies → **APPROVE**. Say so in one line and
  stop — a clean follow-up should be short.
- Carried-over non-blockers, **Nice-to-have** and **Deferred** items never change the verdict.

## Output shape

The visual conventions come from `review-report-format` — same title line, same bolded severities, same
`---` + Status footer. Only the middle differs, and finding IDs **are** visible here, because in a
follow-up they *are* the agenda:

```
<!-- ai-autopilot: round=2 head=9f3ac21 ids=F1-F8 -->
# PR Review — <title> (<source> → <target>)

Round: 2   |   Previously reviewed: a1b2c3d   |   Blockers carried over: 2   |   Verdict: **CHANGES REQUESTED**

## Previous blockers
- **F1** FIXED — null check added at src/Foo.cs:44
- **F3** NOT FIXED — src/Foo.cs:88 still concatenates the SQL string
- **F5** REGRESSED — the using block now disposes the stream before the caller reads it (src/Bar.cs:31)
- **F2** WITHDRAWN — the framework already encodes this; round 1 was wrong

## Still open (not blocking)
<Round-1 Majors/Minors/Nits, carried over verbatim, not re-verified and not part of the verdict.>
- **Major** src/Baz.cs:12 — bitrate still hardcoded (from round 1)

## New findings (new commits only)
- **Blocker** src/Bar.cs:57 — ParseHeader: … Fix: …
<Only regressions and genuine Blockers block. Anything else goes under Nice-to-have.>

## Deferred (not blocking this PR)
- src/Legacy.cs:200 — pre-existing; worth a separate ticket.

Blockers resolved: 2 of 4   |   Coverage: 94% (delta since a1b2c3d, 2 passes)

---

**Status: REVIEW COMPLETE. Verdict: CHANGES REQUESTED**

<!-- ai-autopilot-findings: F8 Functionality src/Bar.cs:57 Blocker -->
```

Keep it short. A follow-up where every blocker is fixed is three lines, not a re-run of the first report.
Post it to the PR in the same step — do not present it in chat and wait to be told to publish it.
