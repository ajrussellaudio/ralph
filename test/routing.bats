#!/usr/bin/env bats
# test/routing.bats — bats test suite for determine_mode() routing

load 'test_helper'

setup() {
  # Temp DB for each test
  TEST_DB="$(mktemp)"
  create_test_db "$TEST_DB"

  # Environment required by determine_mode()
  export DB_PATH="$TEST_DB"
  export RALPH_SKIP_SYNC=1
  export FEATURE_BRANCH="main"
  export FEATURE_LABEL=""
  export REPO="test/repo"
  export WORKTREE_DIR="/tmp/ralph-test-worktree"
  export COMPLETE_REASON=""

  # Source routing logic
  # shellcheck source=../lib/routing.sh
  source "$RALPH_DIR/lib/routing.sh"
}

teardown() {
  rm -f "$TEST_DB"
  # Remove any mock bin that tests may have added
  rm -rf "${BATS_TMPDIR:-/tmp}/ralph-mock-bin-$$"
}

# ── Routing: individual status cases ──────────────────────────────────────────

@test "pending task → implement" {
  insert_task "$TEST_DB" 1 "pending"

  determine_mode

  [ "$MODE"    = "implement" ]
  [ "$TASK_ID" = "1" ]
}

@test "needs_review task → review" {
  insert_task "$TEST_DB" 1 "needs_review"

  determine_mode

  [ "$MODE"    = "review" ]
  [ "$TASK_ID" = "1" ]
}

@test "needs_fix task with fix_count=0 → fix" {
  insert_task "$TEST_DB" 1 "needs_fix" "normal" "0"

  determine_mode

  [ "$MODE"    = "fix" ]
  [ "$TASK_ID" = "1" ]
}

@test "needs_fix task with fix_count=2 → force-approve" {
  insert_task "$TEST_DB" 1 "needs_fix" "normal" "2"

  determine_mode

  [ "$MODE"    = "force-approve" ]
  [ "$TASK_ID" = "1" ]
}

@test "approved task → merge" {
  insert_task "$TEST_DB" 1 "approved"

  determine_mode

  [ "$MODE"    = "merge" ]
  [ "$TASK_ID" = "1" ]
}

@test "in_progress task → fix (resume)" {
  insert_task "$TEST_DB" 1 "in_progress"

  determine_mode

  [ "$MODE"    = "fix" ]
  [ "$TASK_ID" = "1" ]
}

@test "needs_review_2 task → review-round2" {
  insert_task "$TEST_DB" 1 "needs_review_2"

  determine_mode

  [ "$MODE"    = "review-round2" ]
  [ "$TASK_ID" = "1" ]
}

# ── Routing: all-done cases ────────────────────────────────────────────────────

@test "all tasks done, no feature label → complete" {
  insert_task "$TEST_DB" 1 "done"

  determine_mode

  [ "$MODE" = "complete" ]
}

@test "all tasks done, feature label, no upstream PR → feature-pr" {
  insert_task "$TEST_DB" 1 "done"

  # Mock gh so it returns PR count = 0 (no existing feature PR)
  local mock_bin="${BATS_TMPDIR:-/tmp}/ralph-mock-bin-$$"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/gh" <<'EOF'
#!/bin/bash
echo "0"
EOF
  chmod +x "$mock_bin/gh"
  export PATH="$mock_bin:$PATH"

  export FEATURE_LABEL="prd/test-widget"
  export FEATURE_BRANCH="feat/test-widget"

  determine_mode

  [ "$MODE" = "feature-pr" ]
}

@test "all tasks done, feature label, PR already exists → complete" {
  insert_task "$TEST_DB" 1 "done"

  # Mock gh so it returns PR count = 1 (PR already exists)
  local mock_bin="${BATS_TMPDIR:-/tmp}/ralph-mock-bin-$$"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/gh" <<'EOF'
#!/bin/bash
echo "1"
EOF
  chmod +x "$mock_bin/gh"
  export PATH="$mock_bin:$PATH"

  export FEATURE_LABEL="prd/test-widget"
  export FEATURE_BRANCH="feat/test-widget"

  determine_mode

  [ "$MODE" = "complete" ]
}

# ── Routing: blocked task ──────────────────────────────────────────────────────

@test "pending task blocked by incomplete task → complete (nothing to do)" {
  # Only task 1 exists: it is pending but blocked by task 2, which is not in the DB
  # (and therefore not done). No unblocked pending tasks exist → complete.
  insert_task "$TEST_DB" 1 "pending" "normal" "0" "2"

  determine_mode

  [ "$MODE" = "complete" ]
}

# ── Routing: priority ordering ─────────────────────────────────────────────────

@test "high-priority pending task chosen over normal-priority pending task" {
  insert_task "$TEST_DB" 1 "pending" "normal"
  insert_task "$TEST_DB" 2 "pending" "high"

  determine_mode

  [ "$MODE"    = "implement" ]
  [ "$TASK_ID" = "2" ]
}
