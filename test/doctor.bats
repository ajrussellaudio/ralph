#!/usr/bin/env bats
# Tests for ralph_doctor() in lib/doctor.sh.
#
# Uses PATH manipulation to control which tools appear present/absent.
# The mock gh binary in test/helpers/ handles auth, repo view, and API calls.
# RALPH_TESTING=1 is set throughout.
#
# PATH isolation: each test that needs specific tool presence builds an isolated
# bin dir containing exactly the tools needed plus a jq symlink (required by the
# mock gh script). /usr/bin and /bin are included for standard POSIX utilities
# but NOT any package-manager prefix (homebrew, etc.) where a real copilot/gh
# could leak in.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
_JQ_BIN="$(command -v jq)"

setup() {
  # Source doctor function into this shell.
  # shellcheck source=../lib/doctor.sh
  source "$REPO_ROOT/lib/doctor.sh"

  export RALPH_TESTING=1

  # Build a hermetic PATH: test/helpers stubs + isolated jq + system basics only.
  # This avoids any homebrew/user dir where real copilot/gh might live.
  mkdir -p "$BATS_TEST_TMPDIR/jq-only"
  ln -sf "$_JQ_BIN" "$BATS_TEST_TMPDIR/jq-only/jq"
  export PATH="$REPO_ROOT/test/helpers:$BATS_TEST_TMPDIR/jq-only:/usr/bin:/bin"

  # Filesystem defaults.
  export MODES_DIR="$REPO_ROOT/modes"
  export CONFIG_FILE="$REPO_ROOT/ralph.toml"
  export REPO="owner/repo"
  export TEST_CMD="npm test"
  export BUILD_CMD="npm run build"

  # Clear all mock env vars.
  unset MOCK_AUTH_STATUS_EXIT MOCK_REPO_VIEW_RESPONSE MOCK_REPO_VIEW_EXIT \
        MOCK_RATE_LIMIT_EXIT || true
}

# Create a hermetic bin dir containing only the listed tools from test/helpers,
# plus jq. Sets PATH to that dir + /usr/bin:/bin (no homebrew prefix leaks).
_make_bin() {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ln -sf "$_JQ_BIN" "$bin/jq"
  for tool in "$@"; do
    cp "$REPO_ROOT/test/helpers/$tool" "$bin/$tool"
    chmod +x "$bin/$tool"
  done
  export PATH="$bin:/usr/bin:/bin"
}

# ─── All checks pass ──────────────────────────────────────────────────────────

@test "doctor: all checks pass → all ✅ lines and exit 0" {
  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✅"
  echo "$output" | grep -qv "❌"
  echo "$output" | grep -qv "⚠️"
}

@test "doctor: all checks pass → header printed" {
  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Ralph"
  echo "$output" | grep -q "━━━"
}

# ─── Hard failures ────────────────────────────────────────────────────────────

@test "doctor: copilot absent → ❌ line with fix hint and exit 1" {
  _make_bin gh

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*copilot"
  echo "$output" | grep -q "→.*Copilot CLI"
}

@test "doctor: gh absent → ❌ line with fix hint and exit 1" {
  _make_bin copilot

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*gh"
  echo "$output" | grep -q "→.*GitHub CLI"
}

@test "doctor: gh not authenticated → ❌ line with fix hint and exit 1" {
  export MOCK_AUTH_STATUS_EXIT=1

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*authenticated"
  echo "$output" | grep -q "→.*gh auth login"
}

@test "doctor: repo not resolvable → ❌ line with fix hint and exit 1" {
  export REPO=""
  export MOCK_REPO_VIEW_EXIT=1

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*repo"
  echo "$output" | grep -q "→.*ralph.toml"
}

@test "doctor: explicit REPO set but gh repo view fails → ❌ and exit 1" {
  export REPO="typo/nonexistent"
  export MOCK_REPO_VIEW_EXIT=1

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*repo"
  echo "$output" | grep -q "→.*ralph.toml"
}

@test "doctor: modes directory missing → ❌ line with fix hint and exit 1" {
  export MODES_DIR="/nonexistent/modes/dir"

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*modes"
  echo "$output" | grep -q "→.*reinstall"
}

# ─── Warnings ─────────────────────────────────────────────────────────────────

@test "doctor: ralph.toml absent → ⚠️ line with fix hint and exit 0" {
  export CONFIG_FILE=""

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "⚠️.*ralph.toml"
  echo "$output" | grep -q "→.*project.example.toml"
}

@test "doctor: test command missing → ⚠️ line with fix hint and exit 0" {
  export TEST_CMD=""

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "⚠️.*test"
  echo "$output" | grep -q "→.*test = "
}

@test "doctor: build command missing → ⚠️ line with fix hint and exit 0" {
  export BUILD_CMD=""

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "⚠️.*build"
  echo "$output" | grep -q "→.*build = "
}

@test "doctor: GitHub API unreachable → ⚠️ line with fix hint and exit 0" {
  export MOCK_RATE_LIMIT_EXIT=1

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "⚠️.*API"
  echo "$output" | grep -q "→.*network"
}

# ─── Multiple simultaneous failures ──────────────────────────────────────────

@test "doctor: multiple hard failures → all ❌ lines printed and exit 1" {
  _make_bin copilot
  export MODES_DIR="/nonexistent/modes/dir"
  export REPO=""
  export MOCK_REPO_VIEW_EXIT=1

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*gh"
  echo "$output" | grep -q "❌.*modes"
  # check #4 (repo) is intentionally skipped when gh is absent — no double error
  echo "$output" | grep -qv "❌.*repo"
}

@test "doctor: gh absent → check #4 (repo) skipped, no misleading repo error" {
  _make_bin copilot
  export REPO=""

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*gh"
  echo "$output" | grep -qv "❌.*repo"
}

@test "doctor: all checks run even when first check fails" {
  _make_bin gh
  # copilot absent (first check fails); modes still present
  export MODES_DIR="$REPO_ROOT/modes"

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*copilot"
  echo "$output" | grep -q "✅.*modes"
}

# ─── Mix of warnings and hard failures ───────────────────────────────────────

@test "doctor: mix of warnings and failures → ❌ lines and ⚠️ lines, exit 1" {
  export MODES_DIR="/nonexistent/modes/dir"
  export CONFIG_FILE=""
  export TEST_CMD=""

  run ralph_doctor
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "❌.*modes"
  echo "$output" | grep -q "⚠️.*ralph.toml"
  echo "$output" | grep -q "⚠️.*test"
}

# ─── Exit code behaviour ─────────────────────────────────────────────────────

@test "doctor: only warnings present → exit 0" {
  export CONFIG_FILE=""
  export TEST_CMD=""
  export BUILD_CMD=""

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "❌"
}

@test "doctor: each check prints exactly one status line" {
  run ralph_doctor
  [ "$status" -eq 0 ]
  # 9 checks → exactly 9 lines containing a status emoji
  local check_lines
  check_lines=$(echo "$output" | grep -cE "(✅|⚠️|❌)" || true)
  [ "$check_lines" -eq 9 ]
}

# ─── Subcommand dispatch integration ──────────────────────────────────────────

@test "ralph.sh doctor: subcommand dispatches correctly, exits 0, prints header" {
  run "$REPO_ROOT/ralph.sh" doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "🩺 Ralph — doctor"
}

# ─── jira-cli warning checks (only when TASK_BACKEND=jira) ───────────────────

@test "doctor: TASK_BACKEND=jira + jira-cli absent → ⚠️ line and exit 0" {
  export TASK_BACKEND=jira
  # Hermetic bin without jira (only gh + copilot from helpers).
  _make_bin gh copilot

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "⚠️.*jira"
  echo "$output" | grep -qi "→.*install"
}

@test "doctor: TASK_BACKEND=jira + jira-cli present + authed → ✅ line and exit 0" {
  export TASK_BACKEND=jira
  _make_bin gh copilot jira
  export MOCK_JIRA_AUTH_EXIT=0

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "✅.*jira"
  echo "$output" | grep -qv "⚠️.*jira"
}

@test "doctor: TASK_BACKEND=jira + jira-cli present but unauthenticated → ⚠️ line and exit 0" {
  export TASK_BACKEND=jira
  _make_bin gh copilot jira
  export MOCK_JIRA_AUTH_EXIT=1

  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "⚠️.*jira"
  echo "$output" | grep -qi "→.*auth\|→.*login\|→.*jira init"
}

@test "doctor: TASK_BACKEND unset → no jira-cli check lines (9-check behaviour preserved)" {
  unset TASK_BACKEND || true
  run ralph_doctor
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "jira"
}

# ─── All checks pass ──────────────────────────────────────────────────────────
