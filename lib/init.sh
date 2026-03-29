#!/usr/bin/env bash
# init.sh — ralph_init(): guided prompt sequence to scaffold ralph.toml.
#
# Sourced by ralph.sh and by bats unit tests (with RALPH_TESTING=1).
#
# Expects SCRIPT_DIR to be set by the caller (ralph.sh or tests).

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

  echo ""
  echo "  build  Build command — leave empty if no build step. []"
  printf "  > "
  local build_value
  read -r build_value

  # ── Field 4: test ────────────────────────────────────────────────────────────

  echo ""
  echo "  test  Test command — required for Ralph to validate changes. []"
  printf "  > "
  local test_value
  read -r test_value

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
