# Embedded C / C++ Review Rules (`EC-*`)

Each rule has an ID, a severity, what to look for, and the fix. Severities: **Blocker** (must fix),
**Major** (fix before merge), **Minor**, **Nit**.

| Group | Covers |
|-------|--------|
| `EC-MEM-*` | Buffers, bounds, pointer lifetime |
| `EC-TYPE-*` | Fixed-width types, signedness, conversion |
| `EC-ALLOC-*` | Heap, stack depth, recursion |
| `EC-ISR-*` | Interrupts, shared state, critical sections |
| `EC-HW-*` | Registers, volatile, timeouts, watchdog |
| `EC-INT-*` | Overflow, shifts, wraparound |
| `EC-FLOW-*` | Braces, switch, initialisation, returns |
| `EC-ERR-*` | Return codes and failure paths |
| `EC-TEST-*` | Unit tests on constrained targets |

---

## EC-MEM — Memory safety

**EC-MEM-01 — Unbounded string function** · Blocker
- **Look for:** `strcpy`, `strcat`, `sprintf`, `gets`, `scanf("%s")`.
- **Fix:** `strncpy`/`snprintf`/`strlcpy` with the destination size, and terminate explicitly — `strncpy`
  does not NUL-terminate when the source fills the buffer.

**EC-MEM-02 — Copy or index without a bounds check** · Blocker
- **Look for:** `memcpy(dst, src, len)` where `len` comes from a message, a sensor or a caller;
  `buf[i]` where `i` is computed or externally supplied.
- **Fix:** validate against the destination size *before* the copy: `if (len > sizeof dst) return ERR;`.
  On a device, the overrun silently corrupts whatever the linker put next — often the stack.

**EC-MEM-03 — Buffer size hardcoded away from the buffer** · Major
- **Look for:** `memset(buf, 0, 64)` where `buf` is declared elsewhere. The two drift apart on the next
  edit and nothing warns you.
- **Fix:** `sizeof buf` (for arrays), or a single `#define` used in both places.

**EC-MEM-04 — Pointer to a local returned or stored** · Blocker
- **Look for:** returning `&local` / a local array, or saving it into a struct that outlives the call.
- **Fix:** caller-provided buffer, or `static` with a documented lifetime.

**EC-MEM-05 — Use after free / double free** · Blocker
- **Fix:** set the pointer to `NULL` after freeing, and check before use.

**EC-MEM-06 — Off-by-one on array bounds or NUL terminator** · Blocker
- **Look for:** `for (i = 0; i <= n; i++)`, `buf[len]` for the terminator without `len + 1` in the size.

**EC-MEM-07 — Unaligned or type-punned access** · Major
- **Look for:** casting a `uint8_t*` payload to a struct pointer and dereferencing it. On Cortex-M0 and
  several other cores this is a hard fault, not a slow path.
- **Fix:** `memcpy` into a properly aligned object, or parse field by field.

---

## EC-TYPE — Types and conversion

**EC-TYPE-01 — Plain `int`/`long`/`char` where width matters** · Major
- **Fix:** `<stdint.h>` fixed-width types. `int` is 16-bit on some targets and 32-bit on others; a struct
  that matches a wire protocol must not depend on that.

**EC-TYPE-02 — Signed/unsigned comparison** · Major
- **Look for:** `if (i < len)` with `int i` and `size_t len`. `i` is promoted to unsigned, so a negative
  `i` becomes huge and the check passes.
- **Fix:** match the types, or compare after an explicit range check.

**EC-TYPE-03 — Implicit narrowing** · Major
- **Look for:** `uint8_t x = some_uint32;`, assigning a sensor `int16_t` into `int8_t`.
- **Fix:** range-check, then cast explicitly to show it is intended.

**EC-TYPE-04 — `char` used for data** · Minor
- Plain `char` has implementation-defined signedness. Use `uint8_t` for bytes, `char` only for text.

**EC-TYPE-05 — `sizeof` on a pointer instead of the array** · Blocker
- **Look for:** `sizeof(buf)` where `buf` is a function parameter — it is the pointer size, not the array.
- **Fix:** pass the length explicitly.

**EC-TYPE-06 — Bitfield or enum with assumed layout** · Minor
- Bitfield packing and enum underlying type are implementation-defined; do not map them onto hardware
  registers or wire formats. Use explicit masks and shifts.

---

## EC-ALLOC — Allocation and stack

**EC-ALLOC-01 — Dynamic allocation on a firmware path** · Blocker
- **Look for:** `malloc`, `calloc`, `realloc`, `new`, `std::vector`/`std::string` growth in a component
  that runs on the target.
- **Fix:** static or pool allocation. A device that runs for months cannot recover from heap
  fragmentation, and the failure appears long after the change that caused it.

**EC-ALLOC-02 — Large buffer on the stack** · Major
- **Look for:** local arrays of hundreds of bytes or more, especially in an ISR or a deep call chain.
- **Fix:** `static`, or a caller-provided buffer. Embedded stacks are sized in kilobytes and overflow
  silently corrupts adjacent memory.

**EC-ALLOC-03 — Recursion** · Major
- Unbounded stack depth on a bounded stack. **Fix:** iterate, or prove and document a hard bound.

**EC-ALLOC-04 — Allocation failure unchecked** · Blocker
- If dynamic allocation is genuinely allowed here, `NULL` must still be handled on every path.

---

## EC-ISR — Interrupts and concurrency

**EC-ISR-01 — Shared variable not `volatile`** · Blocker
- **Look for:** a flag or counter written in an ISR and read in `main` (or vice versa) without `volatile`.
- **Fix:** `volatile`. Without it the compiler may cache the value in a register and the loop never sees
  the update — a bug that appears only at higher optimisation levels.

**EC-ISR-02 — Non-atomic access to shared multi-byte state** · Blocker
- `volatile` alone does not make a 32-bit read atomic on an 8/16-bit core, nor a struct update atomic
  anywhere.
- **Fix:** disable interrupts around the access, use an atomic type, or a lock-free single-writer pattern.

**EC-ISR-03 — Long-running or blocking work in an ISR** · Blocker
- **Look for:** loops, `printf`, floating point, allocation, blocking I/O, `delay` inside an ISR.
- **Fix:** set a flag or post to a queue; do the work in the main loop or a task.

**EC-ISR-04 — Unbalanced or over-wide critical section** · Major
- **Look for:** a disable with an early `return` before the matching enable; a whole function guarded when
  only two lines touch shared state.
- **Fix:** restore on every path (save/restore the previous mask rather than blindly re-enabling), and
  keep the section as short as the shared access.

**EC-ISR-05 — Non-reentrant function called from an ISR** · Major
- **Look for:** shared static buffers, `strtok`, `printf`, HAL calls that are documented as non-reentrant.

---

## EC-HW — Hardware access

**EC-HW-01 — Register access without `volatile`** · Blocker
- Memory-mapped registers change outside the program's control; without `volatile` reads get optimised
  away and polling loops become infinite.

**EC-HW-02 — Unprotected read-modify-write of a shared register** · Major
- **Look for:** `REG |= BIT;` on a register another context also modifies — the sequence is not atomic.
- **Fix:** critical section, or a hardware bit-set/bit-clear register if the part has one.

**EC-HW-03 — Busy-wait without a timeout** · Blocker
- **Look for:** `while (!(REG & FLAG));`. If the peripheral never asserts, the device hangs forever with
  no diagnostic.
- **Fix:** bound the wait and return an error on timeout.

**EC-HW-04 — Watchdog not serviced on a path, or serviced blindly** · Major
- A new long-running path that never kicks the watchdog causes a reset; kicking it from a timer ISR
  defeats it entirely.

**EC-HW-05 — Magic number for a register, pin or timing value** · Minor
- **Fix:** a named constant that says what it is. `0x1F` tells the next reader nothing.

**EC-HW-06 — Delay used as synchronisation** · Major
- **Look for:** `delay_ms(10)` standing in for "the peripheral should be ready by now". It works on the
  bench and fails at temperature. **Fix:** poll the ready flag with a timeout.

---

## EC-INT — Integer behaviour

**EC-INT-01 — Overflow before assignment** · Major
- **Look for:** `uint32_t ms = seconds * 1000;` where `seconds` is 16-bit — the multiply happens in the
  narrow type. **Fix:** cast an operand up first.

**EC-INT-02 — Division or modulo without a zero check** · Blocker
- Divide-by-zero is a hard fault on many cores.

**EC-INT-03 — Shift by an invalid or signed amount** · Major
- Shifting by ≥ the width, or shifting a signed negative value, is undefined behaviour.

**EC-INT-04 — Tick/timer wraparound mishandled** · Major
- **Look for:** `if (now > deadline)`. **Fix:** `if ((int32_t)(now - deadline) >= 0)` — subtraction is
  wraparound-safe; direct comparison breaks once every wrap period, which is exactly the "hangs after a
  few weeks" bug.

**EC-INT-05 — Float on a target without an FPU** · Minor
- Software floating point is slow and often unnecessary; prefer fixed-point in hot or ISR paths.

---

## EC-FLOW — Control flow

**EC-FLOW-01 — Conditional or loop body without braces** · Major
- The classic goto-fail shape: the next edit adds a second statement and it is silently unconditional.

**EC-FLOW-02 — `switch` without `default`, or unmarked fallthrough** · Major
- **Fix:** a `default` that handles the unexpected value; mark deliberate fallthrough with a comment or
  attribute.

**EC-FLOW-03 — Variable used before initialisation** · Blocker
- Especially a struct or array filled only on some paths.

**EC-FLOW-04 — Non-void function with a path that does not return** · Blocker

**EC-FLOW-05 — Assignment inside a condition** · Minor
- `if (x = y)` — if intended, wrap in extra parentheses so the reader can tell.

---

## EC-ERR — Error handling

**EC-ERR-01 — Return code ignored** · Major
- **Look for:** a HAL or driver call whose status is discarded. The failure surfaces later as corrupt data.
- **Fix:** check it, or cast to `(void)` with a comment explaining why it cannot fail here.

**EC-ERR-02 — Failure leaves hardware in an undefined state** · Major
- **Look for:** an error path that returns without releasing the bus, deasserting chip-select, or
  restoring the interrupt mask.

**EC-ERR-03 — Error swallowed and replaced by a default value** · Major
- Returning `0` for "sensor read failed" makes a fault indistinguishable from a real measurement.

---

## EC-TEST — Tests

**EC-TEST-01 — Changed logic with no unit test** · Major
- Pure logic (parsing, state machines, conversion) is testable on the host even when the driver is not.

**EC-TEST-02 — Test requires real hardware where a fake would do** · Minor
- **Fix:** abstract the register access so the logic is testable off-target.

**EC-TEST-03 — Disabled or removed test in the diff** · Major
- If a test had to be disabled, the reason belongs in the diff.

---

## Verdict guidance

- Any Blocker (`EC-MEM-*` overrun, `EC-ISR-01/02/03`, `EC-HW-01/03`, `EC-ALLOC-01/04`, `EC-INT-02`,
  `EC-FLOW-03/04`) → **CHANGES REQUESTED**.
- Several Major findings, or any change that breaks a build or a variant → **CHANGES REQUESTED**.
- Only Minor/Nit → **APPROVE WITH COMMENTS**.
- Nothing of substance → **APPROVE**.
