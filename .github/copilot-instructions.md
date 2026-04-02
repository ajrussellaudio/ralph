# Copilot Instructions — Ralph

## Testing

```bash
bats test/*.bats                                # all tests
bats test/routing.bats                          # single file
bats test/routing.bats --filter "no open PRs"   # single test by name
```

Tests mock `gh` via `test/helpers/mock_gh`; inject responses through `MOCK_*` env vars. Test hooks: `RALPH_TESTING=1` disables git worktree sync in routing; `RALPH_PARSE_ONLY=1` exits after arg parsing.

## Architecture

Ralph is a bash agent loop that works through GitHub issues via the Copilot CLI. Each iteration: `determine_mode()` → load `modes/<mode>.md` → substitute `{{PLACEHOLDERS}}` → run Copilot → parse `<promise>STOP</promise>` / `<promise>COMPLETE</promise>` signals.

Mode routing (`lib/routing.sh`) has two paths based on whether the Copilot review bot is installed on the repo:

- **Copilot bot path**: checks bot review state → `fix-bot`, `wait`, `escalate`, or `merge`
- **HTML comments path**: checks `<!-- RALPH-REVIEW: ... -->` sentinel comments → `review`, `fix`, or `merge`

See `docs/routing.md` for Mermaid flowcharts of the full decision tree.

## Conventions

### gh CLI — critical pitfalls

- **Always** use `gh_with_retry()` — never bare `gh`
- **Always** append `< /dev/null` to every `gh` call to prevent stdin hangs
- Never use `gh pr comment --body "..."` — write to a temp file and use `--body-file`

### State tracking

Ralph has no database. PR state across iterations is tracked via HTML comment sentinels (e.g., `<!-- RALPH-REVIEW: APPROVED -->`, `<!-- RALPH-FIX: RESPONSE -->`). The routing logic in `lib/routing.sh` parses these to determine the next mode.

### Mode prompts

Each `modes/*.md` file is a self-contained Copilot prompt. `build_prompt()` in `ralph.sh` substitutes `{{PLACEHOLDERS}}` (like `{{REPO}}`, `{{PR_NUMBER}}`, `{{TEST_CMD}}`). Every mode **must** end by emitting `<promise>STOP</promise>`. Per-project overrides go in `<project-root>/ralph/modes/`.

## Common changes — files to touch

| Task | Files |
|---|---|
| New mode | `modes/<mode>.md` + `determine_mode()` in `lib/routing.sh` + `test/routing.bats` |
| New placeholder | `build_prompt()` in `ralph.sh` + any `modes/*.md` that use it |
| New subcommand | Dispatch block in `ralph.sh` + `lib/<cmd>.sh` + `test/<cmd>.bats` |
| New `gh` API call | Add mock branch in `test/helpers/mock_gh` for testability |
