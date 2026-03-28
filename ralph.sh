#!/bin/bash
# Ralph — Long-running Copilot CLI agent loop with bash-side mode routing
#
# Usage:
#   ./ralph.sh <max_iterations> [--label=<label>]
#
# Examples:
#   ./ralph.sh 20
#   ./ralph.sh 20 --label=foo-widget
#
# Each iteration:
#   1. Checks GitHub for open ralph PRs or open issues (in bash)
#   2. Determines which mode to run (implement, review, review-round2, fix,
#      force-approve, or merge)
#   3. Loads the mode-specific prompt from ralph/modes/<mode>.md
#   4. Substitutes {{REPO}}, {{PR_NUMBER}}, {{ISSUE_NUMBER}}, {{FEATURE_BRANCH}}
#      placeholders
#   5. Runs Copilot with that focused, self-contained prompt
#
# The loop stops early if Copilot emits <promise>COMPLETE</promise> or if
# bash routing finds no open PRs and no open issues.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}")")" && pwd)"
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WORKTREE_DIR="${GIT_ROOT%/*}/$(basename "$GIT_ROOT")-ralph-workspace"

# Modes: local project override (ralph/modes/) takes precedence over bundled modes.
if [[ -d "$GIT_ROOT/ralph/modes" ]]; then
  MODES_DIR="$GIT_ROOT/ralph/modes"
else
  MODES_DIR="$SCRIPT_DIR/modes"
fi

# Config: check ralph.toml at project root, then ralph/project.toml (legacy).
if [[ -f "$GIT_ROOT/ralph.toml" ]]; then
  CONFIG_FILE="$GIT_ROOT/ralph.toml"
elif [[ -f "$GIT_ROOT/ralph/project.toml" ]]; then
  CONFIG_FILE="$GIT_ROOT/ralph/project.toml"
else
  CONFIG_FILE=""
fi

# Parse a value from the config file by key name.
# Handles quoted strings (repo = "owner/repo") and unquoted values (build = "").
toml_get() {
  [[ -n "$CONFIG_FILE" ]] || return 0
  grep -E "^$1 *=" "$CONFIG_FILE" \
    | sed -E 's/^[^=]+= *"?([^"]*)"? *$/\1/'
}

BUILD_CMD=$(toml_get build)
TEST_CMD=$(toml_get test)
REPO=$(toml_get repo)

# Fall back to inferring the repo from the GitHub CLI.
if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
fi

UPSTREAM_REPO=$(toml_get upstream)
# Default to $REPO when upstream is not configured (personal project behaviour unchanged).
if [[ -z "$UPSTREAM_REPO" ]]; then
  UPSTREAM_REPO="$REPO"
fi

# Derive the fork owner from the owner prefix of $REPO (e.g. "you" from "you/project").
FORK_OWNER="${REPO%%/*}"

# ── Argument validation ────────────────────────────────────────────────────────

usage() {
  echo "Usage: $(basename "$0") <max_iterations> [--label=<label>] [--issue=<N>]"
  echo ""
  echo "  max_iterations  A positive integer — how many Copilot iterations to"
  echo "                  allow before giving up. There is no default; you must"
  echo "                  decide how many loops is reasonable for your task."
  echo ""
  echo "  --label=<label> Optional feature label. Derives FEATURE_BRANCH=feat/<label>"
  echo "                  and FEATURE_LABEL=prd/<label>. When omitted, FEATURE_BRANCH"
  echo "                  defaults to 'main'."
  echo ""
  echo "  --issue=<N>     Optional issue number. When set, Ralph skips normal issue"
  echo "                  routing and implements only that specific issue. After the"
  echo "                  issue is merged, Ralph exits cleanly without opening a"
  echo "                  feature PR."
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") 20"
  echo "  $(basename "$0") 20 --label=foo-widget"
  echo "  $(basename "$0") 20 --issue=82"
  echo "  $(basename "$0") 20 --issue=82 --label=foo-widget"
}

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage
  exit 1
fi

if ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
  usage
  exit 1
fi

MAX_ITERATIONS="$1"
FEATURE_LABEL=""
FEATURE_BRANCH="main"
PINNED_ISSUE=""

for arg in "${@:2}"; do
  if [[ "$arg" =~ ^--label=(.+)$ ]]; then
    FEATURE_LABEL="prd/${BASH_REMATCH[1]}"
    FEATURE_BRANCH="feat/${BASH_REMATCH[1]}"
  elif [[ "$arg" =~ ^--issue=([1-9][0-9]*)$ ]]; then
    PINNED_ISSUE="${BASH_REMATCH[1]}"
  else
    usage
    exit 1
  fi
done

# ── Preflight checks ───────────────────────────────────────────────────────────

if ! command -v copilot &>/dev/null; then
  echo "Error: 'copilot' not found in PATH. Install the GitHub Copilot CLI first."
  exit 1
fi

if [[ ! -d "$MODES_DIR" ]]; then
  echo "Error: Modes directory not found at $MODES_DIR"
  exit 1
fi

if [[ -z "$REPO" ]]; then
  echo "Error: Could not determine the GitHub repo. Add 'repo = \"owner/repo\"' to"
  echo "ralph.toml in your project root, or run from inside a GitHub repository."
  exit 1
fi

if [[ -z "$TEST_CMD" ]]; then
  echo "Error: No test command configured. Add 'test = \"your-test-cmd\"' to"
  echo "ralph.toml in your project root (create it from ~/.ralph/project.example.toml)."
  exit 1
fi

# In PRD mode (without a pinned issue), validate that either prd/* issues exist or
# the feature branch already exists on origin. If neither is true, the label is almost
# certainly a typo.
if [[ -n "$FEATURE_LABEL" && -z "$PINNED_ISSUE" ]]; then
  if PRD_ISSUE_COUNT=$(gh issue list --repo "$REPO" --state open \
      --label "$FEATURE_LABEL" \
      --json number --jq 'length' \
      < /dev/null 2>/dev/null); then
    if [[ "$PRD_ISSUE_COUNT" -eq 0 ]]; then
      if ! git -C "$GIT_ROOT" ls-remote --exit-code --heads origin "$FEATURE_BRANCH" > /dev/null 2>&1; then
        echo "Error: No open issues with label '${FEATURE_LABEL}' found, and branch 'origin/${FEATURE_BRANCH}' does not exist."
        echo "Check that --label matches an existing PRD label, or create the feature branch first."
        exit 1
      fi
    fi
  else
    echo "Warning: Could not reach GitHub API; skipping PRD preflight check."
  fi
fi

# If a specific issue is pinned, verify it exists and is not already closed.
if [[ -n "$PINNED_ISSUE" ]]; then
  PINNED_ISSUE_STATE=$(gh issue view "$PINNED_ISSUE" --repo "$REPO" --json state \
    --jq '.state' < /dev/null 2>/dev/null || echo "")
  if [[ -z "$PINNED_ISSUE_STATE" ]]; then
    echo "Error: Issue #${PINNED_ISSUE} not found in ${REPO}. Check the issue number."
    exit 1
  fi
  if [[ "$PINNED_ISSUE_STATE" == "CLOSED" ]]; then
    echo "Issue #${PINNED_ISSUE} is already closed. Nothing to do."
    exit 0
  fi
  export PINNED_ISSUE
fi

# ── Worktree setup ─────────────────────────────────────────────────────────────

# Remove the worktree on exit (clean finish, error, or Ctrl-C).
cleanup() {
  if git -C "$GIT_ROOT" worktree list | grep -q "$WORKTREE_DIR"; then
    echo ""
    echo "  Removing worktree at ${WORKTREE_DIR} …"
    git -C "$GIT_ROOT" worktree remove --force "$WORKTREE_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ -d "$WORKTREE_DIR" ]]; then
  echo ""
  echo "⚠️  A Ralph workspace already exists at:"
  echo "   $WORKTREE_DIR"
  echo ""
  echo "This usually means a previous run did not exit cleanly."
  echo "Remove it with:  git worktree remove --force $WORKTREE_DIR"
  exit 1
fi

echo ""
echo "  Creating worktree at ${WORKTREE_DIR} …"

# If a feature branch was specified and doesn't yet exist on origin, create it.
if [[ "$FEATURE_BRANCH" != "main" ]]; then
  if ! git -C "$GIT_ROOT" ls-remote --exit-code --heads origin "$FEATURE_BRANCH" > /dev/null 2>&1; then
    echo "  🌿 Branch origin/${FEATURE_BRANCH} not found — creating from origin/main and pushing…"
    git -C "$GIT_ROOT" fetch origin main > /dev/null
    git -C "$GIT_ROOT" push origin "origin/main:refs/heads/${FEATURE_BRANCH}"
    echo "  ✅  Branch ${FEATURE_BRANCH} created on origin."
  fi
fi

git -C "$GIT_ROOT" worktree add --detach "$WORKTREE_DIR" "origin/$FEATURE_BRANCH"

# ── Review backend detection & routing ────────────────────────────────────────

# shellcheck source=lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"

# Loads the mode file and substitutes {{REPO}}, {{PR_NUMBER}}, {{ISSUE_NUMBER}}.
build_prompt() {
  local mode_file="$MODES_DIR/$MODE.md"
  if [[ ! -f "$mode_file" ]]; then
    echo "  ❌  Mode file not found: $mode_file"
    exit 1
  fi

  PROMPT=$(cat "$mode_file")
  PROMPT="${PROMPT//\{\{REPO\}\}/$REPO}"
  PROMPT="${PROMPT//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
  PROMPT="${PROMPT//\{\{ISSUE_NUMBER\}\}/$ISSUE_NUMBER}"
  PROMPT="${PROMPT//\{\{BUILD_CMD\}\}/$BUILD_CMD}"
  PROMPT="${PROMPT//\{\{TEST_CMD\}\}/$TEST_CMD}"
  PROMPT="${PROMPT//\{\{FEATURE_BRANCH\}\}/$FEATURE_BRANCH}"
  PROMPT="${PROMPT//\{\{FEATURE_LABEL\}\}/$FEATURE_LABEL}"
  PROMPT="${PROMPT//\{\{REVIEW_BACKEND\}\}/$REVIEW_BACKEND}"
  PROMPT="${PROMPT//\{\{UPSTREAM_REPO\}\}/$UPSTREAM_REPO}"
  PROMPT="${PROMPT//\{\{FORK_OWNER\}\}/$FORK_OWNER}"
}

# ── Startup detection ─────────────────────────────────────────────────────────

detect_review_backend

# ── Main loop ──────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Ralph — Copilot agentic loop                                ║"
echo "║  Max iterations: $MAX_ITERATIONS$(printf '%*s' $((46 - ${#MAX_ITERATIONS})) '')║"
echo "╚══════════════════════════════════════════════════════════════╝"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  echo ""
  printf "\033[1;36m"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  🤖 Ralph — iteration $i / $MAX_ITERATIONS"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "\033[0m"

  # Update terminal tab/window title and tmux window name.
  printf "\033]0;🤖 Ralph — iteration %s / %s\007" "$i" "$MAX_ITERATIONS"
  printf "\033k🤖 Ralph %s/%s\033\\" "$i" "$MAX_ITERATIONS"

  MODE=""
  determine_mode

  # All done — no copilot needed
  if [[ "$MODE" == "complete" ]]; then
    echo ""
    printf "\033[1;32m"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅  Ralph completed all tasks at iteration $i / $MAX_ITERATIONS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "\033[0m"
    exit 0
  fi

  build_prompt

  OUTPUT=$(
    cd "$WORKTREE_DIR" && copilot \
      --prompt "$PROMPT" \
      --allow-all \
      --autopilot \
      2>&1 | tee /dev/stderr
  ) || true

  # Belt-and-suspenders COMPLETE check (bash routing handles this now, but
  # keep the signal detection in case a mode emits it unexpectedly)
  if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    printf "\033[1;32m"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅  Ralph completed all tasks at iteration $i / $MAX_ITERATIONS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "\033[0m"
    exit 0
  fi

  if echo "$OUTPUT" | grep -q "<promise>STOP</promise>"; then
    echo ""
    echo "  ✔  Iteration $i / $MAX_ITERATIONS done — restarting"
  fi

  echo ""
  echo "  Iteration $i done. $(( MAX_ITERATIONS - i )) iteration(s) remaining."
  sleep 2
done

# ── Max iterations reached ─────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ⚠️   Ralph reached the max of $MAX_ITERATIONS iteration(s) without"
echo "       receiving a completion signal."
echo ""
echo "  Options:"
echo "    • Run again with more iterations to continue"
echo "    • Tune ralph/modes/ if Copilot is going in the wrong direction"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 1
