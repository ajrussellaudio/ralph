#!/usr/bin/env bash
# init.sh — ralph_init(): guided prompt sequence to scaffold ralph.toml.
#
# Sourced by ralph.sh and by bats unit tests (with RALPH_TESTING=1).
#
# Expects SCRIPT_DIR to be set by the caller (ralph.sh or tests).

# Detect project-type command suggestions for a given field ("build" or "test").
# Scans INIT_SCAN_DIR if set, otherwise PWD. Prints one suggestion per line.
_ralph_init_detect() {
  local field="$1"
  local scan_dir="${INIT_SCAN_DIR:-$PWD}"

  if [[ -f "$scan_dir/package.json" ]]; then
    [[ "$field" == "test" ]]  && echo "npm test"
    [[ "$field" == "build" ]] && echo "npm run build"
  fi

  if [[ -f "$scan_dir/go.mod" ]]; then
    [[ "$field" == "test" ]]  && echo "go test ./..."
    [[ "$field" == "build" ]] && echo "go build ./..."
  fi

  if [[ -f "$scan_dir/Makefile" ]]; then
    if [[ "$field" == "test" ]] && grep -q "^test:" "$scan_dir/Makefile"; then
      echo "make test"
    fi
    if [[ "$field" == "build" ]] && grep -q "^build:" "$scan_dir/Makefile"; then
      echo "make build"
    fi
  fi

  if [[ -f "$scan_dir/Cargo.toml" ]]; then
    [[ "$field" == "test" ]]  && echo "cargo test"
    [[ "$field" == "build" ]] && echo "cargo build"
  fi
}

# Prompt the user for a command field with optional detected suggestions.
# Suggestions are passed as positional args after label and desc.
# Sets global _RALPH_READ_VALUE to the resolved input.
_RALPH_READ_VALUE=""
_ralph_init_prompt() {
  local label="$1"
  local desc="$2"
  shift 2
  local suggestions=("$@")
  local count="${#suggestions[@]}"
  local input=""

  echo ""

  if [[ $count -eq 0 ]]; then
    echo "  $label  $desc []"
    printf "  > "
    read -r input
    _RALPH_READ_VALUE="$input"
  elif [[ $count -eq 1 ]]; then
    echo "  $label  $desc [${suggestions[0]}]"
    printf "  > "
    read -r input
    _RALPH_READ_VALUE="${input:-${suggestions[0]}}"
  else
    echo "  $label  $desc"
    local i
    for (( i=0; i<count; i++ )); do
      echo "    $((i+1))) ${suggestions[$i]}"
    done
    echo "    Or type a custom value. []"
    printf "  > "
    read -r input
    if [[ "$input" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= count )); then
      _RALPH_READ_VALUE="${suggestions[$((input-1))]}"
    else
      if [[ "$input" =~ ^[0-9]+$ ]]; then
        # Out-of-range number — fall back to first suggestion
        _RALPH_READ_VALUE="${suggestions[0]}"
      else
        _RALPH_READ_VALUE="${input:-${suggestions[0]}}"
      fi
    fi
  fi
}

ralph_init() {
  local rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$rule"
  echo "🚀 Ralph — init"
  echo "$rule"
  echo ""
  echo "  Let's configure your project. Press Enter to accept each default."
  echo ""

  # ── Field 1: repo ────────────────────────────────────────────────────────────

  local inferred_repo=""
  if command -v gh >/dev/null 2>&1; then
    inferred_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
  fi

  local repo_default="${inferred_repo:-}"
  if [[ -n "$repo_default" ]]; then
    echo "  repo  GitHub repo slug (owner/repo). [${repo_default}]"
  else
    echo "  repo  GitHub repo slug (owner/repo). []"
  fi
  printf "  > "
  local repo_value
  read -r repo_value
  if [[ -z "$repo_value" ]]; then
    repo_value="$repo_default"
  fi

  # ── Field 2: upstream ────────────────────────────────────────────────────────

  echo ""
  echo "  upstream  Upstream repo slug for fork workflows — Ralph does his work on"
  echo "            your fork but the final feature PR lands on the upstream repo."
  echo "            Leave blank for personal projects (defaults to repo). []"
  printf "  > "
  local upstream_value
  read -r upstream_value

  # ── Field 3: build ───────────────────────────────────────────────────────────

  local -a _build_sugs=()
  while IFS= read -r _line; do [[ -n "$_line" ]] && _build_sugs+=("$_line"); done \
    < <(_ralph_init_detect "build")
  _ralph_init_prompt "build" "Build command — leave empty if no build step." \
    "${_build_sugs[@]+"${_build_sugs[@]}"}"
  local build_value="$_RALPH_READ_VALUE"

  # ── Field 4: test ────────────────────────────────────────────────────────────

  local -a _test_sugs=()
  while IFS= read -r _line; do [[ -n "$_line" ]] && _test_sugs+=("$_line"); done \
    < <(_ralph_init_detect "test")
  _ralph_init_prompt "test" "Test command — required for Ralph to validate changes." \
    "${_test_sugs[@]+"${_test_sugs[@]}"}"
  local test_value="$_RALPH_READ_VALUE"

  # ── Sanitize values for TOML string interpolation (escape \ then ") ─────────

  local repo_safe="${repo_value//\\/\\\\}";         repo_safe="${repo_safe//\"/\\\"}"
  local upstream_safe="${upstream_value//\\/\\\\}"; upstream_safe="${upstream_safe//\"/\\\"}"
  local build_safe="${build_value//\\/\\\\}";       build_safe="${build_safe//\"/\\\"}"
  local test_safe="${test_value//\\/\\\\}";         test_safe="${test_safe//\"/\\\"}"

  # ── File preview ─────────────────────────────────────────────────────────────

  local file_contents
  file_contents=$(cat <<TOML
# Ralph project configuration
# Copy this file to ralph.toml at your project root and fill in the values.

# GitHub repo slug (owner/repo). Optional — Ralph infers it from \`gh repo view\`.
repo = "${repo_safe}"

# Upstream repo slug (owner/repo). Optional — for fork-based workflows where
# Ralph does all his work on your fork but the final feature PR should land on
# the upstream repo. Defaults to \`repo\` when not set (personal project behaviour
# unchanged).
upstream = "${upstream_safe}"

# Build command — leave empty if no build step.
build = "${build_safe}"

# Test command — required.
test = "${test_safe}"
TOML
)

  echo ""
  echo "$rule"
  echo "  📄  ralph.toml preview"
  echo "$rule"
  echo ""
  echo "$file_contents"
  echo ""
  echo "$rule"
  echo ""

  # ── Confirmation ─────────────────────────────────────────────────────────────

  printf "  Write this file? [Y/n] "
  local confirm_value
  read -r confirm_value

  if [[ "$confirm_value" =~ ^[Nn] ]]; then
    echo ""
    echo "  Aborted. No file written."
    return 0
  fi

  # ── Write file ───────────────────────────────────────────────────────────────

  local output_path="${INIT_OUTPUT_DIR:-$GIT_ROOT}/ralph.toml"

  if [[ -f "$output_path" ]]; then
    echo ""
    printf "  ⚠️  %s already exists. Overwrite? [y/N] " "$output_path"
    local overwrite_value
    read -r overwrite_value
    if [[ ! "$overwrite_value" =~ ^[Yy]$ ]]; then
      echo ""
      echo "  Aborted. Existing file kept."
      return 0
    fi
  fi

  printf '%s\n' "$file_contents" > "$output_path"

  echo ""
  echo "  ✅  Written: $output_path"
  echo ""

  # ── Post-write: call doctor or print nudge ───────────────────────────────────

  local doctor_lib="${SCRIPT_DIR:-}/lib/doctor.sh"
  if [[ -f "$doctor_lib" ]]; then
    # shellcheck source=lib/doctor.sh
    source "$doctor_lib"
    ralph_doctor || true
  else
    echo "  Run \`ralph doctor\` to validate your environment."
  fi
}
