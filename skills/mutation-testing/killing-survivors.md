# Killing surviving mutants

How to turn a survivor from `gooze report view` or `goozels check` into a test
that kills it, or a written reason why no test can.

## Contents

- Follow the project's conventions first
- Decide each survivor: gap or equivalent
- What kills each mutant
- Choosing the cases
- Assertions that let mutants survive
- Confirming the kill
- When the code resists

## Follow the project's conventions first

Before writing a test, read how this project tests: a testing section in
`CLAUDE.md` or `AGENTS.md`, a `TESTING*.md` or `CONTRIBUTING.md`, and the
existing `_test.go` files next to the code. Match them: the assertion
library (testify or the standard library), table tests or `t.Run` subtests,
the mock generator (mockery, gomock) or hand-written fakes, file and test
naming. A project's written rules win over the defaults below. Don't convert
existing tests to another style while killing a mutant.

## Decide each survivor: gap or equivalent

For every survivor, ask one question first: **can any input make the mutated
code behave differently?**

- **Gap**: yes. Write the test that makes that difference observable.
- **Equivalent**: no input can, e.g. `i < n` → `i != n` in a loop that only
  steps by one. Say why in one sentence, then ignore it narrowly (see
  `//gooze:ignore` in SKILL.md). Don't write a test that can't exist.

Never leave a survivor unlabelled. When working through several, keep one line
each so the user can review the verdicts:

```
calc.go:5  comparison  if n < lo -> if n <= lo   gap: no test at n == lo  -> TestInRange/accepts_the_lower_bound
calc.go:9  comparison  i < n -> i != n           equivalent: i only steps by one from 0
```

## What kills each mutant

| gooze mutagen | Report shows, e.g. | The test must |
|---|---|---|
| `comparison` | `if n < lo {` → `if n <= lo {` | hit the boundary **exactly** (`n == lo`); for `==` ↔ `!=`, one equal and one unequal case |
| `arithmetic` | `a + b` → `a - b` | assert the exact result with operands that tell the operators apart (not `0`, and `b` ≠ `0` for `*`/`/`) |
| `numbers` | `return 5` → `return 0` / `1` | assert the exact value, not "non-zero" or "positive" |
| `boolean` | `true` → `false` | take the path the literal controls and assert its effect |
| `logical` | `a && b` → `a \|\| b` | include a case where exactly one operand is true |
| `unary` | `!ok` → `ok`, `-x` → `x` | cover both sides of the condition, or a non-zero value whose sign matters |
| `bitwise` | `flags & mask` → `flags \| mask` | use operands whose bits differ, so the two operators give different results (not `0`, not equal values) |
| `increment` | `n++` → `n--` | assert the counter's value after the step, not only that it changed |
| `assignment` | `total += x` → `total -= x` or `total = x` | assert the accumulated value over at least two steps, with a non-zero start |
| `branch` | `if err != nil {` → `if false {`, block removed | take both sides of the condition and assert each side's effect |
| `statement` | `cache[k] = v` (line removed) | assert the effect of that statement (the value stored, the call made, the message sent) |
| `loop` | `i < n` → `i <= n`, body or `break` removed | assert the result at the loop's bounds: zero, one and several iterations, and the early exit |

Mutations that need a `not_covered` fix first: no test runs the line, so add
a test that executes it at all, then check the assertions above.

## Choosing the cases

Pick the cases the code actually distinguishes, one per class it treats alike:

- **Zero, one, many** for anything countable: nil or empty, a single element,
  several. Assert the last element, not only the length.
- **Every boundary from both sides**: for a comparison against `N`, test
  `N-1`, `N` and `N+1`. Only "somewhere below" and "somewhere above" leaves
  the edge, where `comparison` survivors live, untested.
- **The zero value** of the input type: an unset field, a missing map key, a
  zero `time.Time`. It's almost always a legal input the code never intended.
- **The failure path**: an `if err != nil` branch needs a test where the
  error happens, or deleting its body survives.
- By type, ask about: `""` and whitespace for strings; negative numbers;
  nil versus empty for slices and maps; a key present with the zero value
  versus absent; a nil pointer inside an interface; an already-cancelled
  `context`.

This is a prompt to ask, not a quota: a function that never branches on
negative numbers needs no negative case.

## Assertions that let mutants survive

| The test asserts | What survives | Assert instead |
|---|---|---|
| only `NoError` | a mutated return value | the returned value itself |
| `NotNil` on a slice | an empty result | its length and elements |
| "greater than zero" | a changed constant | the exact number |
| that a call happened | a changed argument | the arguments, or the state it produced |
| the error's message text | nothing, but it breaks on rewording | `errors.Is` / `errors.As` |

With testify: `require` for anything later lines depend on, `assert` for
independent facts, arguments in `(t, want, got)` order, and `NoError`, never
`Nil`, for errors (they disagree on a typed nil pointer stored in an `error`).

## Confirming the kill

A new test must first pass on the real code (`go test -run 'TestName' ./pkg`),
then kill the mutant. Don't edit production code to watch it fail: gooze
applies each mutant to a temporary copy. Re-run gooze on just that function
(`gooze run --run '^Func$' ./pkg`, if `gooze run --help` lists `--run`, else
the package) and check the survivor is gone. If it still survives, the test
doesn't observe the change: revisit the tables above.

## When the code resists

If killing a mutant needs more than three fakes, a real clock or network, or a
function with cyclomatic complexity over 10, the code is hard to test, not the
test hard to write. Say so and suggest the change (inject the clock or client,
split the decision from the I/O, split the function), but don't refactor
production code unasked. Leave the survivor labelled until then.

A mutation score is never 100% because of equivalent mutants, so don't make it
a target: label every survivor instead.
