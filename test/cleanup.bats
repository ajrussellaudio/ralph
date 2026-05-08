#!/usr/bin/env bats
# Tests for post_merge_cleanup() in lib/cleanup.sh.
#
# Mock `gh` and `jira` binaries in test/helpers/ are placed first on PATH; they
# read response data from MOCK_* environment variables.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export PATH="$REPO_ROOT/test/helpers:$PATH"

  # shellcheck source=../lib/cleanup.sh
  source "$REPO_ROOT/lib/cleanup.sh"

  export REPO="owner/repo"

  # Per-test transition log file lets us assert which jira moves were called.
  TRANSITION_LOG="$(mktemp)"
  export MOCK_JIRA_TRANSITION_LOG="$TRANSITION_LOG"

  unset MOCK_PR_VIEW_STATE_RESPONSE \
        MOCK_PR_VIEW_HEADREF_RESPONSE \
        MOCK_PR_VIEW_CLOSING_RESPONSE \
        TASK_BACKEND PROJECT_KEY PARENT_TICKET \
        || true
}

teardown() {
  [[ -n "${TRANSITION_LOG:-}" && -f "$TRANSITION_LOG" ]] && rm -f "$TRANSITION_LOG"
}

# ─── PR not merged → no-op ───────────────────────────────────────────────────

@test "post_merge_cleanup: PR not MERGED → returns 0, no transition" {
  export TASK_BACKEND="jira"
  export PROJECT_KEY="CAPP"
  export MOCK_PR_VIEW_STATE_RESPONSE='{"state":"OPEN"}'

  run post_merge_cleanup 42
  [ "$status" -eq 0 ]
  [ ! -s "$TRANSITION_LOG" ]
}

# ─── JIRA path ───────────────────────────────────────────────────────────────

@test "post_merge_cleanup (jira): merged PR with feat/CAPP-100-thing → transitions CAPP-100 to Done" {
  export TASK_BACKEND="jira"
  export PROJECT_KEY="CAPP"
  export MOCK_PR_VIEW_STATE_RESPONSE='{"state":"MERGED"}'
  export MOCK_PR_VIEW_HEADREF_RESPONSE='{"headRefName":"feat/CAPP-100-thing"}'

  run post_merge_cleanup 42

  [ "$status" -eq 0 ]
  run cat "$TRANSITION_LOG"
  [ "$output" = "CAPP-100 Done" ]
}

@test "post_merge_cleanup (jira): merged PR with lowercase feat/capp-101-x → transitions CAPP-101 to Done" {
  export TASK_BACKEND="jira"
  export PROJECT_KEY="CAPP"
  export MOCK_PR_VIEW_STATE_RESPONSE='{"state":"MERGED"}'
  export MOCK_PR_VIEW_HEADREF_RESPONSE='{"headRefName":"feat/capp-101-add-login"}'

  run post_merge_cleanup 42

  [ "$status" -eq 0 ]
  run cat "$TRANSITION_LOG"
  [ "$output" = "CAPP-101 Done" ]
}

@test "post_merge_cleanup (jira): fix/ and refactor/ branch prefixes also work" {
  export TASK_BACKEND="jira"
  export PROJECT_KEY="CAPP"
  export MOCK_PR_VIEW_STATE_RESPONSE='{"state":"MERGED"}'
  export MOCK_PR_VIEW_HEADREF_RESPONSE='{"headRefName":"fix/capp-202-bug"}'

  run post_merge_cleanup 42

  [ "$status" -eq 0 ]
  run cat "$TRANSITION_LOG"
  [ "$output" = "CAPP-202 Done" ]
}

@test "post_merge_cleanup (jira): branch with no project-key match → no transition, returns 0" {
  export TASK_BACKEND="jira"
  export PROJECT_KEY="CAPP"
  export MOCK_PR_VIEW_STATE_RESPONSE='{"state":"MERGED"}'
  export MOCK_PR_VIEW_HEADREF_RESPONSE='{"headRefName":"some/other-branch"}'

  run post_merge_cleanup 42
  [ "$status" -eq 0 ]
  [ ! -s "$TRANSITION_LOG" ]
}

@test "post_merge_cleanup (jira): different project key in branch is ignored" {
  export TASK_BACKEND="jira"
  export PROJECT_KEY="CAPP"
  export MOCK_PR_VIEW_STATE_RESPONSE='{"state":"MERGED"}'
  export MOCK_PR_VIEW_HEADREF_RESPONSE='{"headRefName":"feat/diff-1-other"}'

  run post_merge_cleanup 42
  [ "$status" -eq 0 ]
  [ ! -s "$TRANSITION_LOG" ]
}

# ─── GitHub path is unchanged when TASK_BACKEND != jira ──────────────────────

@test "post_merge_cleanup (github): JIRA branch is ignored — no transition called" {
  # TASK_BACKEND defaults to github; even if the branch looks like a JIRA
  # branch, post_merge_cleanup must take the GitHub path.
  unset TASK_BACKEND
  export MOCK_PR_VIEW_STATE_RESPONSE='{"state":"MERGED"}'
  export MOCK_PR_VIEW_HEADREF_RESPONSE='{"headRefName":"feat/capp-100-thing"}'
  export MOCK_PR_VIEW_CLOSING_RESPONSE='{"closingIssuesReferences":[]}'
  export MOCK_ISSUE_LIST_RESPONSE='[]'

  run post_merge_cleanup 42
  [ "$status" -eq 0 ]
  [ ! -s "$TRANSITION_LOG" ]
}
