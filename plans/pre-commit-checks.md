---
label: pre-commit-checks
---

## Problem Statement

Ralph currently supports a `build` command and a `test` command in `ralph.toml`, which the agent runs before committing implementation code. However, many projects rely on additional lightweight checks — linters, formatters, type-checkers — that should pass before any code is committed. Today there is no way to configure these in ralph.toml, so the agent has no awareness of them and may commit code that violates project standards.

## Solution

Add an optional `pre_commit` configuration key to `ralph.toml` that accepts an ordered array of commands. Before making any code commit (feat/fix/refactor), the agent runs these checks in order, **before** the existing build+test verification step. If a check fails, the agent attempts to auto-fix and restarts the entire sequence from the beginning (up to 2 retries per check). If it cannot fix within the retry budget, it reverts and stops.

The TOML parser is upgraded to support multi-line array syntax, and prompt templates are updated so the agent receives pre-commit instructions as a formatted list.

## User Stories

1. As a project maintainer, I want to define a list of pre-commit checks in ralph.toml, so that ralph enforces my project's code quality standards before committing.
2. As a project maintainer, I want the pre-commit checks to be optional, so that projects without linters or formatters are unaffected.
3. As a project maintainer, I want the checks to run in a defined order, so that faster checks (e.g. linting) run before slower ones (e.g. type-checking).
4. As a project maintainer, I want the pre-commit checks to run before build+test, so that cheap validation happens first and expensive steps are not wasted on code that would fail linting.
5. As a project maintainer, I want the agent to fail fast on the first failing check, so that it focuses on one problem at a time rather than accumulating errors.
6. As a project maintainer, I want the agent to attempt auto-fixing a failing check (e.g. running a formatter, fixing a lint error), so that trivial issues don't block progress.
7. As a project maintainer, I want the agent to restart all pre-commit checks from the beginning after a fix, so that a fix for one check doesn't break an earlier check.
8. As a project maintainer, I want a retry cap of 2 attempts per check, so that the agent doesn't loop forever on an unfixable issue.
9. As a project maintainer, I want the agent to revert and STOP if it cannot fix a pre-commit failure within the retry budget, so that broken code is never committed.
10. As a project maintainer, I want pre-commit checks to only gate code commits (feat/fix/refactor), not bookkeeping chore commits, so that task-status updates are never blocked by linter failures.
11. As a project maintainer, I want the pre-commit step to appear in `implement` and `fix` modes only, since those are the modes that produce code commits.
12. As a project maintainer, I want to use standard multi-line TOML array syntax for the config, so that long check lists are readable.
13. As a project maintainer, I want `project.example.toml` to include a commented example of `pre_commit`, so that new users discover the feature.
14. As a project maintainer, I want an empty or missing `pre_commit` to mean "no checks", so that the feature is fully backward-compatible.
15. As a project maintainer, I want the agent's prompt to show me the checks as a clear numbered list, so that the agent understands the execution order.

## Implementation Decisions

### TOML Parser Upgrade

- The current `toml_get()` function is a single-line `grep | sed` that can only parse scalar values. It will be upgraded or supplemented with a `toml_get_array()` function that handles multi-line TOML arrays.
- `toml_get_array()` extracts text between `key = [` and the closing `]`, then parses individual quoted string items. It returns one item per line to stdout.
- The existing `toml_get()` continues to work unchanged for scalar keys (`build`, `test`, `repo`). No breaking changes.
- Single-line arrays (e.g. `pre_commit = ["eslint ."]`) should also be supported for simple cases.

### Config Reading & Formatting

- `ralph.sh` reads the `pre_commit` array using `toml_get_array`.
- If the array is empty or the key is missing, `PRE_COMMIT_CHECKS` is set to an empty string.
- If items are present, they are formatted as a numbered markdown list:
  ```
  1. `eslint .`
  2. `prettier --check .`
  3. `tsc --noEmit`
  ```
- This formatted string is stored in a `PRE_COMMIT_CHECKS` shell variable for prompt substitution.

### Prompt Substitution

- `build_prompt()` in `lib/functions.sh` adds a `{{PRE_COMMIT_CHECKS}}` substitution alongside the existing `{{BUILD_CMD}}` and `{{TEST_CMD}}` substitutions.

### Mode Template Updates

- `modes/implement.md`: A new step is inserted **before** the existing Verify step (currently Step 5). The step is conditional — if `{{PRE_COMMIT_CHECKS}}` is empty, the agent skips it.
- `modes/fix.md`: Same treatment — a pre-commit check step is inserted before the test-running step.
- The prompt instructions specify:
  - Run checks in the numbered order, fail-fast on first failure.
  - On failure: attempt to fix the issue, then restart ALL checks from check 1.
  - Track retry count per check. After 2 failed fix attempts for the same check, revert and emit `STOP`.
  - Only gate code commits (feat/fix/refactor), not chore commits.
- No changes to `review.md`, `merge.md`, `force-approve.md`, or `review-round2.md`.

### Config Templates

- `ralph.toml` and `project.example.toml` get a commented-out `pre_commit` example showing multi-line array syntax.

## Testing Decisions

- **What makes a good test here:** Tests should verify external behavior (given TOML input text, what array items are returned?) rather than implementation details of the parsing approach.
- **Module under test:** The `toml_get_array()` function in `lib/functions.sh`.
- **Test cases to cover:**
  - Multi-line array with multiple items
  - Single-line array (`key = ["a", "b"]`)
  - Empty array (`key = []`)
  - Missing key (no match in file)
  - Array with trailing comma
  - Array with whitespace variations
  - Items containing spaces (e.g. `"eslint --fix ."`)
  - Single-item array
- **Prior art:** `test/routing.bats` and `test/yaml_helpers.bats` use the bats testing framework with `test_helper.bash`. New tests follow the same pattern — a new `test/toml_parser.bats` file.

## Out of Scope

- Replacing or deprecating the existing `build` and `test` scalar keys. They remain as-is.
- Running pre-commit checks on bookkeeping (chore) commits.
- Running pre-commit checks in review, merge, or force-approve modes.
- Parallel execution of pre-commit checks.
- Git hook integration (`.git/hooks/pre-commit`). This is prompt-level, not git-level.
- A "run all, report all" failure mode. Fail-fast is the chosen behavior.
- Support for non-string TOML array items (numbers, booleans, nested tables).

## Further Notes

- The retry-cap of 2 is per-check, not per-sequence. If check 1 passes, check 2 fails and is fixed, then on restart check 1 passes again and check 2 fails again, that counts as 2 attempts for check 2.
- The restart-from-beginning behavior means the total number of command executions could be higher than the number of checks × retries, but this is acceptable given these are fast, cheap checks.
- Backward compatibility is preserved: existing ralph.toml files without `pre_commit` continue to work identically.
