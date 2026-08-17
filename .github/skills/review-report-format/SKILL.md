---
name: review-report-format
description: 'The exact shape of a posted PR review comment: the title line, the Jira/files/project-type/verdict metadata line, the Summary paragraph, Findings by Area with a bolded per-area verdict, the `**Severity** file:line — Symbol: problem. Fix: …` finding line, the ✅/⚠️ style for ticket alignment, the themed numbered Blockers section, Nice-to-have, and the Status footer. Use when composing or posting a review to a pull request, or when asked "make the review look like ours", "format the review", "why does the report look different", "post the review". Owned by the PR Review Orchestrator; every reviewer''s section is rendered through it.'
---

# Review Report Format

One reviewer writing `[F3][Major] Foo.cs:12 — CS-SEC-04 …` and another writing `Major: Foo.cs line 12`
produces a report nobody reads. This skill is the single definition of what lands in the PR comment.

**The reviewers' output does not change.** Sub-agents keep emitting `[F<n>][Severity] file:line — <RULE-ID>
issue. Fix: …` — that is the internal contract the coverage loop and follow-up rounds depend on. This skill
governs the **rendering** step: how the orchestrator turns those sections into the posted comment.

A full worked example: **[references/example-report.md](./references/example-report.md)**. Read it once —
it is faster than this description.

## The template

````markdown
<!-- ai-autopilot: round=<n> head=<short-sha> ids=F1-F<max> -->
# PR Review — <PR title> (<source-branch> → <target-branch>)

Jira: <KEY, KEY | none>   |   Files changed: <n>   |   Project type: <family>   |   Verdict: **<VERDICT>**

## Summary

<One paragraph. What the change does, then the headline risk classes in **bold**. Ends with a sentence
saying what must happen before merge.>

## Findings by Area

### Functionality            **<PASS | COMMENTS | CHANGES>**
- **<Blocker|Major|Minor|Nit>** <file>:<line> — <Symbol>: <what is wrong and what it causes>. Fix: <what to do>.

### PR Description Match      **<PASS | COMMENTS | CHANGES>**
- **<Severity>** <what the description claims vs what the diff does>. <What to change.>

### Jira Ticket Alignment     **<PASS | COMMENTS | CHANGES>**
- ✅ <requirement that is met>
- ⚠️ **<concern>**: <why it is a concern>.

### AppConstants / Config     **<PASS | COMMENTS | CHANGES>**
- **<Severity>** <file>:<line> — <literal> hardcoded. Fix: Use <Constants>.<NAME> constant.

### Coding Standards (<ruleset name>)  **<PASS | COMMENTS | CHANGES>**
- **<Severity>** <file>:<line> — <Symbol>: <issue>. Fix: <suggestion>.

## Blockers (must fix before merge)

1. **<Theme>** (<file>:<line>, <line>, <line>) — <why it matters, in one or two sentences>. <The fix.>

## Nice-to-have

- <improvement that is not a defect>

## Deferred (not blocking this PR)

- <file>:<line> — <issue in code this change did not touch>

---

**Status: REVIEW COMPLETE. Verdict: <VERDICT>**
````

`<VERDICT>` is `APPROVE`, `APPROVE WITH COMMENTS` or `CHANGES REQUESTED`. Area verdicts are the shorter
`PASS | COMMENTS | CHANGES`, **bolded**, aligned to roughly one tab past the longest heading.

## Rules that are easy to get wrong

**No `[F<n>]` and no rule IDs in the visible text.** They are noise to the author, who wants to know
*where* and *what*, not which internal rule fired. Keep them in the hidden index (below) so follow-up
rounds still have stable IDs.

**Lead with the symbol, not the rule.** `Program.cs:537 — ResolveAssigneeAccountId: HttpResponseMessage
never disposed` beats `Program.cs:537 — CS-RES-02 resource leak`. The author navigates by function name.

**Every finding says what it causes.** "never disposed; early returns leak the connection" — not just
"not disposed". A finding the author can't judge the severity of is a finding they argue with.

**Every finding ends with `Fix:` and a concrete action.** "Wrap response in a `using` statement", not
"consider improving resource management".

**Ticket alignment uses ✅ / ⚠️, not severities.** That section answers "does this satisfy the ticket",
which is a yes/no per requirement plus concerns — not a defect list. `✅` for a met requirement, `⚠️` with
a **bold lead-in** for a gap or an unverified assumption.

**Blockers are themed, not copied.** The `## Blockers` section is not the Blocker-severity findings pasted
again. Group them by root cause across areas, collapse the file:line list into the parentheses, and add
the consequence the per-finding line was too short to carry:

> 2. **HttpResponseMessage resource leaks** (Program.cs:537, 615, 648, 671, 693, 706, 780) — All HTTP
>    responses must be disposed in `using` statements or try-finally blocks. Without disposal, TCP
>    connections hang until GC.

Seven findings, one blocker entry. If a theme has one member, it still gets its own numbered entry.

**Nice-to-have is not a severity.** It holds suggestions that were never findings — a pattern worth
adopting, a test worth adding, something worth documenting. Never demote a real Minor finding into it.

**Omit an empty section.** No deferred items → no `## Deferred` heading; nothing nice-to-have → drop that
section too. An empty heading reads as an oversight. `## Deferred` carries no severities and never affects
the verdict — it exists so the author knows you saw the problem and chose not to charge it to this PR.

**Areas that did not run are not listed.** Only the reviewers that actually ran get a `###` heading. Name
the ruleset in the Coding Standards heading — `### Coding Standards (C# Web App Rules)`, `(Embedded C
Rules)`, `(SPLE Platform Standards)`, `(Python Rules)` — one heading per ruleset that ran.

**The metadata line is short.** Jira keys, file count, project-type slug from `project-type-detect`,
verdict in bold. Coverage and deferred counts do **not** go here — see below.

## Where the machine-readable parts live

The rendered comment must look like the template, so the bookkeeping is invisible:

```
<!-- ai-autopilot: round=1 head=a1b2c3d ids=F1-F31 -->     <- first line, before the title
...
<!-- ai-autopilot-findings:
F1 Functionality Program.cs:537 Blocker
F2 Functionality Program.cs:615 Blocker
F13 AppConstants Configuration/SecureConfigurationManager.cs:14 Major
-->                                                         <- last lines, after the Status footer
```

The round marker is **required** — `Get-PullRequestContext.ps1` finds the previous review by it, and
without it follow-up mode silently degrades into a fresh full review. The findings index is what lets
round 2 say "F13 FIXED" about a finding whose visible line never showed an ID.

Deferred items stay **visible** (they are information the author wants), but coverage does not — it is
process telemetry, and a table of it in the body buries the findings:

```
<!-- ai-autopilot-coverage: overall=92% lowest=Functionality passes=3 -->
```

If coverage stalled below 90%, say so in **one sentence at the end of the Summary** — the author needs to
know the review may be incomplete, and that belongs in prose, not a table.

## Inline comments

The summary comment above is posted once, at PR level. Findings that anchor to a changed line are *also*
posted inline via `bitbucket-pr-comment`, in a shorter form — the author reads them next to the code:

```
**Major** ResolveAssigneeAccountId: HttpResponseMessage never disposed; early returns leak the
connection. Fix: wrap in a `using` statement.
```

Same severity vocabulary, no file:line (the anchor supplies it), no ID. Do not post an inline comment for
a finding that has no line anchor — it belongs only in the summary.

## Follow-up rounds

Round 2+ uses the `review-followup` skill's shorter shape, with this skill's visual conventions: bolded
severities, the same metadata line with `Round: 2`, `## Previous blockers` (one `**F<n>** VERDICT —
evidence` line each, IDs **are** visible here because they are the agenda), then `## Still open (not
blocking)` for round-1 Majors/Minors carried over verbatim, then `## New findings (new commits only)`, then
the same `---` + Status footer. Do not restate the round-1 report.

Two shape rules specific to a follow-up:
- The `## Blockers (must fix before merge)` section lists **only** unfixed previous Blockers, regressions and
  Blockers the new commits introduced. A carried-over Major never appears there, however long it stays open.
- The hidden findings index keeps each finding's **original severity**, not a re-judged one, so the next
  round can still tell the agenda from the carry-over.

## Checklist before posting

- [ ] Round marker is the first line; findings index is the last block.
- [ ] Title carries the PR title and both branch names.
- [ ] Metadata line: Jira, file count, project type, **bolded** verdict.
- [ ] Summary is one paragraph and names the risk classes in bold.
- [ ] Every area heading has a bolded `PASS | COMMENTS | CHANGES`.
- [ ] Every finding: `**Severity** file:line — Symbol: problem + consequence. Fix: action.`
- [ ] No `[F<n>]` and no rule IDs in the visible text.
- [ ] Ticket alignment uses ✅ / ⚠️.
- [ ] Blockers are themed and numbered, with aggregated locations and a consequence.
- [ ] Empty sections removed; `## Deferred` present only if something was deferred.
- [ ] Footer is `**Status: REVIEW COMPLETE. Verdict: <VERDICT>**` after a `---`.
