---
name: embedded-c-rules
description: 'The rule set for reviewing embedded / firmware C and C++ changes: memory safety (buffer overruns, unchecked bounds, strcpy/sprintf), fixed-width and signedness discipline, dynamic allocation and stack depth on constrained targets, `volatile` and register access, interrupt-safety and shared-state races, integer overflow and implicit conversion, MISRA-leaning practices, and hardware/timing assumptions. Use whenever a diff touches .c/.h/.cpp/.hpp files, an ISR, a driver, a linker script or a HAL — including plain requests like "review this firmware change", "check my interrupt handler", "is this safe on the MCU", "why does this hang after a few hours". Applies to embedded C anywhere: bare-metal, RTOS, and the C components inside an SPLE / spl-core repo.'
---

# Embedded C / C++ Review Rules

Review rules for firmware and embedded C/C++ changes. The full rule set with IDs, severities and examples
is in **[embedded-c-rules.md](./references/embedded-c-rules.md)** (rule IDs `EC-*`) — read it before
reporting, so every finding cites a rule and a concrete fix.

Embedded defects are expensive in a way desktop defects are not: the device is in a field, a car or a
factory, the failure is intermittent, and there is no stack trace. A missing `volatile`, an ISR touching a
multi-byte variable, or one unchecked `memcpy` produces a fault that reproduces once a week and cannot be
debugged remotely. This rule set names the patterns that cause exactly that.

## How to Apply

1. Read the reference and walk the diff hunk by hunk, mapping each changed region to the relevant
   categories:
   - **Memory safety (`EC-MEM-*`)** — bounds checks before indexing and `memcpy`, `strcpy`/`sprintf`/
     `gets` replaced by bounded forms, array size derived from the array, no return of a pointer to a
     local, no use-after-free.
   - **Types (`EC-TYPE-*`)** — fixed-width types (`uint8_t`, `int32_t`) over `int`/`long`, signed/unsigned
     comparison, implicit narrowing, `sizeof` on the right operand, enum/bitfield width.
   - **Allocation & stack (`EC-ALLOC-*`)** — no `malloc`/`new` on firmware paths (fragmentation has no
     recovery on a device that runs for years), large buffers moved off the stack, recursion avoided.
   - **Concurrency & ISRs (`EC-ISR-*`)** — shared state `volatile` *and* access-atomic, ISRs short and
     allocation-free, critical sections minimal and balanced, no blocking calls in interrupt context.
   - **Hardware (`EC-HW-*`)** — `volatile` on memory-mapped registers, read-modify-write of registers
     protected, no busy-wait without a timeout, watchdog serviced on all paths.
   - **Integers (`EC-INT-*`)** — overflow before assignment, division by zero, shift width and signedness,
     timer/tick wraparound handled by subtraction.
   - **Control flow (`EC-FLOW-*`)** — braces on every conditional, no fallthrough without a marker,
     `switch` has `default`, all variables initialised, every non-void path returns.
   - **Errors (`EC-ERR-*`)** — return codes checked, not ignored; failure paths leave the peripheral in a
     defined state.
2. Prefer what the repo already enforces. If it has a `.clang-format`, a cppcheck suppression list, an
   `AGENTS.md` or a documented MISRA subset, that wins over this reference — note the discrepancy rather
   than silently overriding it.
3. Cite the rule ID and give a concrete fix for each finding.

## Scope

Report only on lines this change touched (see the `review-coverage-loop` skill). Reading surrounding code —
the ISR that shares a variable, the caller that sizes the buffer — is exactly how these defects are found;
just anchor the finding to the changed line.

In an SPLE / spl-core repo the `sple-standards` skill owns component structure, CMake, KConfig and variant
wiring; this skill owns the C code itself. Check both, but report each finding once — whichever rule set
describes the actual defect.

## Output Format

```
### Embedded C Rules  <PASS | COMMENTS | CHANGES>
- [F<n>][Blocker|Major|Minor|Nit] file:line — <EC-ID> <issue>. Fix: <suggestion>.
- …
```
Memory-safety and ISR-race findings are Blockers — those are the ones that corrupt state in the field.
Several Major issues also warrant CHANGES. A clean diff returns PASS.
