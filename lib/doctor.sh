#!/usr/bin/env bash
# doctor.sh — ralph_doctor(): audit the environment and report health checks.
#
# Sourced by ralph.sh and by bats unit tests (with RALPH_TESTING=1).
#
# Expects MODES_DIR and (optionally) CONFIG_FILE to be set by the caller.
# All 9 checks always run to completion regardless of earlier failures.
# Exits 0 if no hard failures occurred; exits 1 if any hard failure was found.

ralph_doctor() {
  local rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$rule"
  echo "🩺 Ralph — doctor"
  echo "$rule"
  echo ""

  local hard_fail=0

  # ── Hard failure checks ─────────────────────────────────────────────────────

  # 1. copilot in PATH
  if command -v copilot >/dev/null 2>&1; then
    echo "  ✅  copilot found in PATH"
  else
    echo "  ❌  copilot not found in PATH"
    echo "     → install the GitHub Copilot CLI"
    hard_fail=1
  fi

  # 2. gh in PATH
  if command -v gh >/dev/null 2>&1; then
    echo "  ✅  gh found in PATH"
  else
    echo "  ❌  gh not found in PATH"
    echo "     → install the GitHub CLI"
    hard_fail=1
  fi

  # 3. gh authenticated (only checked when gh is present; missing-gh already reported above)
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      echo "  ✅  gh is authenticated"
    else
      echo "  ❌  gh is not authenticated"
      echo "     → run gh auth login"
      hard_fail=1
    fi
  fi

  # 4. GitHub repo resolvable (only when gh is present; missing-gh already reported above)
  if command -v gh >/dev/null 2>&1; then
    local resolved_repo="${REPO:-}"
    if [[ -z "$resolved_repo" ]]; then
      resolved_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
    fi
    # Validate the repo actually exists on GitHub, whether set explicitly or inferred.
    if [[ -n "$resolved_repo" ]] && gh repo view "$resolved_repo" >/dev/null 2>&1; then
      echo "  ✅  GitHub repo resolvable: $resolved_repo"
    else
      echo "  ❌  GitHub repo not resolvable"
      echo "     → set REPO in ralph.toml or run from a git repo"
      hard_fail=1
    fi
  fi

  # 5. Modes directory present
  if [[ -d "${MODES_DIR:-}" ]]; then
    echo "  ✅  modes directory found"
  else
    echo "  ❌  modes directory missing"
    echo "     → re-clone or reinstall Ralph"
    hard_fail=1
  fi

  # ── Warning checks ──────────────────────────────────────────────────────────

  # 6. ralph.toml present
  if [[ -n "${CONFIG_FILE:-}" && -f "${CONFIG_FILE:-}" ]]; then
    echo "  ✅  ralph.toml present"
  else
    echo "  ⚠️   ralph.toml absent"
    echo "     → copy from project.example.toml"
  fi

  # 7. test command in ralph.toml
  local test_cmd="${TEST_CMD:-}"
  if [[ -n "$test_cmd" ]]; then
    echo "  ✅  test command configured"
  else
    echo "  ⚠️   test command missing from ralph.toml"
    echo "     → add test = \"...\" to ralph.toml"
  fi

  # 8. build command in ralph.toml
  local build_cmd="${BUILD_CMD:-}"
  if [[ -n "$build_cmd" ]]; then
    echo "  ✅  build command configured"
  else
    echo "  ⚠️   build command missing from ralph.toml"
    echo "     → add build = \"...\" to ralph.toml if a build step is needed"
  fi

  # 9. GitHub API reachable (only when gh is present; missing-gh already reported above)
  if command -v gh >/dev/null 2>&1; then
    if gh api /rate_limit >/dev/null 2>&1; then
      echo "  ✅  GitHub API reachable"
    else
      echo "  ⚠️   GitHub API unreachable"
      echo "     → check network connectivity"
    fi
  fi

  echo ""
  if [[ "$hard_fail" -eq 0 ]]; then
    echo "  All checks passed."
    return 0
  else
    echo "  Doctor found issues — check the hints above."
    return 1
  fi
}
