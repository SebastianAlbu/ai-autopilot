# Polyspace / MISRA rules (`EC-MISRA-*`)

The MISRA layer of the embedded review. It is driven by the project's **own** Polyspace checkers
selection, not by a fixed list — every variant enables a different subset, and reporting a rule the
project has switched off is noise.

Get the real list before reviewing:

```powershell
pwsh .github/skills/embedded-c-rules/scripts/Get-PolyspaceCheckers.ps1                    # enabled here
pwsh .github/skills/embedded-c-rules/scripts/Get-PolyspaceCheckers.ps1 -State notimplemented
```

The file is `variants/<variant>/<NAME>.xml` (root element `<polyspace_checkers_selection>`); the script
finds it, or set `POLYSPACE_CHECKERS_XML`.

## The three states, and what each means for a reviewer

| State | Meaning | What you do |
|-------|---------|-------------|
| `on` | Polyspace reports it; a violation fails the quality gate. | Report it — but as **Major**, not Blocker, unless the code is also genuinely unsafe. The tool would have caught it anyway; you are saving a CI round-trip. |
| `off` | Deliberately excluded from this project's MISRA subset. | **Do not report it as a MISRA finding.** If the code is dangerous for a non-MISRA reason, report it under the `EC-*` rule that actually describes the defect. |
| `notimplemented` | In scope, but Polyspace **cannot** check it. | **Highest value.** No tool covers these. If a changed line touches one, it is yours to catch — nothing else will. |

That third row is the point of this reference. A reviewer who only re-checks what Polyspace already
checks adds nothing; the `notimplemented` set is where a human/AI pass is the only gate.

## Typical enabled set (embedded, C99/C11, no dynamic memory)

Rule titles below are abridged — consult the MISRA C:2012 text (with Amendments 2/3) for the normative
wording. A concrete example: the RL78 touch variant enables 18 MISRA C:2012 rules plus the whole of
**SEI CERT C**.

**Literals, initialisation, expressions**

| Rule | What it catches |
|------|-----------------|
| 7.5 | Argument of an integer-constant macro (`UINT16_C(x)`) has an inappropriate form. |
| 9.1 | An automatic object is **read before it is set** — the classic uninitialised-local bug. |
| 12.5 | `sizeof` applied to a function parameter declared as an array type (it is a pointer). |

**Functions**

| Rule | What it catches |
|------|-----------------|
| 17.3 | A function is declared implicitly — a missing include, not a style issue. |
| 17.4 | A non-void function has an exit path with no `return <expr>`. |
| 17.6 | `static` between the `[ ]` of an array parameter. |
| 17.9 | A `_Noreturn` function that can return to its caller. |

**Overlapping storage**

| Rule | What it catches |
|------|-----------------|
| 19.1 | An object is assigned or copied to an **overlapping** object (`memcpy` on overlapping ranges — use `memmove`). |

**Standard library** — mostly moot on bare metal, but they fire on host-side tests and tooling.

| Rule | What it catches |
|------|-----------------|
| 21.13 | A `<ctype.h>` argument not representable as `unsigned char` or `EOF` (a plain `char` that is negative). |
| 21.17 | `<string.h>` use that reads or writes **beyond the bounds** of its pointer arguments. |
| 21.18 | A `size_t` argument to a `<string.h>` function with a value larger than the object. |
| 21.19 / 21.20 | Pointers from `localeconv`/`getenv`/`setlocale`/`strerror`/`asctime`/… treated as writable, or used after the next call to the same function. |
| 21.22 | `<tgmath.h>` type-generic macro applied to an argument of the wrong essential type. |

**Resources**

| Rule | What it catches |
|------|-----------------|
| 22.2 | Freeing memory that was not allocated by a standard allocation function. |
| 22.4 | Writing to a stream opened read-only. |
| 22.5 | Dereferencing a `FILE *`. |
| 22.6 | Using a `FILE *` after the stream was closed. |

## The `notimplemented` gap — review is the only gate

These are the rules a typical embedded selection keeps in scope but Polyspace does not implement. Check
them by hand whenever a changed line is in range:

| Rule | Check it by |
|------|-------------|
| **D3.1** | Every requirement is traceable to code and vice versa — does the change carry the requirement/ticket reference the project's process demands? |
| **D4.2** | All assembly is documented and encapsulated (`__asm`, intrinsics behind a wrapper with a comment saying why). |
| **D5.3** | No dynamic thread/task creation after start-up. |
| **2.8** | Unused object definitions — a `static` variable or object added and never read. |
| **7.6** | Small-integer variants of the minimum-width constant macros (`UINT8_C`, `INT8_C`) used at all. |
| **9.6** | Chained-designator initialisers mixed with positional ones. |
| **9.7** | An atomic object accessed before `atomic_init`. |
| **11.10** | `_Atomic` applied to `void`. |
| **12.6** | A member of an atomic struct/union accessed directly instead of through an atomic operation. |
| **18.10** | Pointers to variably-modified array types. |
| **21.25 / 21.26** | Memory-order argument other than sequentially-consistent; `mtx_timedlock` on a mutex that is not timed. |
| **22.12 – 22.14** | Thread objects, sync objects and TSS pointers: right access functions, right storage duration, initialised before use. |
| **22.18 – 22.20** | Non-recursive mutex locked recursively; one condition variable bound to two mutexes; TSS pointer used before it was created. |

On a bare-metal target most of the C11 threads/atomics rows are inert — say so once and move on rather
than reporting "not applicable" per rule. The rows that bite in practice on real firmware are **D3.1**,
**D4.2**, **D5.3** and **2.8**.

## SEI CERT C

When the `SEI CERT C` standard is `on` as a whole, the enabled set is much wider than the MISRA subset
and overlaps the `EC-*` rules almost exactly. Treat it as confirmation that the following are enforced
project rules, not preferences — report them under their `EC-*` id and mention the CERT family:

| CERT family | `EC-*` equivalent |
|-------------|-------------------|
| `ARR30-C`, `ARR38-C`, `STR31-C` (bounds, NUL) | `EC-MEM-02`, `EC-MEM-06` |
| `INT30-C`, `INT31-C`, `INT32-C` (wrap, truncation, signed overflow) | `EC-INT-01`, `EC-TYPE-03` |
| `MEM30-C`, `MEM31-C`, `MEM34-C` (use-after-free, leak, free of non-heap) | `EC-MEM-05`, `EC-ALLOC-*` |
| `EXP33-C` (uninitialised read) | `EC-FLOW-03` — and MISRA 9.1 |
| `CON` family (concurrency) | `EC-ISR-*` |
| `SIG31-C` (shared object from a handler) | `EC-ISR-01`, `EC-ISR-02` |
| `ERR33-C` (unchecked return) | `EC-ERR-01` |

## Reporting

Cite both ids when a finding is a MISRA violation the project enforces:

```
[F3][Major] app/prog/touch_control/touch_helper.c:118 — EC-MISRA MISRA 9.1 (Polyspace: on)
  `crc` is read before it is set on the early-return path. Fix: initialise at declaration.
```

For a `notimplemented` rule, say so — it tells the author no tool would have found it:

```
[F5][Major] app/prog/touch_control/touch_main.c:64 — EC-MISRA MISRA 2.8 (Polyspace: not implemented)
  `s_lastSlotId` is defined and never read. Fix: remove it, or use it in the reinit path it was added for.
```

Never report a rule whose state is `off` as a MISRA finding.
