# gooze for Claude Code

A Claude Code plugin for [gooze](https://github.com/gooze-dev/gooze), the Go
mutation testing tool.

- **`/gooze:mutation-testing` skill.** Teaches Claude the gooze loop: scope and
  run `gooze run`, read the mutation score and surviving mutants, write tests that
  kill them, and rerun to confirm the score went up. It knows when a mutant can't
  be killed and how to use `//gooze:ignore` narrowly. Claude also loads it on its
  own when you ask about mutation testing.
- **Post-edit hook.** After Claude edits a Go file or `gooze.yaml`, it gets that
  file's gooze diagnostics straight away: the mutation score, each surviving
  mutant with the change your tests missed, mistyped `//gooze:ignore` mutagens and
  `gooze.yaml` errors. This needs [goozels](https://github.com/gooze-dev/goozels);
  without it the hook does nothing.

It works alongside the official `gopls-lsp` plugin; keep that on for Go code
intelligence.

## Install

In Claude Code:

```text
/plugin marketplace add gooze-dev/claude-plugin
/plugin install gooze@gooze
```

Then install the tools the plugin uses (they must be on the `PATH` of the shell
you start `claude` from):

```bash
go install gooze.dev/pkg/gooze@latest                # required
go install gooze.dev/pkg/goozels/cmd/goozels@latest  # optional, for the post-edit hook
```

To get new versions automatically, open `/plugin`, go to **Marketplaces**, select
`gooze` and choose **Enable auto-update**. Otherwise run
`/plugin marketplace update gooze`.

## Use it

Ask in plain words, for example:

- *"Run gooze on `./internal/domain/...` and kill the surviving mutants in
  `ignore.go` without changing production code."*
- *"Which files in this package have the lowest mutation score?"*
- *"Are any of the surviving mutants in `parser.go` equivalent? Suppress only
  those."*

Or invoke the skill directly with `/gooze:mutation-testing`.

To skip permission prompts for gooze outside the skill, allow it in
`.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Bash(gooze run *)", "Bash(gooze report view)", "Bash(goozels check *)"]
  }
}
```

## Develop

```bash
claude --plugin-dir .          # load this checkout for one session
claude plugin validate .       # check the manifest and marketplace
```

Bump `version` in `.claude-plugin/plugin.json` on every release; users only
receive changes when it changes.

## License

[MIT](LICENSE)
