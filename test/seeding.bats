#!/usr/bin/env bats
# test/seeding.bats — bats test suite for tasks.md parsing and DB seeding

load 'test_helper'

SEED_SCRIPT="$RALPH_DIR/lib/seed.py"

setup() {
  TEST_DB="$(mktemp)"
  TEST_TASKS="$(mktemp)"
  create_test_db "$TEST_DB"
}

teardown() {
  rm -f "$TEST_DB" "$TEST_TASKS"
}

# ── Seeding: basic cases ───────────────────────────────────────────────────────

@test "valid tasks.md seeds correct row count" {
  cat > "$TEST_TASKS" << 'EOF'
---
label: test-feature
prd: |
  Test PRD overview.
---

## Task 1 — First task

Task body here.

## Task 2 — Second task

Another task body.
EOF

  run python3 "$SEED_SCRIPT" "$TEST_TASKS" "$TEST_DB" "test-feature"

  [ "$status" -eq 0 ]
  row_count=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM tasks;")
  [ "$row_count" = "2" ]
}

@test "valid tasks.md seeds correct title, priority, status fields" {
  cat > "$TEST_TASKS" << 'EOF'
---
label: test-feature
prd: |
  Test PRD overview.
---

## Task 1 — Core engine
**Priority:** high

High-priority implementation task.
EOF

  python3 "$SEED_SCRIPT" "$TEST_TASKS" "$TEST_DB" "test-feature"

  result=$(sqlite3 "$TEST_DB" "SELECT title, priority, status FROM tasks WHERE id=1;")
  [ "$result" = "Core engine|high|pending" ]
}

@test "valid tasks.md with blocked task sets blocked_by correctly" {
  cat > "$TEST_TASKS" << 'EOF'
---
label: test-feature
prd: |
  Test PRD overview.
---

## Task 1 — First task

First task body.

## Task 2 — Depends on task 1
**Blocked by:** 1

Depends on task 1.
EOF

  python3 "$SEED_SCRIPT" "$TEST_TASKS" "$TEST_DB" "test-feature"

  blocked_by=$(sqlite3 "$TEST_DB" "SELECT blocked_by FROM tasks WHERE id=2;")
  [ "$blocked_by" = "1" ]
}

@test "task without blocked_by has NULL blocked_by" {
  cat > "$TEST_TASKS" << 'EOF'
---
label: test-feature
prd: |
  Test PRD overview.
---

## Task 1 — Standalone task

No dependencies.
EOF

  python3 "$SEED_SCRIPT" "$TEST_TASKS" "$TEST_DB" "test-feature"

  blocked_by=$(sqlite3 "$TEST_DB" "SELECT COALESCE(blocked_by, 'NULL') FROM tasks WHERE id=1;")
  [ "$blocked_by" = "NULL" ]
}

@test "seeding is idempotent — running twice does not change row count" {
  cat > "$TEST_TASKS" << 'EOF'
---
label: test-feature
prd: |
  Test PRD.
---

## Task 1 — A task

Body.
EOF

  python3 "$SEED_SCRIPT" "$TEST_TASKS" "$TEST_DB" "test-feature"
  count_after_first=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM tasks;")

  # Second seed attempt inserts or replaces the same rows
  python3 "$SEED_SCRIPT" "$TEST_TASKS" "$TEST_DB" "test-feature"
  count_after_second=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM tasks;")

  [ "$count_after_first" = "$count_after_second" ]
}

# ── Seeding: error cases ───────────────────────────────────────────────────────

@test "missing tasks.md exits with non-zero and helpful message" {
  run python3 "$SEED_SCRIPT" "/nonexistent/tasks.md" "$TEST_DB" "test-feature"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"ERROR"* ]]
}
