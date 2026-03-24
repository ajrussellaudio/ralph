---
title: TOML array parser + tests
priority: normal
blocked_by: []
status: pending
branch: ""
review_notes: ""
fix_count: 0
---

## Parent PRD

`plans/pre-commit-checks.md`

## What to build

Add a `toml_get_array()` function to `lib/functions.sh` that parses TOML array values from the config file and returns one item per line to stdout. The function must handle both multi-line and single-line TOML array syntax. Add a comprehensive bats test suite to verify the parser against a range of inputs.

### `toml_get_array()` specification

- **Signature:** `toml_get_array <key>` (reads from the global `$CONFIG_FILE` variable, same as `toml_get`)
- **Input:** A TOML key name (e.g. `pre_commit`)
- **Output:** One array item per line on stdout, with surrounding quotes stripped
- **Exit code:** 0 always (empty output for missing keys or empty arrays, matching `toml_get` convention)

**Formats to support:**

Multi-line:
```toml
pre_commit = [
  "eslint .",
  "prettier --check .",
]
```

Single-line:
```toml
pre_commit = ["eslint .", "prettier --check ."]
```

Empty:
```toml
pre_commit = []
```

**Edge cases:**
- Trailing commas are allowed
- Whitespace around `=`, `[`, `]`, and between items is flexible
- Items may contain spaces (e.g. `"eslint --fix ."`)
- Missing key → empty output (no error)

### Test suite

Create `test/toml_parser.bats` following the conventions in `test/routing.bats` and `test/yaml_helpers.bats`:
- `load 'test_helper'` to source `lib/functions.sh`
- Use `setup()` to create a temp directory and write TOML fixture files
- Use `teardown()` to clean up

**Test cases to cover:**
1. Multi-line array with multiple items → returns each item on a separate line
2. Single-line array (`key = ["a", "b"]`) → returns each item
3. Empty array (`key = []`) → empty output
4. Missing key (key not in file) → empty output
5. Array with trailing comma → still parses correctly
6. Array with varied whitespace → still parses correctly
7. Items containing spaces (e.g. `"eslint --fix ."`) → preserves full command
8. Single-item array → returns that one item

### Important constraints

- The existing `toml_get()` function (in `ralph.sh` lines 47-51) must NOT be modified or broken. It continues to handle scalar values.
- `toml_get_array()` lives in `lib/functions.sh` so it is automatically available to tests via `test_helper.bash` (which sources `lib/functions.sh`).
- The function needs the `$CONFIG_FILE` global to be set (same pattern as `toml_get`).

## Acceptance criteria

- [ ] `toml_get_array` function exists in `lib/functions.sh` and parses multi-line TOML arrays
- [ ] `toml_get_array` function handles single-line TOML arrays
- [ ] `toml_get_array` returns empty output for missing keys and empty arrays
- [ ] `test/toml_parser.bats` exists with tests covering all 8 cases listed above
- [ ] All tests pass (`bats test/toml_parser.bats`)
- [ ] Existing tests still pass (`bats test/`)

## User stories addressed

- User story 1 (define a list of pre-commit checks in ralph.toml)
- User story 12 (multi-line TOML array syntax)
- User story 14 (empty or missing means no checks)
