#!/usr/bin/env bats
# Tests for ralph_init() in lib/init.sh.
#
# Uses RALPH_TESTING=1, temp directories for file output, and stdin injection
# via heredocs to simulate user input at each prompt.
#
# Prompt sequence: repo → upstream → build → test → confirmation (5 reads).

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export PATH="$REPO_ROOT/test/helpers:$PATH"

  # Source init function into this shell.
  # shellcheck source=../lib/init.sh
  source "$REPO_ROOT/lib/init.sh"

  export RALPH_TESTING=1
  export SCRIPT_DIR="$REPO_ROOT"
  export GIT_ROOT="$BATS_TEST_TMPDIR"
  export INIT_OUTPUT_DIR="$BATS_TEST_TMPDIR"

  # Default mock: gh repo view returns owner/repo.
  unset MOCK_REPO_VIEW_RESPONSE MOCK_REPO_VIEW_EXIT || true
}

# Helper: run ralph_init with five lines of stdin input.
# Usage: _run_init "repo" "upstream" "build" "test" "confirm"
_run_init() {
  local repo_input="$1"
  local upstream_input="$2"
  local build_input="$3"
  local test_input="$4"
  local confirm_input="$5"
  run ralph_init <<< "$(printf '%s\n' \
    "$repo_input" \
    "$upstream_input" \
    "$build_input" \
    "$test_input" \
    "$confirm_input")"
}

# ─── Header ───────────────────────────────────────────────────────────────────

@test "init: output contains Ralph header" {
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "Ralph"
}

@test "init: output uses box style (━━━)" {
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "━━━"
}

# ─── All defaults accepted ────────────────────────────────────────────────────

@test "init: all defaults accepted → file written with inferred repo, blank build/test" {
  # Enter for all fields → accept defaults; Y to confirm.
  _run_init "" "" "" "" "Y"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'repo = "owner/repo"' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'upstream = ""' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'build = ""' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = ""' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── User overrides repo and test ─────────────────────────────────────────────

@test "init: user overrides repo and test → file contains typed values" {
  _run_init "myorg/myrepo" "" "" "npm test" "Y"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'repo = "myorg/myrepo"' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = "npm test"' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Upstream left blank ──────────────────────────────────────────────────────

@test "init: upstream left blank → field written as empty string" {
  _run_init "" "" "" "" "Y"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'upstream = ""' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Decline preview → file not written ──────────────────────────────────────

@test "init: 'n' at preview → file not written, clean exit" {
  _run_init "" "" "" "" "n"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/ralph.toml" ]
}

@test "init: 'N' at preview → file not written, clean exit" {
  _run_init "" "" "" "" "N"
  [ "$status" -eq 0 ]
  [ ! -f "$BATS_TEST_TMPDIR/ralph.toml" ]
}

# ─── File preview shown before writing ───────────────────────────────────────

@test "init: file preview shown before confirmation" {
  _run_init "preview/test" "" "" "" "n"
  echo "$output" | grep -q "ralph.toml preview"
  echo "$output" | grep -q 'repo = "preview/test"'
}

# ─── Written file includes inline comments ───────────────────────────────────

@test "init: written file includes inline comments matching example style" {
  _run_init "" "" "" "" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q "# GitHub repo slug" "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q "# Upstream repo slug" "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q "# Build command" "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q "# Test command" "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Repo inferred from gh repo view ─────────────────────────────────────────

@test "init: repo default is inferred from gh repo view" {
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "owner/repo"
}

@test "init: gh inference fails → blank default offered" {
  export MOCK_REPO_VIEW_EXIT=1
  _run_init "" "" "" "" "n"
  [ "$status" -eq 0 ]
  # Should still complete without error (blank default used).
  echo "$output" | grep -q "repo"
}

# ─── ralph_doctor called after successful write ───────────────────────────────

@test "init: ralph_doctor called after successful write (or nudge printed)" {
  _run_init "" "" "" "" "Y"
  [ "$status" -eq 0 ]
  # Either ralph_doctor output (contains "🩺 Ralph — doctor") or nudge message.
  (echo "$output" | grep -q "🩺 Ralph" || echo "$output" | grep -q "ralph doctor")
}

# ─── Subcommand dispatch integration ──────────────────────────────────────────

@test "ralph.sh init: subcommand dispatches correctly" {
  run "$REPO_ROOT/ralph.sh" init <<< "$(printf '%s\n' "" "" "" "" "n")"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Ralph"
}
