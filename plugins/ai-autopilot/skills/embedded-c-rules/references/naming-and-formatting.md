# Naming, formatting and documentation (`EC-NAME-*`, `EC-FMT-*`, `EC-DOC-*`)

The "beyond MISRA" layer: the rules a static analyser does not enforce but a maintainer feels every day.
MISRA and Polyspace say nothing about whether a static is called `reinitFlag` or `s_reinitFlag`.

## The prime directive: derive the convention, don't impose one

**Read the module before judging a name.** Every one of these repos has a house style, it is rarely
written down, and it is visible in the first thirty lines of any existing file. A finding that says
"use `snake_case`" in a file where every other function is `PREFIX_camelCase` is worse than no finding.

Establish, from the file being changed and its siblings:

| Element | How to establish it | Typical embedded form |
|---------|--------------------|-----------------------|
| Module prefix | The prefix on the existing public functions and macros of that file | `TCHH_` for `touch_helper.c`, `TCHU_` for `touch_ui.c` |
| Functions | Existing public API in the header | `TCHH_loadScanConfig` — `PREFIX_` + `camelCase` |
| Macros / constants | Existing `#define`s | `TCHH_SCAN_NVM_DATA_SIZE` — `PREFIX_UPPER_SNAKE` |
| Types | Existing `struct`/`enum`/`typedef` | `struct TouchScaleDataType`, `enum AcquisitionStateType` — PascalCase + `Type`, or `snake_case_t` |
| Enum constants | Existing enumerators | `TCHH_STATE_WAIT_FOR_DATA` — module prefix, upper snake |
| Scope markers | Existing statics and globals | `s_` static / module-local, `g_` global, `p`/`p_` pointer |
| Files | Sibling file names | `touch_helper.c` / `touch_helper.h`, guard `TOUCH_HELPER_H` |

Then review **against that**, and report a deviation from the module's own convention — not from a
convention you brought with you.

---

## EC-NAME — Naming

**EC-NAME-01 — New identifier breaks the module's convention** · Major
A function, macro, type or enumerator added without the module prefix its neighbours all carry, or in a
different case style. It makes the symbol unfindable by prefix search and unattributable in a map file or
a stack dump. Fix: rename to match the file's existing form.

**EC-NAME-02 — File-scope object with no scope marker** · Major
A `static` variable, or a global, whose name does not say so. Nothing at the use site distinguishes
`reinitFlag` (module state, shared with the ISR) from a local. This is the single most common real
finding in embedded code, and it is exactly the class of confusion that produces a race. Fix: adopt the
module's marker (`s_` / `g_` / the module prefix) — consistently, including the identifiers the change
did not add.

**EC-NAME-03 — Inconsistent type suffix** · Minor
`Type`, `_t` and a bare name in the same module. Pick the one the file already uses. Note that `_t` is
reserved by POSIX for the implementation; if the project uses it anyway, that is a project decision —
report the inconsistency, not the choice.

**EC-NAME-04 — Meaningless or ambiguous name** · Minor
`data`, `tmp`, `flag`, `val`, `buf2` on anything wider than a few lines, or a name that says the type
(`uint8Value`) instead of the meaning (`crcPosition`). Loop counters `i`/`j` are fine.

**EC-NAME-05 — Abbreviation invented for this file** · Nit
`cfgNvmTgtBl`. If the abbreviation is not already used in the module or the datasheet, spell it out.

**EC-NAME-06 — Name shadows or nearly collides** · Major
A local that shadows a file-scope object, or two identifiers differing only in case or by one character
(`slotId` / `slotID`). The compiler is happy; the reader is not.

**EC-NAME-07 — Index or magic-value macro per literal** · Nit
`#define TCHH_IDX_0 (0u)` … `TCHH_IDX_11 (11u)`. A macro whose name is its value carries no information
and does not satisfy the intent of "no magic numbers". Fix: name the *meaning* (`TCHH_CRC_POSITION`), or
leave the literal.

---

## EC-FMT — Formatting and structure

**EC-FMT-01 — Formatting inconsistent with the file** · Nit
Indent width, brace placement, pointer binding (`uint8_t *p` vs `uint8_t* p`), space after keywords.
Match the file. If the repo has a `.clang-format`, it wins over everything here — and a finding should be
"run clang-format", not a list of lines.

**EC-FMT-02 — Section banner missing or wrong** · Nit
Many embedded houses divide a file with banner comments (`/* INCLUDES */`, `/* PRIVATE DEFINITIONS */`,
`/* PUBLIC FUNCTIONS */`) and place declarations in that order. If the file has them, keep new code in
the right section instead of appending to the end.

**EC-FMT-03 — Function too long or too deeply nested** · Major
A function that does not fit on a screen, or nesting past three levels, in code that must be reviewed
line by line for safety certification. Fix: extract the inner block as a named static helper.

**EC-FMT-04 — Line unreadably long** · Nit
Beyond the file's evident limit (usually 100–120). Wrap the parameter list rather than reformatting the
whole file.

**EC-FMT-05 — Include order or unnecessary include** · Minor
Own header first, then project, then library — or whatever the file does. A new include that nothing in
the change uses is a dependency added for free.

**EC-FMT-06 — Header does something a header should not** · Major
Definitions (not declarations) of objects or non-inline functions in a `.h`, a missing include guard, or
a guard whose macro does not match the file name. Multiple definition errors appear only once a second
translation unit includes it.

**EC-FMT-07 — Unparenthesised or unsuffixed constant macro** · Major
`#define MASK 0x3FF` used in an expression. Fix: `#define TCHH_CTSUSO_SO_MASK (0x3FFU)` — parentheses
against precedence surprises, `U` against the implicit signed type. Also flag mixed `U`/`u` in one file
(Nit).

**EC-FMT-08 — Commented-out code or a stray debug artefact** · Minor
A disabled block, a leftover `printf`, a `// TODO` with no ticket. Delete it; git remembers.

---

## EC-DOC — Documentation

**EC-DOC-01 — Public API without a doc comment** · Major
A function added to a header with no Doxygen block, in a file where the rest of the API has one. On an
embedded API the parameter contract (units, valid range, who owns the buffer, whether it may be called
from an ISR) is not inferable from the signature. Fix: `@brief`, one `@param` per parameter, `@return`
with the meaning of each returned code.

**EC-DOC-02 — Doc comment contradicts the code** · Major
A `@param` for an argument that no longer exists, a `@return true/false` on a function returning
`uint8_t`, a `@brief` describing the previous behaviour. A stale comment is worse than none — it is
believed. Check every doc block whose function the diff changed.

**EC-DOC-03 — Comment restates the code** · Nit
`/* increment i */`. Comment the *why*: the datasheet section, the erratum, the timing constraint, the
reason the order matters.

**EC-DOC-04 — Magic hardware value undocumented** · Major
A register value, timeout or scaling constant with no comment naming the datasheet section or the unit it
is in. Overlaps `EC-HW-05`; report once.

**EC-DOC-05 — File header missing** · Nit
Where the module uses a `\file` / `@file` block with brief and details, a new file without one.

---

## Severity discipline

Naming and formatting are **Minor/Nit by default**. They become Major only when they cause a real
misreading — an unmarked file-scope object shared with an ISR (`EC-NAME-02`), a header that defines
objects (`EC-FMT-06`), a doc comment that lies about a return code (`EC-DOC-02`).

Never let this group dominate a review. If a diff produces twenty naming nits, report the **pattern**
once with two or three examples and the fix, not twenty lines:

```
[F9][Nit] app/prog/touch_control/touch_main.c — EC-NAME-02 file-scope statics lack the `s_`/module
  prefix the header's API uses (`reinitFlag`:53, `tuningTarget`:61, +6 more). Fix: prefix them, or drop
  the marker project-wide — the mix is the problem.
```
