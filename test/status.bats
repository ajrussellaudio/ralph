#!/usr/bin/env bats
# Tests for ralph_status() in lib/status.sh.
#
# A mock gh binary in test/helpers/ is placed first on PATH; it reads response
# data from MOCK_* environment variables and applies any --jq filter via real jq.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export PATH="$REPO_ROOT/test/helpers:$PATH"

  # Source status function into this shell.
  # shellcheck source=../lib/status.sh
  source "$REPO_ROOT/lib/status.sh"

  # Common defaults — individual tests override as needed.
  export REPO="owner/repo"
  export FEATURE_BRANCH="feat/my-feature"
  export FEATURE_LABEL="prd/my-feature"
  export RALPH_TESTING=1

  # Clear all mock env vars so tests start from a clean slate.
  unset MOCK_PR_LIST_RESPONSE || true
}

# ─── Header ───────────────────────────────────────────────────────────────────

@test "status: output contains Ralph header" {
  export MOCK_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Ralph"
}

# ─── No open PRs ─────────────────────────────────────────────────────────────

@test "status: no open PRs → shows placeholder" {
  export MOCK_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no open PRs"
}

# ─── Single approved PR with passing CI ──────────────────────────────────────

@test "status: approved PR with passing CI → shows APPROVED and passing" {
  export MOCK_PR_LIST_RESPONSE='[{
    "number": 42,
    "headRefName": "ralph/issue-42",
    "reviewDecision": "APPROVED",
    "statusCheckRollup": [
      {"conclusion": "SUCCESS", "status": "COMPLETED"},
      {"conclusion": "SUCCESS", "status": "COMPLETED"}
    ]
  }]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "42"
  echo "$output" | grep -q "ralph/issue-42"
  echo "$output" | grep -q "APPROVED"
  echo "$output" | grep -q "passing"
}

# ─── Changes-requested PR with failing CI ────────────────────────────────────

@test "status: changes-requested PR with failing CI → shows CHANGES_REQUESTED and failing" {
  export MOCK_PR_LIST_RESPONSE='[{
    "number": 7,
    "headRefName": "ralph/issue-7",
    "reviewDecision": "CHANGES_REQUESTED",
    "statusCheckRollup": [
      {"conclusion": "FAILURE", "status": "COMPLETED"},
      {"conclusion": "SUCCESS", "status": "COMPLETED"}
    ]
  }]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "7"
  echo "$output" | grep -q "ralph/issue-7"
  echo "$output" | grep -q "CHANGES_REQUESTED"
  echo "$output" | grep -q "failing"
}

# ─── Pending review PR with pending CI ───────────────────────────────────────

@test "status: pending review PR with pending CI → shows PENDING and pending" {
  export MOCK_PR_LIST_RESPONSE='[{
    "number": 15,
    "headRefName": "ralph/issue-15",
    "reviewDecision": null,
    "statusCheckRollup": [
      {"conclusion": null, "status": "IN_PROGRESS"}
    ]
  }]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "15"
  echo "$output" | grep -q "ralph/issue-15"
  echo "$output" | grep -q "PENDING"
  echo "$output" | grep -q "pending"
}

# ─── Multiple PRs ─────────────────────────────────────────────────────────────

@test "status: multiple PRs → each appears on its own line" {
  export MOCK_PR_LIST_RESPONSE='[
    {
      "number": 3,
      "headRefName": "ralph/issue-3",
      "reviewDecision": "APPROVED",
      "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}]
    },
    {
      "number": 8,
      "headRefName": "ralph/issue-8",
      "reviewDecision": "CHANGES_REQUESTED",
      "statusCheckRollup": [{"conclusion": "FAILURE", "status": "COMPLETED"}]
    }
  ]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "ralph/issue-3"
  echo "$output" | grep -q "ralph/issue-8"
  # Both should appear; count lines containing issue numbers
  pr3_lines=$(echo "$output" | grep -c "ralph/issue-3" || true)
  pr8_lines=$(echo "$output" | grep -c "ralph/issue-8" || true)
  [ "$pr3_lines" -ge 1 ]
  [ "$pr8_lines" -ge 1 ]
}
