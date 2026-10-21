---
runs: 3
max_turns: 6
allowed_tools: [Read, Glob, Grep, Skill]
tags: [behavior]
---
gooze keeps reporting this survivor in our Go code and I can't find a test that kills it. What should I do?

sum.go:6:2: warning: gooze: surviving comparison mutant — tests still pass with `for i := 0; i < len(xs); i++ {` → `for i := 0; i != len(xs); i++ {`
