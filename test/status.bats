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
  unset MOCK_PR_LIST_EXIT || true
  unset MOCK_PR_LIST_ERROR || true
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

# ─── CI: cancelled/action-required/startup-failure → failing ─────────────────

@test "status: CI with CANCELLED conclusion → shows failing" {
  export MOCK_PR_LIST_RESPONSE='[{
    "number": 20,
    "headRefName": "ralph/issue-20",
    "reviewDecision": null,
    "statusCheckRollup": [
      {"conclusion": "CANCELLED", "status": "COMPLETED"},
      {"conclusion": "SUCCESS", "status": "COMPLETED"}
    ]
  }]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "failing"
}

@test "status: CI with ACTION_REQUIRED conclusion → shows failing" {
  export MOCK_PR_LIST_RESPONSE='[{
    "number": 21,
    "headRefName": "ralph/issue-21",
    "reviewDecision": null,
    "statusCheckRollup": [
      {"conclusion": "ACTION_REQUIRED", "status": "COMPLETED"}
    ]
  }]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "failing"
}

@test "status: CI with STARTUP_FAILURE conclusion → shows failing" {
  export MOCK_PR_LIST_RESPONSE='[{
    "number": 22,
    "headRefName": "ralph/issue-22",
    "reviewDecision": null,
    "statusCheckRollup": [
      {"conclusion": "STARTUP_FAILURE", "status": "COMPLETED"}
    ]
  }]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "failing"
}

# ─── gh pr list failure → surfaces error ─────────────────────────────────────

@test "status: gh pr list failure → shows error and returns non-zero" {
  export MOCK_PR_LIST_EXIT=1
  export MOCK_PR_LIST_ERROR="could not authenticate: token expired"
  run ralph_status
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "gh pr list failed"
  echo "$output" | grep -q "token expired"
}

# ─── Issues section ───────────────────────────────────────────────────────────

@test "status: issues section appears in output" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Issues"
}

@test "status: no open issues → shows placeholder" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no open issues"
}

@test "status: open issue → shows number and title" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[{"number": 42, "title": "Fix the widget", "labels": []}]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "42"
  echo "$output" | grep -q "Fix the widget"
}

@test "status: blocked issue → shows warning indicator" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[{"number": 7, "title": "Blocked task", "labels": [{"name": "blocked"}]}]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "7"
  echo "$output" | grep -q "Blocked task"
  echo "$output" | grep -q "⚠️"
}

@test "status: non-blocked issue → no warning indicator" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[{"number": 8, "title": "Normal task", "labels": []}]'
  run ralph_status
  [ "$status" -eq 0 ]
  issue_line=$(echo "$output" | grep "Normal task")
  echo "$issue_line" | grep -qv "⚠️"
}

@test "status: multiple issues → each appears on its own line" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[
    {"number": 3, "title": "First task", "labels": []},
    {"number": 9, "title": "Second task", "labels": [{"name": "blocked"}]}
  ]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "First task"
  echo "$output" | grep -q "Second task"
  echo "$output" | grep -q "⚠️"
}

# ─── Feature PR section ───────────────────────────────────────────────────────

@test "status: --label set, feature PR exists → shows feature PR section" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[]'
  export MOCK_FEATURE_PR_LIST_RESPONSE='[{
    "number": 100,
    "headRefName": "feat/my-feature",
    "reviewDecision": "APPROVED",
    "statusCheckRollup": [{"conclusion": "SUCCESS", "status": "COMPLETED"}]
  }]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Feature PR"
  echo "$output" | grep -q "100"
  echo "$output" | grep -q "feat/my-feature"
}

@test "status: --label set, no feature PR → feature PR section absent" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[]'
  export MOCK_FEATURE_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "Feature PR"
}

@test "status: no --label flag → feature PR section absent" {
  export FEATURE_LABEL=""
  export FEATURE_BRANCH="main"
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -qv "Feature PR"
}

# ─── JIRA mode (--ticket) ─────────────────────────────────────────────────────

@test "status --ticket: renders parent ticket key, summary, and status" {
  export PARENT_TICKET="CAPP-100"
  unset FEATURE_LABEL
  export MOCK_JIRA_ISSUE_VIEW_RESPONSE=$'CAPP-100\tBuild the widget\tIn Progress'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tSub-task\tFirst subtask\tTo Do\tHigh'
  export MOCK_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CAPP-100"
  echo "$output" | grep -q "Build the widget"
  echo "$output" | grep -q "In Progress"
}

@test "status --ticket: renders subtask row with key, summary, status, priority" {
  export PARENT_TICKET="CAPP-100"
  unset FEATURE_LABEL
  export MOCK_JIRA_ISSUE_VIEW_RESPONSE=$'CAPP-100\tParent ticket\tIn Progress'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tSub-task\tFirst subtask\tTo Do\tHigh'
  export MOCK_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CAPP-101"
  echo "$output" | grep -q "First subtask"
  echo "$output" | grep -q "To Do"
  echo "$output" | grep -q "High"
}

@test "status --ticket: subtask with no linked PR shows em dash" {
  export PARENT_TICKET="CAPP-100"
  unset FEATURE_LABEL
  export MOCK_JIRA_ISSUE_VIEW_RESPONSE=$'CAPP-100\tParent\tIn Progress'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tSub-task\tNo linked PR\tTo Do\tMedium'
  export MOCK_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  # Subtask row must contain an em dash placeholder for missing PR.
  row=$(echo "$output" | grep "CAPP-101")
  echo "$row" | grep -q "—"
}

@test "status --ticket: subtask with linked PR shows PR number" {
  export PARENT_TICKET="CAPP-100"
  unset FEATURE_LABEL
  export MOCK_JIRA_ISSUE_VIEW_RESPONSE=$'CAPP-100\tParent\tIn Progress'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tSub-task\tHas linked PR\tIn Progress\tMedium'
  export MOCK_PR_LIST_RESPONSE='[{"number": 99, "headRefName": "feat/capp-101-has-linked-pr"}]'
  run ralph_status
  [ "$status" -eq 0 ]
  row=$(echo "$output" | grep "CAPP-101")
  echo "$row" | grep -q "#99"
}

@test "status --ticket: multiple subtasks (open + done) all rendered" {
  export PARENT_TICKET="CAPP-100"
  unset FEATURE_LABEL
  export MOCK_JIRA_ISSUE_VIEW_RESPONSE=$'CAPP-100\tParent\tIn Progress'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tSub-task\tOpen one\tTo Do\tHigh\nCAPP-102\tSub-task\tDone one\tDone\tMedium'
  export MOCK_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CAPP-101"
  echo "$output" | grep -q "Open one"
  echo "$output" | grep -q "CAPP-102"
  echo "$output" | grep -q "Done one"
}

@test "status --ticket: no subtasks → shows placeholder" {
  export PARENT_TICKET="CAPP-100"
  unset FEATURE_LABEL
  export MOCK_JIRA_ISSUE_VIEW_RESPONSE=$'CAPP-100\tParent\tTo Do'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=""
  export MOCK_PR_LIST_RESPONSE='[]'
  run ralph_status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no subtasks"
}
