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
  # Isolate project-file detection from the real working directory.
  export INIT_SCAN_DIR="$BATS_TEST_TMPDIR"

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

# ─── Special character escaping ──────────────────────────────────────────────

@test "init: double-quote in repo value is escaped in written file" {
  _run_init 'org/repo"hack' "" "" "" "Y"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -qF 'repo = "org/repo\"hack"' "$BATS_TEST_TMPDIR/ralph.toml"
}

@test "init: backslash in test value is escaped in written file" {
  _run_init "" "" "" 'npm run test\spec' "Y"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -qF 'test = "npm run test\\spec"' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Overwrite protection ─────────────────────────────────────────────────────

@test "init: existing ralph.toml → warns user, keeps file if declined" {
  echo "# existing" > "$BATS_TEST_TMPDIR/ralph.toml"
  run ralph_init <<< "$(printf '%s\n' "" "" "" "" "Y" "n")"
  [ "$status" -eq 0 ]
  grep -q "# existing" "$BATS_TEST_TMPDIR/ralph.toml"
  echo "$output" | grep -q "already exists"
}

@test "init: existing ralph.toml → overwrites when user confirms" {
  echo "# existing" > "$BATS_TEST_TMPDIR/ralph.toml"
  run ralph_init <<< "$(printf '%s\n' "" "" "" "" "Y" "y")"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  ! grep -q "# existing" "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'repo = "' "$BATS_TEST_TMPDIR/ralph.toml"
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

# ─── Project-type detection: no match ────────────────────────────────────────

@test "init: no project file → blank build/test defaults (no regression)" {
  # INIT_SCAN_DIR is empty temp dir — no project files.
  _run_init "" "" "" "" "Y"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = ""' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = ""' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Project-type detection: package.json ────────────────────────────────────

@test "init: package.json present → npm test offered as test default" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "npm test"
}

@test "init: package.json present → npm run build offered as build default" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "npm run build"
}

@test "init: package.json present, enter accepted → file written with npm commands" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  _run_init "" "" "" "" "Y"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = "npm run build"' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = "npm test"' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Project-type detection: go.mod ──────────────────────────────────────────

@test "init: go.mod present → go test ./... offered as test default" {
  echo 'module example.com/mymod' > "$BATS_TEST_TMPDIR/go.mod"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "go test ./\.\.\."
}

@test "init: go.mod present, enter accepted → file written with go commands" {
  echo 'module example.com/mymod' > "$BATS_TEST_TMPDIR/go.mod"
  _run_init "" "" "" "" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = "go build ./..."' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = "go test ./..."' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Project-type detection: Makefile ────────────────────────────────────────

@test "init: Makefile with test: target → make test offered" {
  printf 'test:\n\techo run tests\n' > "$BATS_TEST_TMPDIR/Makefile"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "make test"
}

@test "init: Makefile without test: target → make test NOT offered (blank default)" {
  printf 'lint:\n\techo lint\n' > "$BATS_TEST_TMPDIR/Makefile"
  _run_init "" "" "" "" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'test = ""' "$BATS_TEST_TMPDIR/ralph.toml"
}

@test "init: Makefile with build: target → make build offered" {
  printf 'build:\n\techo build\n' > "$BATS_TEST_TMPDIR/Makefile"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "make build"
}

@test "init: Makefile without build: target → make build NOT offered (blank default)" {
  printf 'lint:\n\techo lint\n' > "$BATS_TEST_TMPDIR/Makefile"
  _run_init "" "" "" "" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = ""' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Project-type detection: Cargo.toml ──────────────────────────────────────

@test "init: Cargo.toml present → cargo test offered as test default" {
  echo '[package]' > "$BATS_TEST_TMPDIR/Cargo.toml"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "cargo test"
}

@test "init: Cargo.toml present, enter accepted → file written with cargo commands" {
  echo '[package]' > "$BATS_TEST_TMPDIR/Cargo.toml"
  _run_init "" "" "" "" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = "cargo build"' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = "cargo test"' "$BATS_TEST_TMPDIR/ralph.toml"
}

# ─── Multiple matches: numbered list presented ────────────────────────────────

@test "init: multiple project files → numbered options shown for test" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  echo 'module example.com/m' > "$BATS_TEST_TMPDIR/go.mod"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "1)"
  echo "$output" | grep -q "2)"
}

@test "init: multiple project files → user picks number → correct command written" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  echo 'module example.com/m' > "$BATS_TEST_TMPDIR/go.mod"
  # build: pick option 1 (npm run build), test: pick option 1 (npm test)
  _run_init "" "" "1" "1" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = "npm run build"' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = "npm test"' "$BATS_TEST_TMPDIR/ralph.toml"
}

@test "init: multiple project files → user picks second option" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  echo 'module example.com/m' > "$BATS_TEST_TMPDIR/go.mod"
  # build: pick option 2 (go build ./...), test: pick option 2 (go test ./...)
  _run_init "" "" "2" "2" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = "go build ./..."' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = "go test ./..."' "$BATS_TEST_TMPDIR/ralph.toml"
}

@test "init: multiple project files → user types custom value instead of picking number" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  echo 'module example.com/m' > "$BATS_TEST_TMPDIR/go.mod"
  _run_init "" "" "pnpm build" "vitest run" "Y"
  [ -f "$BATS_TEST_TMPDIR/ralph.toml" ]
  grep -q 'build = "pnpm build"' "$BATS_TEST_TMPDIR/ralph.toml"
  grep -q 'test = "vitest run"' "$BATS_TEST_TMPDIR/ralph.toml"
}

@test "init: multiple project files → 'Or type a custom value' shown in output" {
  echo '{}' > "$BATS_TEST_TMPDIR/package.json"
  echo 'module example.com/m' > "$BATS_TEST_TMPDIR/go.mod"
  _run_init "" "" "" "" "n"
  echo "$output" | grep -q "custom"
}
