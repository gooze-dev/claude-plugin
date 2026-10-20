<!-- gooze:begin guide=1 gooze=v1.2.0 -->
## Mutation testing (gooze)

This Go project uses [gooze](https://gooze.dev) for mutation testing. Reports live in `.gooze-reports/`.

- Scope runs to the packages you changed: `gooze run ./internal/foo/...` (`--estimate` previews the cost). Runs are incremental: unchanged files are skipped.
- `gooze report view` shows the score; `goozels check <file.go>` lists one file's surviving mutants with the exact change.
- Kill a surviving mutant by adding or tightening a test whose assertion fails under that mutation. Don't change production code to kill it.
- Rerun `gooze run` on the same packages to confirm the score went up.
- Use `//gooze:ignore <mutagen>` (e.g. `comparison`) only for an equivalent mutant, one no test can detect, and say why in the comment.
- Settings are in `./gooze.yaml` (an unparsable file is ignored entirely); check it with `goozels check gooze.yaml`.

**Code review rule:** when reviewing Go changes (including `/code-review`), run `gooze run <changed packages>` or read the existing `.gooze-reports`, and report surviving mutants in changed code as test-gap findings with `file:line`. Use `goozels check <file>` for per-file detail.
<!-- gooze:end -->
