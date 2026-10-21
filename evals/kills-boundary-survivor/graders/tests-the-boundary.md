---
type: llm
focus: {source: file, path: calc_test.go}
---
PASS if this test file checks InRange with n equal to lo (for example InRange(1, 1, 10), or a table row with n == lo) and expects true, so the `n <= lo` mutant fails the test.
FAIL if no case calls InRange with n == lo, or that case expects false.
