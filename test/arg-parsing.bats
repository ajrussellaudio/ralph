#!/usr/bin/env bats
# Tests for ralph.sh argument parsing.
#
# Uses RALPH_PARSE_ONLY=1 to exit after parsing without running preflight
# checks or the main loop, so tests are fast and self-contained.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RALPH="$REPO_ROOT/ralph.sh"

# ─── No --max-iterations flag ─────────────────────────────────────────────────

@test "no args: parses successfully with unlimited iterations" {
  run env RALPH_PARSE_ONLY=1 "$RALPH"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MAX_ITERATIONS="
  # MAX_ITERATIONS should be empty (unlimited)
  echo "$output" | grep -q "^MAX_ITERATIONS=$"
}

@test "--label only: parses successfully, FEATURE_BRANCH derived" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --label=foo-widget
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "FEATURE_BRANCH=feat/foo-widget"
}

# ─── --max-iterations flag ────────────────────────────────────────────────────

@test "--max-iterations=10: parses successfully, MAX_ITERATIONS set" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --max-iterations=10
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MAX_ITERATIONS=10"
}

@test "--max-iterations=1: minimum valid value accepted" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --max-iterations=1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "MAX_ITERATIONS=1"
}

# ─── --max-iterations invalid values ─────────────────────────────────────────

@test "--max-iterations=0: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --max-iterations=0
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}

@test "--max-iterations=foo: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --max-iterations=foo
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}

@test "--max-iterations without value: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --max-iterations
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}

# ─── Old positional interface ─────────────────────────────────────────────────

@test "positional integer (old interface): exits with migration error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" 40
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "positional"
  echo "$output" | grep -q "\-\-max-iterations"
}

# ─── Unknown flags ────────────────────────────────────────────────────────────

@test "unknown flag: exits with usage error" {
  run env RALPH_PARSE_ONLY=1 "$RALPH" --unknown-flag
  [ "$status" -eq 1 ]
  echo "$output" | grep -qi "usage\|--max-iterations"
}
