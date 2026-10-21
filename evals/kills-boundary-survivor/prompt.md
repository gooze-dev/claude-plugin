---
runs: 3
max_turns: 15
allowed_tools: [Read, Glob, Grep, Edit, Write, Skill]
tags: [behavior]
---
gooze reported this surviving mutant. Kill it with a test.

calc.go:5:2: warning: gooze: surviving comparison mutant — tests still pass with `if n < lo {` → `if n <= lo {`
