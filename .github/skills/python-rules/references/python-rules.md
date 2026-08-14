# Python Review Rules (`PY-*`)

Each rule has an ID, a severity, what to look for, and the fix. Severities: **Blocker** (must fix),
**Major** (fix before merge), **Minor**, **Nit**.

| Group | Covers |
|-------|--------|
| `PY-CORR-*` | Correctness traps that still pass tests |
| `PY-ERR-*` | Exception handling and error propagation |
| `PY-RES-*` | Files, sockets, connections, subprocesses |
| `PY-API-*` | Typing and public interface shape |
| `PY-SEC-*` | Injection, deserialization, secrets, transport |
| `PY-PERF-*` | Avoidable complexity and I/O |
| `PY-TEST-*` | pytest conventions and coverage of the change |
| `PY-PKG-*` | Imports, dependencies, packaging |

---

## PY-CORR — Correctness

**PY-CORR-01 — Mutable default argument** · Major
The default is created once at function definition, so it is shared by every call and accumulates state.
- **Look for:** `def f(items=[])`, `def f(opts={})`, `def f(t=set())`.
- **Fix:** `def f(items=None):` then `items = [] if items is None else items`.

**PY-CORR-02 — Late-binding closure in a loop** · Major
Lambdas and inner functions capture the *variable*, not its value, so every closure sees the last value.
- **Look for:** `handlers = [lambda: use(i) for i in range(n)]`, callbacks defined in a `for` body.
- **Fix:** bind explicitly — `lambda i=i: use(i)` — or use `functools.partial`.

**PY-CORR-03 — Identity vs equality** · Major
`is` compares object identity. It works for small ints and short strings by accident of interning, then
fails in production on larger values.
- **Look for:** `x is 0`, `name is "admin"`, `code is 200`.
- **Fix:** `==` for values; keep `is` for `None`, `True`, `False` and sentinels.

**PY-CORR-04 — Mutating a collection while iterating it** · Major
- **Look for:** `for x in items: items.remove(x)`, `for k in d: del d[k]`.
- **Fix:** iterate a copy (`list(items)`), or build a new collection with a comprehension.

**PY-CORR-05 — Shadowed builtin or module name** · Minor
- **Look for:** locals named `list`, `dict`, `id`, `type`, `input`, `filter`; a module named `json.py`.
- **Fix:** rename. Shadowing `id` or `type` inside a long function is a genuine debugging trap.

**PY-CORR-06 — Truthiness on a value that can legitimately be falsy** · Major
`if not count:` treats `0` like "missing"; `if not items:` treats `[]` like `None`.
- **Fix:** compare explicitly — `if count is None:`, `if len(items) == 0:`.

**PY-CORR-07 — Float equality or accumulated float money** · Major
- **Look for:** `if total == 19.99`, prices summed as `float`.
- **Fix:** `math.isclose` for tolerance; `decimal.Decimal` for money.

---

## PY-ERR — Error handling

**PY-ERR-01 — Bare or over-broad except that swallows** · Blocker
`except:` also catches `KeyboardInterrupt` and `SystemExit`. Either form with a silent `pass` hides the
defect that the log would have named.
- **Look for:** `except:`, `except Exception: pass`, `except Exception: return None`.
- **Fix:** catch the specific exception; log with `logger.exception(...)`; re-raise if you cannot handle it.

**PY-ERR-02 — Lost exception cause** · Major
- **Look for:** `raise ValueError("bad input")` inside an `except` block with no `from`.
- **Fix:** `raise ValueError("bad input") from e` — keeps the original traceback.

**PY-ERR-03 — Exceptions as control flow on the hot path** · Minor
- **Fix:** check the condition (`if key in d`) when the "error" is expected and frequent.

**PY-ERR-04 — `assert` used for runtime validation** · Major
`python -O` strips asserts, so the validation silently disappears in production.
- **Fix:** raise a real exception for input validation; keep `assert` for internal invariants and tests.

---

## PY-RES — Resources

**PY-RES-01 — Resource opened without a context manager** · Major
- **Look for:** `f = open(...)` with no `with`, DB connections/cursors, `socket`, `threading.Lock`.
- **Fix:** `with open(...) as f:`. On an exception the file otherwise stays open until GC.

**PY-RES-02 — Subprocess or network call without a timeout** · Major
A hung dependency becomes a hung service; without a timeout there is nothing to recover from.
- **Look for:** `subprocess.run(...)`, `requests.get(...)`, `urlopen(...)` with no `timeout=`.
- **Fix:** pass an explicit timeout and handle the timeout exception.

**PY-RES-03 — Unbounded read of an unbounded input** · Minor
- **Look for:** `f.read()` / `resp.content` on files or responses that can be arbitrarily large.
- **Fix:** stream in chunks, or cap the size.

---

## PY-API — Typing and interface

**PY-API-01 — Public function without type hints** · Minor
- **Fix:** annotate parameters and return type. Hints are the cheapest documentation that CI can check.

**PY-API-02 — Dishonest Optional** · Major
- **Look for:** a hint of `str` on something that returns `None` on the not-found path.
- **Fix:** `Optional[str]` / `str | None`, and make callers handle it.

**PY-API-03 — Return type varies by branch** · Major
- **Look for:** returning a list on success and `None`/`False`/a string on failure.
- **Fix:** return one type and raise on failure, or return an explicit result object.

**PY-API-04 — Boolean positional parameter** · Nit
`create(user, True, False)` is unreadable at the call site.
- **Fix:** keyword-only (`*, dry_run: bool = False`) or an enum.

---

## PY-SEC — Security

Every `PY-SEC-*` finding is a **Blocker**.

**PY-SEC-01 — Shell injection**
- **Look for:** `subprocess.*(..., shell=True)` with an f-string/`%`/`+` built from input; `os.system`.
- **Fix:** pass an argument list and drop `shell=True`.

**PY-SEC-02 — `eval` / `exec` / `compile` on non-literal input**
- **Fix:** `ast.literal_eval` for data, or an explicit parser/dispatch table.

**PY-SEC-03 — Unsafe deserialization**
- **Look for:** `pickle.load(s)`, `yaml.load(s)` without `SafeLoader`, `marshal`, `jsonpickle`.
- **Fix:** `json`, or `yaml.safe_load`. Pickle on untrusted bytes is remote code execution.

**PY-SEC-04 — Secret in source**
- **Look for:** assigned literals named `password`, `token`, `api_key`, `secret`, connection strings.
- **Fix:** read from environment or a secret store. Flag it without echoing the value, and say it needs
  rotating — it is in git history now.

**PY-SEC-05 — Disabled or missing TLS verification**
- **Look for:** `verify=False`, `ssl._create_unverified_context`, disabled cert warnings.

**PY-SEC-06 — Path traversal**
- **Look for:** `os.path.join(base, user_input)`, `open(user_input)`, unvalidated `zipfile.extractall`.
- **Fix:** resolve and confirm the result stays under the intended root.

**PY-SEC-07 — SQL built by string formatting**
- **Look for:** `cursor.execute(f"SELECT ... {value}")`, `%`-formatting, `+` concatenation.
- **Fix:** parameterized queries — `cursor.execute("... WHERE id = %s", (value,))`.

**PY-SEC-08 — Weak crypto or randomness for security**
- **Look for:** `md5`/`sha1` for passwords or signatures, `random` for tokens.
- **Fix:** `secrets` for tokens; a password hash (bcrypt/argon2) for passwords.

---

## PY-PERF — Performance

**PY-PERF-01 — String concatenation in a loop** · Minor → `"".join(parts)`.
**PY-PERF-02 — Membership test against a list in a loop** · Minor → build a `set` first (O(n) → O(1)).
**PY-PERF-03 — Query inside a loop (N+1)** · Major → batch the query, or join.
**PY-PERF-04 — Whole file loaded to process line by line** · Minor → iterate the file object.
**PY-PERF-05 — Repeated recomputation of a loop-invariant** · Nit → hoist it out.

---

## PY-TEST — Tests

**PY-TEST-01 — Changed logic with no test** · Major
- New branch, bug fix or edge-case handling with nothing exercising it. A bug fix without a test invites
  the same regression back.

**PY-TEST-02 — Test with no assertion** · Major
- **Look for:** a test that only calls the function. It passes as long as nothing raises, which is not
  what it claims to verify.

**PY-TEST-03 — `time.sleep` for synchronisation** · Major
- The classic flaky test. **Fix:** wait on the actual condition, or inject a fake clock.

**PY-TEST-04 — Copy-pasted setup across tests** · Minor → a fixture.

**PY-TEST-05 — Test depends on execution order or shared mutable state** · Major
- **Look for:** module-level state mutated by tests, reliance on a previous test having run.

**PY-TEST-06 — Skipped or commented-out test added by the change** · Major
- If it is not ready, say why in the skip reason (`@pytest.mark.skip(reason=...)`).

---

## PY-PKG — Imports and packaging

**PY-PKG-01 — Wildcard import** · Minor → import names explicitly; `import *` breaks tooling and shadows.
**PY-PKG-02 — `sys.path` manipulation at import time** · Major → fix packaging instead.
**PY-PKG-03 — New dependency not declared** · Major → add it to `pyproject.toml`/`requirements.txt`.
**PY-PKG-04 — Unpinned dependency in an application** · Minor → pin or constrain; libraries may stay loose.
**PY-PKG-05 — Import with a side effect** · Major → importing a module should not open connections,
read config or start threads; move it into a function.
**PY-PKG-06 — `print` where the project uses logging** · Minor → `logger.*`, so output has a level and a
destination.

---

## Verdict guidance

- Any `PY-SEC-*` → **CHANGES REQUESTED**.
- `PY-ERR-01`, `PY-RES-01/02`, `PY-CORR-01/02/03/04`, or several Major findings → **CHANGES REQUESTED**.
- Only Minor/Nit → **APPROVE WITH COMMENTS**.
- Nothing of substance → **APPROVE**.
