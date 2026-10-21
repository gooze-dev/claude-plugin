#!/bin/sh
# A Go module whose test misses the lower bound of InRange.
set -e
cat >go.mod <<'GO'
module example.com/calc

go 1.22
GO
cat >calc.go <<'GO'
package calc

// InRange reports whether n is within [lo, hi].
func InRange(n, lo, hi int) bool {
	if n < lo {
		return false
	}

	if n > hi {
		return false
	}

	return true
}
GO
cat >calc_test.go <<'GO'
package calc

import "testing"

func TestInRange(t *testing.T) {
	if !InRange(5, 1, 10) {
		t.Fatal("5 is in [1, 10]")
	}

	if InRange(0, 1, 10) {
		t.Fatal("0 is below [1, 10]")
	}
}
GO
