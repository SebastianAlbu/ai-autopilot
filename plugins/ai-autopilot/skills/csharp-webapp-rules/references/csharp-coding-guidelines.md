# C# Coding Guidelines & Best Practices v1.0

Encoded from *C# Coding Guidelines And Best Practices v1.0* (c-sharpcorner). These complement the
security/reliability rules in [csharp-webapp-rules.md](./csharp-webapp-rules.md). Cite the rule ID in
findings (e.g. `CS-NAME-05`). Severities: **Major**, **Minor**, **Nit** (style). Apply to changed lines.

## 1. Naming Conventions

| ID | Rule | Good | Wrong |
|----|------|------|-------|
| CS-NAME-01 | **Class** → PascalCase | `public class HelloWorld {}` | `public class helloWorld {}` |
| CS-NAME-02 | **Method** → PascalCase | `public void AddNumbers(int first, int second)` | `addNumbers(...)` |
| CS-NAME-03 | **Interface** → `I` prefix + PascalCase | `public interface IEmployee {}` | `Iemployee` / `Employee` |
| CS-NAME-04 | **Local variables** → camelCase, meaningful, no abbreviations | `firstName`, `salary` | `fName`, `sal`, `_firstName` |
| CS-NAME-05 | **Member (private field)** → `_` prefix + camelCase | `private IEmployee _employeeService` | `empService`, `userRole` |
| CS-NAME-06 | **Boolean** → prefix `is`/`has`/`can` | `_isAccepted`, `_isFinished` | `accepted`, `finished` |
| CS-NAME-07 | **Namespace** → `Company.Product.Module` | `Company.Product.BusinessLayer` | `BusinessLayer` |
| CS-NAME-08 | **File name** = class name (`.cs`) | `HelloWorld.cs` | `helloworld.cs` |

> Note: the c-sharpcorner doc calls local-variable naming "Hungarian", but its own *correct* examples use plain
> camelCase **without** a datatype prefix (e.g. `firstName`, `salary`). Follow the examples: camelCase, no
> `str`/`i`/`m_` prefixes. The only mandated prefixes are `_` (private fields), `I` (interfaces), `is/has/can`
> (booleans), and UI control prefixes (below).

### UI Control Prefixes (Web Forms / WinForms)
`lbl` Label · `txt` TextBox · `grd` DataGrid · `btn` Button · `imb` ImageButton · `hyp` Hyperlink ·
`ddl` DropDownList · `lst` ListBox · `dtl` DataList · `rep` Repeater · `chk` Checkbox · `cbl` CheckBoxList ·
`rdo` RadioButton · `rbl` RadioButtonList · `img` Image · `pnl` Panel · `phd` PlaceHolder · `tbl` Table ·
`val` Validators. (CS-NAME-09 — flag UI controls without the correct prefix.)

## 2. Indentation & Comments

- CS-FMT-01 — One statement and one declaration per line.
- CS-FMT-02 — One blank line between methods; blank lines to separate logical groups.
- CS-FMT-03 — Use tabs for indentation (default VS settings).
- CS-FMT-04 — XML doc comments (`///`) on classes, constructors, public methods. Use `//` or `///`;
  **avoid** `/* … */`.
- CS-FMT-05 — Don't comment every line; meaningful names reduce the need for comments. Document only complex logic.
- CS-FMT-06 — Group members with `#region`/`#endregion` in this order: Private members → Private properties →
  Public properties → Constructors → Event handlers/Actions → Private methods → Public methods.

## 3. Good Programming Practices

- CS-PRAC-01 — **Method length**: aim ≤ 40–50 lines; refactor longer methods into private helpers. (Major if very long.)
- CS-PRAC-02 — **Class length**: aim ≤ 600–700 lines; split into `partial` classes / separate files. One class per file.
- CS-PRAC-03 — **Single responsibility**: a method does one job. Split `SaveAddress` into `InsertAddress` / `UpdateAddress`.
- CS-PRAC-04 — **Language aliases**, not CTS types: `int`/`string`/`object`, not `System.Int32`/`String`/`Object`.
- CS-PRAC-05 — **No hardcoded strings/numbers**: use constants files or config (key/value). Cross-reference the
  `appconstants-audit` skill. Use resource files for user-facing strings.
- CS-PRAC-06 — **No hardcoded paths/drives**: get the application path programmatically; use relative paths and `System.IO`.
- CS-PRAC-07 — **String compare case-normalized**: `if (name.ToLower() == "x")`, not `if (name == "X")`.
- CS-PRAC-08 — Use `String.Empty`, not `""`.
- CS-PRAC-09 — Use **enums** for discrete values, not magic numbers/strings (incl. in `switch`).
- CS-PRAC-10 — **Method names meaningful**; no redundant prefixes (in `EmployeeController`, use `Create`, not `CreateEmployee`).
- CS-PRAC-11 — **Null-check** objects (and nested objects) before access.
- CS-PRAC-12 — **User-friendly error messages**; log the real exception via a logger. Keep messages in constants.
- CS-PRAC-13 — **Minimal visibility**: prefer `private`/`internal`; expose `public` only when needed.
- CS-PRAC-14 — **≤ 4–5 parameters**; beyond that pass a class/struct.
- CS-PRAC-15 — **Collections**: return empty (not null); test `Any()` not `Count > 0`; `foreach` over `for`;
  expose `IList<T>`/`IEnumerable<T>`/`ICollection<T>` instead of concrete `List<T>`.
- CS-PRAC-16 — Use **object initializers**.
- CS-PRAC-17 — **`using` ordering**: framework namespaces first, then app namespaces, each ascending.
- CS-PRAC-18 — Close connections/streams/sockets in `finally`, or prefer a `using` statement over try/finally+Dispose.
- CS-PRAC-19 — **Catch specific exceptions**, not `catch (Exception)`.
- CS-PRAC-20 — Use **`StringBuilder`** for string manipulation in loops.
- CS-PRAC-21 — Keep **event handlers thin** — delegate the real work to a named method.
- CS-PRAC-22 — Add whitespace around operators (`a + b`, `x == y`); always brace `if/else/for/foreach/while/do`.
- CS-PRAC-23 — Avoid `var` where it hides the type / where `dynamic` is meant; prefer explicit, readable types.

## 4. Architecture Guidelines

- CS-ARCH-01 — **N-tier**: separate UI, Business, Data Access, Framework, Exception/Logging assemblies.
- CS-ARCH-02 — **No DB access from UI**; go through the data-access layer.
- CS-ARCH-03 — Prefer **stored procedures** over inline SQL; wrap Create/Update/Delete in **transactions**.
- CS-ARCH-04 — Don't name user procs `sp_`/`fn_` (reserved-prefix overhead).
- CS-ARCH-05 — Keep complex logic in the business layer, not in stored procedures.
- CS-ARCH-06 — Apply **SOLID** and design patterns; share code via base classes/utilities (DRY); use generics for reuse.
- CS-ARCH-07 — **Data layer** uses try-catch-finally to record DB exceptions (command/proc/params), then rethrow.
- CS-ARCH-08 — Don't store large/complex objects in Session or ViewState; dispose session vars after use.
- CS-ARCH-09 — Reference third-party JS/CSS/DLLs via NuGet; use minified assets in production.

## Verdict Guidance
- Multiple **Major** naming/practice violations on changed code → CHANGES.
- Mostly **Minor/Nit** style → PASS-WITH-COMMENTS.
- Use judgment: flag what the diff *introduces or worsens*; don't demand churn of untouched legacy code.
