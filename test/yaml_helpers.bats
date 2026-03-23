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

# ── review_notes: append_review_note / get_last_review_note / get_all_review_notes ──

setup_review_notes_file() {
  cat > "$TEST_FILE" <<'EOF'
---
status: needs_review
branch: ralph/task-07
fix_count: 0
review_notes: []
---

# Task body

Some content here.
EOF
}

@test "get_last_review_note returns empty string when review_notes is []" {
  setup_review_notes_file
  result="$(get_last_review_note "$TEST_FILE")"
  [ "$result" = "" ]
}

@test "append_review_note appends first entry to empty list" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "Missing null check on user input"
  result="$(get_last_review_note "$TEST_FILE")"
  [ "$result" = "Missing null check on user input" ]
}

@test "append_review_note appends second entry, get_last_review_note returns it" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "First issue: missing null check"
  append_review_note "$TEST_FILE" "Second issue: wrong status code"
  result="$(get_last_review_note "$TEST_FILE")"
  [ "$result" = "Second issue: wrong status code" ]
}

@test "append_review_note preserves first entry after two rounds" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "First issue: missing null check"
  append_review_note "$TEST_FILE" "Second issue: wrong status code"
  result="$(get_all_review_notes "$TEST_FILE")"
  echo "$result" | grep -q "First issue: missing null check"
  echo "$result" | grep -q "Second issue: wrong status code"
}

@test "get_all_review_notes labels entries with [Review N]" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "Entry one"
  append_review_note "$TEST_FILE" "Entry two"
  result="$(get_all_review_notes "$TEST_FILE")"
  echo "$result" | grep -q "\[Review 1\]"
  echo "$result" | grep -q "\[Review 2\]"
}

@test "append_review_note handles colons in note text without YAML corruption" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "src/auth.ts line 42: token expiry missing — returns 403 instead of 401"
  result="$(get_last_review_note "$TEST_FILE")"
  [ "$result" = "src/auth.ts line 42: token expiry missing — returns 403 instead of 401" ]
}

@test "append_review_note handles multi-line notes" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "$(printf 'Line one\nLine two\nLine three')"
  result="$(get_last_review_note "$TEST_FILE")"
  echo "$result" | grep -q "Line one"
  echo "$result" | grep -q "Line two"
  echo "$result" | grep -q "Line three"
}

@test "append_review_note does not corrupt other front matter fields" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "Some review note"
  [ "$(get_front_matter_field "$TEST_FILE" "status")"    = "needs_review" ]
  [ "$(get_front_matter_field "$TEST_FILE" "branch")"    = "ralph/task-07" ]
  [ "$(get_front_matter_field "$TEST_FILE" "fix_count")" = "0" ]
}

@test "append_review_note preserves task body" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "Some review note"
  grep -q "Some content here." "$TEST_FILE"
}

@test "two review rounds produce two entries in review_notes" {
  setup_review_notes_file
  append_review_note "$TEST_FILE" "Round 1: missing check"
  append_review_note "$TEST_FILE" "Round 2: fix incomplete"
  count=$(grep -c '  - |' "$TEST_FILE")
  [ "$count" -eq 2 ]
}
