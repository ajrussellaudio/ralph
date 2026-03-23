#!/usr/bin/env bats
# test/yaml_helpers.bats — bats test suite for get_front_matter_field and
# set_front_matter_field (markdown backend)

load 'test_helper'

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_FILE="$TEST_DIR/test.md"
  cat > "$TEST_FILE" <<'EOF'
---
status: needs_review
priority: high
fix_count: 3
branch: ralph/task-07
blocked_by: [1, 2]
review_notes: "looks good overall"
---

# Task body

Some content here.
EOF
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── YAML read: get_front_matter_field ────────────────────────────────────────

@test "get_front_matter_field returns string value" {
  result="$(get_front_matter_field "$TEST_FILE" "status")"
  [ "$result" = "needs_review" ]
}

@test "get_front_matter_field returns string value for branch field" {
  result="$(get_front_matter_field "$TEST_FILE" "branch")"
  [ "$result" = "ralph/task-07" ]
}

@test "get_front_matter_field returns integer value (as string)" {
  result="$(get_front_matter_field "$TEST_FILE" "fix_count")"
  [ "$result" = "3" ]
}

@test "get_front_matter_field returns list value as raw string" {
  result="$(get_front_matter_field "$TEST_FILE" "blocked_by")"
  [ "$result" = "[1, 2]" ]
}

@test "get_front_matter_field returns empty string for missing field" {
  result="$(get_front_matter_field "$TEST_FILE" "nonexistent_field")"
  [ "$result" = "" ]
}

@test "get_front_matter_field returns quoted string field (strips quotes)" {
  result="$(get_front_matter_field "$TEST_FILE" "review_notes")"
  [ "$result" = "looks good overall" ]
}

# ── YAML write: set_front_matter_field ───────────────────────────────────────

@test "set_front_matter_field updates a string field" {
  set_front_matter_field "$TEST_FILE" "status" "done"
  result="$(get_front_matter_field "$TEST_FILE" "status")"
  [ "$result" = "done" ]
}

@test "set_front_matter_field updates an integer field" {
  set_front_matter_field "$TEST_FILE" "fix_count" "5"
  result="$(get_front_matter_field "$TEST_FILE" "fix_count")"
  [ "$result" = "5" ]
}

@test "set_front_matter_field does not corrupt other fields" {
  set_front_matter_field "$TEST_FILE" "status" "in_progress"
  [ "$(get_front_matter_field "$TEST_FILE" "priority")"  = "high" ]
  [ "$(get_front_matter_field "$TEST_FILE" "fix_count")" = "3" ]
  [ "$(get_front_matter_field "$TEST_FILE" "branch")"    = "ralph/task-07" ]
}

@test "set_front_matter_field preserves the task body after front matter" {
  set_front_matter_field "$TEST_FILE" "status" "done"
  body="$(tail -n +1 "$TEST_FILE" | sed -n '/^---$/,/^---$/!p' | grep -v '^---' | head -5)"
  echo "$body" | grep -q "Some content here."
}

@test "set_front_matter_field fails for a field that does not exist" {
  run set_front_matter_field "$TEST_FILE" "nonexistent_field" "value"
  [ "$status" -ne 0 ]
}
