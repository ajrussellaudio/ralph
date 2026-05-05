#!/usr/bin/env bats
# Tests for gh_with_retry() in lib/utils.sh.
#
# Uses PATH prepending to inject a configurable mock_gh stub from test/helpers/.
# The stub reads MOCK_GH_FAIL_TIMES, MOCK_GH_STDOUT, MOCK_GH_EXIT and writes
# to MOCK_GH_COUNTER_FILE so tests can assert invocation count.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  # Source utils into this shell.
  # shellcheck source=../lib/utils.sh
  source "$REPO_ROOT/lib/utils.sh"

  # Create a temp dir with a `gh` symlink pointing at our mock stub.
  mkdir -p "$BATS_TEST_TMPDIR/mock-bin"
  # Copy mock_gh into the test-local bin dir (not a symlink — tests that write
  # a custom gh must not corrupt the shared test/helpers/mock_gh source file).
  cp "$REPO_ROOT/test/helpers/mock_gh" "$BATS_TEST_TMPDIR/mock-bin/gh"
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/gh"
  export PATH="$BATS_TEST_TMPDIR/mock-bin:$PATH"

  # Counter file is unique per test run.
  export MOCK_GH_COUNTER_FILE="$BATS_TEST_TMPDIR/gh_counter"

  # Clear mock env vars so tests start from a clean state.
  unset MOCK_GH_FAIL_TIMES MOCK_GH_STDOUT MOCK_GH_EXIT || true
}

# Helper: read invocation count from the counter file.
gh_call_count() {
  if [[ -f "$MOCK_GH_COUNTER_FILE" ]]; then
    cat "$MOCK_GH_COUNTER_FILE"
  else
    echo 0
  fi
}

# ─── success path ─────────────────────────────────────────────────────────────

@test "first attempt succeeds → stdout forwarded, exit 0, gh called once, no warning" {
  export MOCK_GH_FAIL_TIMES=0
  export MOCK_GH_STDOUT="hello world"

  run gh_with_retry pr list
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
  [ "$(gh_call_count)" -eq 1 ]
}

@test "first attempt succeeds → no warning printed to stderr" {
  export MOCK_GH_FAIL_TIMES=0
  export MOCK_GH_STDOUT="ok"

  # bats `run` captures stderr in $output only with --separate-stderr flag (bats ≥1.7)
  # We redirect stderr to a file and assert it is empty.
  gh_with_retry pr list 2>"$BATS_TEST_TMPDIR/stderr.txt"
  [ ! -s "$BATS_TEST_TMPDIR/stderr.txt" ]
}

# ─── single retry ─────────────────────────────────────────────────────────────

@test "first attempt fails, second succeeds → warning printed, exit 0, gh called twice" {
  export MOCK_GH_FAIL_TIMES=1
  export MOCK_GH_EXIT=1
  export MOCK_GH_STDOUT="recovered"

  run --separate-stderr gh_with_retry pr list
  [ "$status" -eq 0 ]
  [ "$output" = "recovered" ]
  [ "$(gh_call_count)" -eq 2 ]
  [[ "$stderr" == *"attempt 1/3"* ]]
}

@test "first attempt fails → warning message matches expected format" {
  export MOCK_GH_FAIL_TIMES=1
  export MOCK_GH_EXIT=42
  export MOCK_GH_STDOUT=""

  run --separate-stderr gh_with_retry api /some/endpoint
  [[ "$stderr" == *"⚠️"* ]]
  [[ "$stderr" == *"retrying"* ]]
}

# ─── all attempts exhausted ───────────────────────────────────────────────────

@test "all 3 attempts fail → non-zero exit" {
  export MOCK_GH_FAIL_TIMES=99
  export MOCK_GH_EXIT=2

  run gh_with_retry pr list
  [ "$status" -ne 0 ]
}

@test "all 3 attempts fail → gh called exactly 3 times" {
  export MOCK_GH_FAIL_TIMES=99
  export MOCK_GH_EXIT=1

  run gh_with_retry pr list
  [ "$(gh_call_count)" -eq 3 ]
}

@test "all 3 attempts fail → 2 warning messages on stderr" {
  export MOCK_GH_FAIL_TIMES=99
  export MOCK_GH_EXIT=1

  run --separate-stderr gh_with_retry pr list
  warning_count=$(echo "$stderr" | grep -c "⚠️" || true)
  [ "$warning_count" -eq 2 ]
}

@test "all 3 attempts fail → final error message on stderr" {
  export MOCK_GH_FAIL_TIMES=99
  export MOCK_GH_EXIT=1

  run --separate-stderr gh_with_retry pr list
  [[ "$stderr" == *"❌"* ]]
  [[ "$stderr" == *"3 attempts"* ]]
}

@test "all 3 attempts fail → last non-zero exit code returned" {
  export MOCK_GH_FAIL_TIMES=99
  export MOCK_GH_EXIT=5

  run gh_with_retry pr list
  [ "$status" -eq 5 ]
}

# ─── argument forwarding ──────────────────────────────────────────────────────

@test "arguments are forwarded verbatim to gh" {
  # We verify by capturing the args the stub receives. The stub doesn't echo
  # args back, so we use a custom wrapper that logs args to a file.
  cat > "$BATS_TEST_TMPDIR/mock-bin/gh" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${ARG_LOG_FILE}"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/gh"

  export ARG_LOG_FILE="$BATS_TEST_TMPDIR/args.txt"
  gh_with_retry pr list --repo owner/repo

  grep -q "pr"        "$ARG_LOG_FILE"
  grep -q "list"      "$ARG_LOG_FILE"
  grep -q "owner/repo" "$ARG_LOG_FILE"
}

# ─── stdin forwarding ─────────────────────────────────────────────────────────

@test "stdin forwarding: < /dev/null pattern works correctly" {
  # A stub that reads stdin and exits 0 — should not block when /dev/null is used.
  cat > "$BATS_TEST_TMPDIR/mock-bin/gh" << 'EOF'
#!/usr/bin/env bash
# Read any stdin (non-blocking thanks to /dev/null at call site).
stdin_content=$(cat)
printf '%s' "$stdin_content" > "${STDIN_LOG_FILE}"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/gh"

  export STDIN_LOG_FILE="$BATS_TEST_TMPDIR/stdin.txt"
  gh_with_retry api /repos < /dev/null

  # stdin should have been empty (EOF from /dev/null).
  [ ! -s "$STDIN_LOG_FILE" ]
}

# ─── stderr forwarding ────────────────────────────────────────────────────────

@test "stderr from gh is forwarded to caller on success" {
  # A stub that writes to its own stderr and exits 0.
  cat > "$BATS_TEST_TMPDIR/mock-bin/gh" << 'EOF'
#!/usr/bin/env bash
echo "gh stderr output" >&2
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/gh"

  run --separate-stderr gh_with_retry pr list
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"gh stderr output"* ]]
}

@test "stderr from gh is forwarded to caller on failure/exhaustion" {
  # A stub that writes to stderr on every invocation and always fails.
  cat > "$BATS_TEST_TMPDIR/mock-bin/gh" << 'STUB'
#!/usr/bin/env bash
echo "gh native error" >&2
exit 1
STUB
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/gh"

  run --separate-stderr gh_with_retry pr list
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"gh native error"* ]]
  [ "$(echo "$stderr" | grep -c 'gh native error')" -eq 3 ]
}

# ─── jira_branch_prefix ───────────────────────────────────────────────────────

@test "jira_branch_prefix: Bug → fix" {
  [ "$(jira_branch_prefix Bug)" = "fix" ]
}

@test "jira_branch_prefix: Improvement → refactor" {
  [ "$(jira_branch_prefix Improvement)" = "refactor" ]
}

@test "jira_branch_prefix: Task → feat" {
  [ "$(jira_branch_prefix Task)" = "feat" ]
}

@test "jira_branch_prefix: Sub-task → feat" {
  [ "$(jira_branch_prefix "Sub-task")" = "feat" ]
}

@test "jira_branch_prefix: Story → feat" {
  [ "$(jira_branch_prefix Story)" = "feat" ]
}

@test "jira_branch_prefix: Spike → feat" {
  [ "$(jira_branch_prefix Spike)" = "feat" ]
}

@test "jira_branch_prefix: Epic → feat" {
  [ "$(jira_branch_prefix Epic)" = "feat" ]
}

@test "jira_branch_prefix: unknown type → feat" {
  [ "$(jira_branch_prefix "Some Future Type")" = "feat" ]
}

@test "jira_branch_prefix: empty → feat" {
  [ "$(jira_branch_prefix "")" = "feat" ]
}

# ─── jira_kebab_summary ───────────────────────────────────────────────────────

@test "jira_kebab_summary: simple title → kebab-case" {
  [ "$(jira_kebab_summary "Add login button")" = "add-login-button" ]
}

@test "jira_kebab_summary: lowercases all letters" {
  [ "$(jira_kebab_summary "FOO Bar BAZ")" = "foo-bar-baz" ]
}

@test "jira_kebab_summary: strips special characters" {
  [ "$(jira_kebab_summary "Fix: don't crash on @user!")" = "fix-don-t-crash-on-user" ]
}

@test "jira_kebab_summary: collapses runs of separators" {
  [ "$(jira_kebab_summary "foo   ___   bar")" = "foo-bar" ]
}

@test "jira_kebab_summary: trims leading/trailing dashes" {
  [ "$(jira_kebab_summary "   hello world   ")" = "hello-world" ]
}

@test "jira_kebab_summary: empty input → empty output" {
  [ "$(jira_kebab_summary "")" = "" ]
}

@test "jira_kebab_summary: only-special-chars → empty" {
  [ "$(jira_kebab_summary "!@#\$%^&*()")" = "" ]
}

@test "jira_kebab_summary: truncates very long summaries" {
  long_summary="this is a very long summary that should definitely be truncated to a reasonable length for branches"
  out=$(jira_kebab_summary "$long_summary")
  [ "${#out}" -le 50 ]
  # Should not end with a dash after truncation
  [[ "$out" != *- ]]
}

# ─── jira_feature_branch ──────────────────────────────────────────────────────

@test "jira_feature_branch: composes feat/<key>-<slug> from key+summary" {
  [ "$(jira_feature_branch CAPP-123 "Add login button")" = "feat/capp-123-add-login-button" ]
}

@test "jira_feature_branch: empty summary → feat/<key> only" {
  [ "$(jira_feature_branch CAPP-123 "")" = "feat/capp-123" ]
}

@test "jira_feature_branch: lowercases the project key" {
  [ "$(jira_feature_branch ABC-9 "Hello World")" = "feat/abc-9-hello-world" ]
}

# ─── jira_with_retry ──────────────────────────────────────────────────────────

@test "jira_with_retry: first attempt succeeds → exit 0, jira called once" {
  cp "$REPO_ROOT/test/helpers/mock_jira" "$BATS_TEST_TMPDIR/mock-bin/jira"
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/jira"
  export MOCK_JIRA_COUNTER_FILE="$BATS_TEST_TMPDIR/jira_counter"
  export MOCK_JIRA_FAIL_TIMES=0
  export MOCK_JIRA_STDOUT="ok"

  run jira_with_retry me
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
  [ "$(cat "$MOCK_JIRA_COUNTER_FILE")" -eq 1 ]
}

@test "jira_with_retry: fails twice then succeeds → exit 0, called 3 times" {
  cp "$REPO_ROOT/test/helpers/mock_jira" "$BATS_TEST_TMPDIR/mock-bin/jira"
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/jira"
  export MOCK_JIRA_COUNTER_FILE="$BATS_TEST_TMPDIR/jira_counter"
  export MOCK_JIRA_FAIL_TIMES=2
  export MOCK_JIRA_EXIT=1
  export MOCK_JIRA_STDOUT="recovered"

  run jira_with_retry issue list
  [ "$status" -eq 0 ]
  [ "$(cat "$MOCK_JIRA_COUNTER_FILE")" -eq 3 ]
}

@test "jira_with_retry: all 3 attempts fail → non-zero exit, called 3 times" {
  cp "$REPO_ROOT/test/helpers/mock_jira" "$BATS_TEST_TMPDIR/mock-bin/jira"
  chmod +x "$BATS_TEST_TMPDIR/mock-bin/jira"
  export MOCK_JIRA_COUNTER_FILE="$BATS_TEST_TMPDIR/jira_counter"
  export MOCK_JIRA_FAIL_TIMES=99
  export MOCK_JIRA_EXIT=2

  run jira_with_retry issue list
  [ "$status" -eq 2 ]
  [ "$(cat "$MOCK_JIRA_COUNTER_FILE")" -eq 3 ]
}
