#!/usr/bin/env bats
# Tests for ralph.sh argument parsing.
#
# Uses RALPH_PARSE_ONLY=1 to exit after parsing without running preflight
# checks or the main loop, so tests are fast and self-contained.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RALPH="$REPO_ROOT/ralph.sh"

# ─── Subcommand dispatch ──────────────────────────────────────────────────────

@test "no args: defaults to status subcommand, exits 0" {
  run env RALPH_PARSE_ONLY=1 "$RALPH"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SUBCOMMAND=status"
}

@test "status subcommand: exits 0" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SUBCOMMAND=status"
}

@test "status --label: exits 0, FEATURE_BRANCH derived" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status --label=foo-widget
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FEATURE_BRANCH=feat/foo-widget"
}

@test "status with unknown flag: exits non-zero with usage message" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status --unknown
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "usage"
}

@test "status --ticket=<KEY-N>: exits 0" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status --ticket=CAPP-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SUBCOMMAND=status"
}

@test "status --label and --ticket together: exits non-zero with mutex error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status --label=foo --ticket=CAPP-123
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "mutually exclusive"
}

@test "status --ticket with invalid value: exits non-zero" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status --ticket=not-a-ticket
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "usage\|KEY-NUMBER"
}

@test "status --ticket bare flag (no value): exits non-zero" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status --ticket
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "usage\|KEY-NUMBER"
}

@test "run subcommand: exits 0" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^MAX_ITERATIONS=$"
}

@test "run-style flag without subcommand: exits non-zero with ralph run migration message" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --label=foo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "ralph run"
}

@test "run-style --max-iterations flag without subcommand: exits non-zero with ralph run migration message" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --max-iterations=5
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "ralph run"
}

@test "unknown subcommand: exits non-zero with usage message" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" unknown
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "usage\|subcommand"
}

# ─── run subcommand: --label flag ─────────────────────────────────────────────

@test "run --label only: parses successfully, FEATURE_BRANCH derived" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --label=foo-widget
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FEATURE_BRANCH=feat/foo-widget"
}

# ─── run subcommand: --max-iterations flag ───────────────────────────────────

@test "run --max-iterations=10: parses successfully, MAX_ITERATIONS set" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --max-iterations=10
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MAX_ITERATIONS=10"
}

@test "run --max-iterations=1: minimum valid value accepted" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --max-iterations=1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MAX_ITERATIONS=1"
}

# ─── run subcommand: --max-iterations invalid values ─────────────────────────

@test "run --max-iterations=0: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --max-iterations=0
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}

@test "run --max-iterations=foo: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --max-iterations=foo
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}

@test "run --max-iterations without value: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --max-iterations
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}

# ─── run subcommand: old positional interface ─────────────────────────────────

@test "run with positional integer (old interface): exits with migration error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run 40
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "positional"
  echo "$output" | grep -q "\-\-max-iterations"
}

# ─── run subcommand: unknown flags ────────────────────────────────────────────

@test "run with unknown flag: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --unknown-flag
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}

# ─── run subcommand: --ticket flag (JIRA backend) ────────────────────────────

@test "run --ticket=CAPP-123: parses successfully, exposes JIRA backend vars" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --ticket=CAPP-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "PARENT_TICKET=CAPP-123"
  echo "$output" | grep -q "PROJECT_KEY=CAPP"
  echo "$output" | grep -q "TASK_BACKEND=jira"
}

@test "run --ticket=PROJ-1: minimum-shape ticket accepted" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --ticket=PROJ-1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "PARENT_TICKET=PROJ-1"
  echo "$output" | grep -q "PROJECT_KEY=PROJ"
  echo "$output" | grep -q "TASK_BACKEND=jira"
}

@test "run --ticket=invalid: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --ticket=not-a-ticket
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--ticket"
}

@test "run --ticket without value: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --ticket
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--ticket"
}

@test "run --label only: TASK_BACKEND defaults to github" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --label=foo-widget
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "TASK_BACKEND=github"
}

@test "run with no flags: TASK_BACKEND defaults to github" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "TASK_BACKEND=github"
}

# ─── run subcommand: --ticket mutex ─────────────────────────────────────────

@test "run --ticket + --label: exits non-zero with mutex error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --ticket=CAPP-123 --label=foo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "mutually exclusive\|cannot.*combine\|--ticket.*--label\|mutex"
}

@test "run --ticket + --issue: exits non-zero with mutex error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" run --ticket=CAPP-123 --issue=42
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "mutually exclusive\|cannot.*combine\|--ticket.*--issue\|mutex"
}

# ─── status subcommand: --ticket flag (stub-accept) ──────────────────────────

@test "status --ticket=CAPP-123: parses successfully (stub-accept)" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" status --ticket=CAPP-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SUBCOMMAND=status"
}
