#!/usr/bin/env bats
# test/routing.bats — bats test suite for determine_mode() routing (markdown backend)

load 'test_helper'

setup() {
  PLANS_DIR="$(mktemp -d)"
  RAW_LABEL="test-label"
  FEATURE_BRANCH="feat/test-label"
  REPO="test/owner/repo"
}

teardown() {
  rm -rf "$PLANS_DIR"
}

# ── No label ──────────────────────────────────────────────────────────────────

@test "no feature label → complete mode" {
  RAW_LABEL=""
  determine_mode
  [ "$MODE" = "complete" ]
}

# ── Routing: individual status cases ─────────────────────────────────────────

@test "single pending task → implement" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=pending"
  determine_mode
  [ "$MODE"    = "implement" ]
  [ "$TASK_ID" = "01" ]
}

@test "in_progress task → fix (resume)" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=in_progress"
  determine_mode
  [ "$MODE"    = "fix" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_review task → review" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_review"
  determine_mode
  [ "$MODE"    = "review" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_fix task with fix_count=0 → fix" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_fix" "fix_count=0"
  determine_mode
  [ "$MODE"    = "fix" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_fix task with fix_count=1 → fix (below force-approve threshold)" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_fix" "fix_count=1"
  determine_mode
  [ "$MODE"    = "fix" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_fix task with fix_count=2 → force-approve" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_fix" "fix_count=2"
  determine_mode
  [ "$MODE"    = "force-approve" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_review_2 task with fix_count=0 → review-round2" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_review_2" "fix_count=0"
  determine_mode
  [ "$MODE"    = "review-round2" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_review_2 task with fix_count=1 → review-round2 (below force-approve threshold)" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_review_2" "fix_count=1"
  determine_mode
  [ "$MODE"    = "review-round2" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_review_2 task with fix_count=2 → force-approve" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_review_2" "fix_count=2"
  determine_mode
  [ "$MODE"    = "force-approve" ]
  [ "$TASK_ID" = "01" ]
}

@test "approved task → merge" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=approved"
  determine_mode
  [ "$MODE"    = "merge" ]
  [ "$TASK_ID" = "01" ]
}

@test "approved task takes priority over needs_review_2" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=approved"
  create_task_file "$PLANS_DIR" "02-task.md" "status=needs_review_2"
  determine_mode
  [ "$MODE"    = "merge" ]
  [ "$TASK_ID" = "01" ]
}

@test "needs_review takes priority over approved" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_review"
  create_task_file "$PLANS_DIR" "02-task.md" "status=approved"
  determine_mode
  [ "$MODE"    = "review" ]
  [ "$TASK_ID" = "01" ]
}

# ── Routing: all-done cases ───────────────────────────────────────────────────

@test "all tasks done, no feature label → complete" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=done"
  RAW_LABEL=""
  determine_mode
  [ "$MODE" = "complete" ]
}

@test "all tasks done, feature label, no upstream PR → feature-pr" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=done"

  # Mock gh to report PR count = 0 (no existing feature PR).
  local mock_bin
  mock_bin="$(mktemp -d)"
  printf '#!/bin/bash\necho "0"\n' > "$mock_bin/gh"
  chmod +x "$mock_bin/gh"
  export PATH="$mock_bin:$PATH"

  determine_mode
  rm -rf "$mock_bin"
  [ "$MODE" = "feature-pr" ]
}

@test "all tasks done, feature label, PR already exists → complete" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=done"

  # Mock gh to report PR count = 1 (feature PR already open).
  local mock_bin
  mock_bin="$(mktemp -d)"
  printf '#!/bin/bash\necho "1"\n' > "$mock_bin/gh"
  chmod +x "$mock_bin/gh"
  export PATH="$mock_bin:$PATH"

  determine_mode
  rm -rf "$mock_bin"
  [ "$MODE" = "complete" ]
}

# ── Routing: priority ordering ────────────────────────────────────────────────

@test "high-priority pending task chosen over normal-priority pending task" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=pending" "priority=normal"
  create_task_file "$PLANS_DIR" "02-task.md" "status=pending" "priority=high"
  determine_mode
  [ "$MODE"    = "implement" ]
  [ "$TASK_ID" = "02" ]
}

@test "review takes priority over implement" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=needs_review"
  create_task_file "$PLANS_DIR" "02-task.md" "status=pending"
  determine_mode
  [ "$MODE"    = "review" ]
  [ "$TASK_ID" = "01" ]
}

# ── Routing: blocked-by dependency enforcement ────────────────────────────────

@test "pending task blocked by undone dep → skipped, unblocked task gets implement" {
  # Task 01 is blocked by task 02 (which is pending, not done).
  # Task 02 has no blockers and is pending → should be selected.
  create_task_file "$PLANS_DIR" "01-task.md" "status=pending" "blocked_by=2"
  create_task_file "$PLANS_DIR" "02-task.md" "status=pending"
  determine_mode
  [ "$MODE"    = "implement" ]
  [ "$TASK_ID" = "02" ]
}

@test "pending task whose dep is done → unblocked, implement" {
  create_task_file "$PLANS_DIR" "01-task.md" "status=done"
  create_task_file "$PLANS_DIR" "02-task.md" "status=pending" "blocked_by=1"
  determine_mode
  [ "$MODE"    = "implement" ]
  [ "$TASK_ID" = "02" ]
}

@test "all pending tasks blocked → blocked mode" {
  # Task 01 is blocked by task 99 which does not exist (never done).
  create_task_file "$PLANS_DIR" "01-task.md" "status=pending" "blocked_by=99"
  determine_mode
  [ "$MODE" = "blocked" ]
}
