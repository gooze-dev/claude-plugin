---
type: llm
---
PASS if the answer says the mutant is equivalent (i starts at 0 and only steps by one, so `<` and `!=` stop at the same point and no input behaves differently), and suggests a narrow `//gooze:ignore comparison` on that line with a written reason.
FAIL if it proposes writing a test to kill it, or suggests ignoring all mutagens or the whole file.
