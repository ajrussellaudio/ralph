---
title: Config wiring + prompt substitution + config templates
priority: normal
blocked_by: [1]
status: pending
branch: ""
review_notes: ""
fix_count: 0
---

## Parent PRD

`plans/pre-commit-checks.md`

## What to build

Wire the `toml_get_array()` function (from task 01) into ralph's startup flow: read the `pre_commit` config, format it as a numbered markdown list, and substitute it into prompt templates via a new `{{PRE_COMMIT_CHECKS}}` placeholder. Update both config templates so users can discover the feature.

### Config reading in `ralph.sh`

After the existing lines that read `BUILD_CMD`, `TEST_CMD`, and `REPO` (ralph.sh ~lines 53-55), add logic to:

1. Call `toml_get_array pre_commit` to get the list of commands
2. If the list is empty, set `PRE_COMMIT_CHECKS=""` (empty string)
3. If items are present, format them as a numbered markdown list:
   ```
   1. `eslint .`
   2. `prettier --check .`
   3. `tsc --noEmit`
   ```
4. Store the result in a `PRE_COMMIT_CHECKS` shell variable

Note: `toml_get_array` is defined in `lib/functions.sh`, which is sourced by `ralph.sh` before the config-reading section. Verify this source order is correct; if `lib/functions.sh` is sourced after the config section, the source line may need to move up.

### Prompt substitution in `build_prompt()`

In `lib/functions.sh`, function `build_prompt()` (~lines 326-359), add a new substitution line alongside the existing ones:

```bash
PROMPT="${PROMPT//\{\{PRE_COMMIT_CHECKS\}\}/$PRE_COMMIT_CHECKS}"
```

Place it near the `{{BUILD_CMD}}` and `{{TEST_CMD}}` substitutions for readability.

### Config template updates

**`project.example.toml`** — add a commented-out `pre_commit` example after the `test` line:

```toml
# Pre-commit checks — optional list of commands to run before each code commit.
# pre_commit = [
#   "eslint .",
#   "prettier --check .",
# ]
```

**`ralph.toml`** — add the same commented-out example (ralph's own project doesn't need pre-commit checks, but the example shows the syntax).

## Acceptance criteria

- [ ] `ralph.sh` reads `pre_commit` from ralph.toml using `toml_get_array`
- [ ] `PRE_COMMIT_CHECKS` is an empty string when `pre_commit` is missing or empty
- [ ] `PRE_COMMIT_CHECKS` is a numbered markdown list when items are present
- [ ] `build_prompt()` substitutes `{{PRE_COMMIT_CHECKS}}` into the prompt
- [ ] `project.example.toml` contains a commented-out `pre_commit` example
- [ ] `ralph.toml` contains a commented-out `pre_commit` example
- [ ] Existing tests still pass (`bats test/`)
- [ ] ralph.sh does not error when `pre_commit` is absent from ralph.toml (backward compat)

## User stories addressed

- User story 2 (optional — projects without checks are unaffected)
- User story 3 (checks run in defined order — numbered list preserves order)
- User story 13 (project.example.toml includes commented example)
- User story 14 (empty or missing means no checks)
- User story 15 (agent sees checks as a clear numbered list)
