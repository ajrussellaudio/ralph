#!/usr/bin/env bats
# test/toml_parser.bats — bats test suite for toml_get_array()

load 'test_helper'

setup() {
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── toml_get_array ───────────────────────────────────────────────────────────

@test "multi-line array with multiple items returns each item on a separate line" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
pre_commit = [
  "eslint .",
  "prettier --check .",
  "tsc --noEmit",
]
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "eslint ." ]
  [ "${lines[1]}" = "prettier --check ." ]
  [ "${lines[2]}" = "tsc --noEmit" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "single-line array returns each item" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
pre_commit = ["eslint .", "prettier --check ."]
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "eslint ." ]
  [ "${lines[1]}" = "prettier --check ." ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "empty array returns empty output" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
pre_commit = []
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "missing key returns empty output" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
repo = "owner/repo"
build = "make"
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "array with trailing comma parses correctly" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
pre_commit = [
  "eslint .",
  "prettier --check .",
]
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "eslint ." ]
  [ "${lines[1]}" = "prettier --check ." ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "array with varied whitespace parses correctly" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
pre_commit   =   [
    "eslint ."  ,
      "prettier --check ."  ,
  "tsc --noEmit"
  ]
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "eslint ." ]
  [ "${lines[1]}" = "prettier --check ." ]
  [ "${lines[2]}" = "tsc --noEmit" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "items containing spaces are preserved" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
pre_commit = ["eslint --fix .", "prettier --write --check ."]
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "eslint --fix ." ]
  [ "${lines[1]}" = "prettier --write --check ." ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "single-item array returns that one item" {
  CONFIG_FILE="$TEST_DIR/test.toml"
  cat > "$CONFIG_FILE" <<'EOF'
pre_commit = ["eslint ."]
EOF
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "eslint ." ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "CONFIG_FILE unset returns empty output" {
  CONFIG_FILE=""
  run toml_get_array pre_commit
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
