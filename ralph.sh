#!/bin/bash
# Ralph — Long-running Copilot CLI agent loop with bash-side mode routing
#
# Usage:
#   ./ralph.sh [--max-iterations=N] [--label=<label>] [--issue=<N>]
#
# Examples:
#   ./ralph.sh --label=foo-widget
#   ./ralph.sh --max-iterations=20 --label=foo-widget
#   ./ralph.sh --max-iterations=20 --issue=82
#
# Each iteration:
#   1. Checks GitHub for open ralph PRs or open issues (in bash)
#   2. Determines which mode to run (implement, review, fix,
#      escalate, or merge)
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
    | sed -E 's/^[^=]+= *"?([^"]*)"? *$/\1/' || true
}

BUILD_CMD=$(toml_get build)
TEST_CMD=$(toml_get test)
REPO=$(toml_get repo)

# shellcheck source=lib/utils.sh
source "$SCRIPT_DIR/lib/utils.sh"

# Fall back to inferring the repo from the GitHub CLI.
if [[ -z "$REPO" ]]; then
  REPO=$(gh_with_retry repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "")
fi

UPSTREAM_REPO=$(toml_get upstream)
# Default to $REPO when upstream is not configured (personal project behaviour unchanged).
if [[ -z "$UPSTREAM_REPO" ]]; then
  UPSTREAM_REPO="$REPO"
fi

# Derive the fork owner from the owner prefix of $REPO (e.g. "you" from "you/project").
FORK_OWNER="${REPO%%/*}"

# ── Subcommand dispatch ────────────────────────────────────────────────────────

SUBCOMMAND=""
if [[ $# -eq 0 ]]; then
  SUBCOMMAND="status"
elif [[ "$1" == "run" ]]; then
  SUBCOMMAND="run"
  shift
elif [[ "$1" == "status" ]]; then
  SUBCOMMAND="status"
  shift
elif [[ "$1" == "doctor" ]]; then
  SUBCOMMAND="doctor"
  shift
elif [[ "$1" == "init" ]]; then
  SUBCOMMAND="init"
  shift
elif [[ "$1" =~ ^-- ]]; then
  echo "Error: '$1' requires a subcommand. Did you mean: ralph run $*"
  echo "Use 'ralph run' to start the agent loop."
  exit 1
else
  echo "Error: Unknown subcommand '$1'."
  echo ""
  echo "Usage: $(basename "$0") <subcommand> [flags]"
  echo ""
  echo "Subcommands:"
  echo "  run     Start the Copilot agent loop"
  echo "  status  Show status of the current feature"
  echo "  doctor  Check environment health"
  echo "  init    Scaffold a ralph.toml configuration file"
  exit 1
fi

# ── Status handler ─────────────────────────────────────────────────────────────

if [[ "$SUBCOMMAND" == "status" ]]; then
  FEATURE_LABEL=""
  FEATURE_BRANCH="main"
  PARENT_TICKET=""

  for arg in "$@"; do
    if [[ "$arg" =~ ^--label=(.+)$ ]]; then
      FEATURE_LABEL="prd/${BASH_REMATCH[1]}"
      FEATURE_BRANCH="feat/${BASH_REMATCH[1]}"
    elif [[ "$arg" =~ ^--ticket=([A-Z][A-Z0-9]*-[1-9][0-9]*)$ ]]; then
      # Stub-accept: JIRA backend wiring lands in a later slice.
      PARENT_TICKET="${BASH_REMATCH[1]}"
    elif [[ "$arg" =~ ^--ticket(=.*)?$ ]]; then
      echo "Error: --ticket value must look like KEY-NUMBER (e.g. CAPP-123)."
      echo "Usage: $(basename "$0") status [--label=<label>] [--ticket=<KEY-N>]"
      exit 1
    else
      echo "Usage: $(basename "$0") status [--label=<label>] [--ticket=<KEY-N>]"
      exit 1
    fi
  done

  # --ticket is mutually exclusive with --label (different task backends).
  if [[ -n "$PARENT_TICKET" && -n "$FEATURE_LABEL" ]]; then
    echo "Error: --ticket and --label are mutually exclusive (different task backends)."
    exit 1
  fi

  if [[ "${RALPH_PARSE_ONLY:-}" == "1" ]]; then
    echo "SUBCOMMAND=status"
    echo "FEATURE_BRANCH=${FEATURE_BRANCH}"
    exit 0
  fi

  # shellcheck source=lib/status.sh
  source "$SCRIPT_DIR/lib/status.sh"
  ralph_status
  exit 0
fi

# ── Doctor handler ─────────────────────────────────────────────────────────────

if [[ "$SUBCOMMAND" == "doctor" ]]; then
  if [[ "${RALPH_PARSE_ONLY:-}" == "1" ]]; then
    echo "SUBCOMMAND=doctor"
    exit 0
  fi

  # shellcheck source=lib/doctor.sh
  source "$SCRIPT_DIR/lib/doctor.sh"
  ralph_doctor
  exit $?
fi

# ── Init handler ───────────────────────────────────────────────────────────────

if [[ "$SUBCOMMAND" == "init" ]]; then
  if [[ "${RALPH_PARSE_ONLY:-}" == "1" ]]; then
    echo "SUBCOMMAND=init"
    exit 0
  fi

  # shellcheck source=lib/init.sh
  source "$SCRIPT_DIR/lib/init.sh"
  ralph_init
  exit $?
fi

# ── Argument validation (run subcommand) ───────────────────────────────────────

usage() {
  echo "Usage: $(basename "$0") run [--max-iterations=N] [--label=<label>] [--issue=<N>] [--ticket=<KEY-N>]"
  echo ""
  echo "  --max-iterations=N  Optional positive integer — how many Copilot iterations"
  echo "                      to allow before giving up. When omitted, Ralph runs"
  echo "                      indefinitely until a clean exit condition is reached."
  echo ""
  echo "  --label=<label>     Optional feature label. Derives FEATURE_BRANCH=feat/<label>"
  echo "                      and FEATURE_LABEL=prd/<label>. When omitted, FEATURE_BRANCH"
  echo "                      defaults to 'main'."
  echo ""
  echo "  --issue=<N>         Optional issue number. When set, Ralph skips normal issue"
  echo "                      routing and implements only that specific issue. After the"
  echo "                      issue is merged, Ralph exits cleanly without opening a"
  echo "                      feature PR."
  echo ""
  echo "  --ticket=<KEY-N>    Optional JIRA ticket reference (e.g. CAPP-123). Switches"
  echo "                      Ralph's task backend to JIRA. Mutually exclusive with"
  echo "                      --label and --issue."
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") run"
  echo "  $(basename "$0") run --label=foo-widget"
  echo "  $(basename "$0") run --max-iterations=20 --label=foo-widget"
  echo "  $(basename "$0") run --max-iterations=20 --issue=82 --label=foo-widget"
  echo "  $(basename "$0") run --ticket=CAPP-123"
}

MAX_ITERATIONS=""
FEATURE_LABEL=""
FEATURE_BRANCH="main"
PINNED_ISSUE=""
PARENT_TICKET=""
PROJECT_KEY=""
TASK_BACKEND="github"

for arg in "$@"; do
  if [[ "$arg" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: The positional <max_iterations> argument has been removed. Use --max-iterations=N instead."
    exit 1
  elif [[ "$arg" =~ ^--max-iterations=([1-9][0-9]*)$ ]]; then
    MAX_ITERATIONS="${BASH_REMATCH[1]}"
  elif [[ "$arg" =~ ^--max-iterations(=.*)?$ ]]; then
    usage
    exit 1
  elif [[ "$arg" =~ ^--label=(.+)$ ]]; then
    FEATURE_LABEL="prd/${BASH_REMATCH[1]}"
    FEATURE_BRANCH="feat/${BASH_REMATCH[1]}"
  elif [[ "$arg" =~ ^--issue=([1-9][0-9]*)$ ]]; then
    PINNED_ISSUE="${BASH_REMATCH[1]}"
  elif [[ "$arg" =~ ^--ticket=([A-Z][A-Z0-9]*-[1-9][0-9]*)$ ]]; then
    PARENT_TICKET="${BASH_REMATCH[1]}"
    PROJECT_KEY="${PARENT_TICKET%%-*}"
    TASK_BACKEND="jira"
  elif [[ "$arg" =~ ^--ticket(=.*)?$ ]]; then
    echo "Error: --ticket value must look like KEY-NUMBER (e.g. CAPP-123)."
    usage
    exit 1
  else
    usage
    exit 1
  fi
done

# --ticket is mutually exclusive with --label and --issue (different task backends).
if [[ -n "$PARENT_TICKET" ]]; then
  if [[ -n "$FEATURE_LABEL" ]]; then
    echo "Error: --ticket and --label are mutually exclusive (different task backends)."
    exit 1
  fi
  if [[ -n "$PINNED_ISSUE" ]]; then
    echo "Error: --ticket and --issue are mutually exclusive (different task backends)."
    exit 1
  fi
fi

# Test hook: exit 0 after successful arg parsing so bats tests can verify
# arg handling without requiring a full preflight environment.
if [[ "${RALPH_PARSE_ONLY:-}" == "1" ]]; then
  echo "MAX_ITERATIONS=${MAX_ITERATIONS}"
  echo "FEATURE_BRANCH=${FEATURE_BRANCH}"
  echo "PINNED_ISSUE=${PINNED_ISSUE}"
  echo "PARENT_TICKET=${PARENT_TICKET}"
  echo "PROJECT_KEY=${PROJECT_KEY}"
  echo "TASK_BACKEND=${TASK_BACKEND}"
  exit 0
fi

export TASK_BACKEND PARENT_TICKET PROJECT_KEY

# In JIRA mode, derive the feature branch from the parent ticket.
if [[ "$TASK_BACKEND" == "jira" ]]; then
  FEATURE_BRANCH=$(jira_feature_branch "$PARENT_TICKET")
fi

# Derive the worktree path. Include a unique slug when running against a
# feature branch so multiple ralph runs can coexist in parallel on the same machine.
if [[ "$TASK_BACKEND" == "jira" ]]; then
  WORKTREE_DIR="${GIT_ROOT%/*}/$(basename "$GIT_ROOT")-ralph-$(printf '%s' "$PARENT_TICKET" | tr '[:upper:]' '[:lower:]')"
elif [[ -n "$FEATURE_LABEL" ]]; then
  WORKTREE_DIR="${GIT_ROOT%/*}/$(basename "$GIT_ROOT")-ralph-${FEATURE_BRANCH#feat/}"
else
  WORKTREE_DIR="${GIT_ROOT%/*}/$(basename "$GIT_ROOT")-ralph-workspace"
fi

# ── Preflight checks (via ralph_doctor) ───────────────────────────────────────

# shellcheck source=lib/doctor.sh
source "$SCRIPT_DIR/lib/doctor.sh"
if ! ralph_doctor; then
  exit 1
fi

# In PRD mode (without a pinned issue), validate that either prd/* issues exist or
# the feature branch already exists on origin. If neither is true, the label is almost
# certainly a typo.
if [[ -n "$FEATURE_LABEL" && -z "$PINNED_ISSUE" ]]; then
  if PRD_ISSUE_COUNT=$(gh_with_retry issue list --repo "$REPO" --state open \
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

# In JIRA mode, validate the parent ticket exists OR the feature branch is
# already on origin. A typo'd ticket key fails fast here with a clear error.
if [[ "$TASK_BACKEND" == "jira" ]]; then
  if jira_with_retry issue view "$PARENT_TICKET" --plain --no-headers --columns key < /dev/null > /dev/null 2>&1; then
    : # parent ticket exists
  elif git -C "$GIT_ROOT" ls-remote --exit-code --heads origin "$FEATURE_BRANCH" > /dev/null 2>&1; then
    echo "  ℹ  JIRA ticket ${PARENT_TICKET} not reachable, but feature branch origin/${FEATURE_BRANCH} exists — continuing."
  else
    echo "Error: JIRA ticket '${PARENT_TICKET}' not found, and branch 'origin/${FEATURE_BRANCH}' does not exist."
    echo "Check that --ticket matches an existing JIRA issue key."
    exit 1
  fi
fi

# If a specific issue is pinned, verify it exists and is not already closed.
if [[ -n "$PINNED_ISSUE" ]]; then
  PINNED_ISSUE_STATE=$(gh_with_retry issue view "$PINNED_ISSUE" --repo "$REPO" --json state \
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

    git -C "$GIT_ROOT" fetch origin "$FEATURE_BRANCH" > /dev/null
  fi
fi

git -C "$GIT_ROOT" worktree add --detach "$WORKTREE_DIR" "origin/$FEATURE_BRANCH"

# ── Review backend detection & routing ────────────────────────────────────────

# shellcheck source=lib/routing.sh
source "$SCRIPT_DIR/lib/routing.sh"

# Loads the mode file and substitutes {{REPO}}, {{PR_NUMBER}}, {{ISSUE_NUMBER}}.
build_prompt() {
  local mode_file=""
  if [[ "${TASK_BACKEND:-github}" == "jira" && -f "$MODES_DIR/jira/$MODE.md" ]]; then
    mode_file="$MODES_DIR/jira/$MODE.md"
  elif [[ -f "$MODES_DIR/$MODE.md" ]]; then
    mode_file="$MODES_DIR/$MODE.md"
  else
    echo "  ❌  Mode file not found: $MODES_DIR/$MODE.md"
    exit 1
  fi

  # Pre-resolve the PR branch name so mode files don't need to look it up.
  local pr_branch=""
  if [[ -n "$PR_NUMBER" ]]; then
    pr_branch=$(gh_with_retry pr view "$PR_NUMBER" --repo "$REPO" \
      --json headRefName --jq '.headRefName' < /dev/null 2>/dev/null || echo "")
  fi

  # Build the feature-pr section: tells Copilot whether to create or promote.
  local feature_pr_section=""
  if [[ -n "${FEATURE_PR_NUMBER:-}" ]]; then
    feature_pr_section="A draft PR (#${FEATURE_PR_NUMBER}) already exists. You will update and promote it in Step 2."
  else
    feature_pr_section="No existing PR. You will create a new one in Step 2."
  fi

  # Derive JIRA-specific placeholders from TASK_TYPE/TASK_SUMMARY when available.
  local task_slug="" branch_prefix=""
  if [[ "${TASK_BACKEND:-github}" == "jira" ]]; then
    task_slug=$(jira_kebab_summary "${TASK_SUMMARY:-}")
    branch_prefix=$(jira_branch_prefix "${TASK_TYPE:-}")
  fi

  PROMPT=$(cat "$mode_file")
  PROMPT="${PROMPT//\{\{REPO\}\}/$REPO}"
  PROMPT="${PROMPT//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
  PROMPT="${PROMPT//\{\{PR_BRANCH\}\}/$pr_branch}"
  PROMPT="${PROMPT//\{\{ISSUE_NUMBER\}\}/$ISSUE_NUMBER}"
  PROMPT="${PROMPT//\{\{BUILD_CMD\}\}/$BUILD_CMD}"
  PROMPT="${PROMPT//\{\{TEST_CMD\}\}/$TEST_CMD}"
  PROMPT="${PROMPT//\{\{FEATURE_BRANCH\}\}/$FEATURE_BRANCH}"
  PROMPT="${PROMPT//\{\{FEATURE_LABEL\}\}/$FEATURE_LABEL}"
  PROMPT="${PROMPT//\{\{REVIEW_BACKEND\}\}/$REVIEW_BACKEND}"
  PROMPT="${PROMPT//\{\{UPSTREAM_REPO\}\}/$UPSTREAM_REPO}"
  PROMPT="${PROMPT//\{\{FORK_OWNER\}\}/$FORK_OWNER}"
  PROMPT="${PROMPT//\{\{FEATURE_PR_NUMBER\}\}/${FEATURE_PR_NUMBER:-}}"
  PROMPT="${PROMPT//\{\{FEATURE_PR_SECTION\}\}/$feature_pr_section}"
  PROMPT="${PROMPT//\{\{TASK_BACKEND\}\}/${TASK_BACKEND:-github}}"
  PROMPT="${PROMPT//\{\{PARENT_TICKET\}\}/${PARENT_TICKET:-}}"
  PROMPT="${PROMPT//\{\{PROJECT_KEY\}\}/${PROJECT_KEY:-}}"
  PROMPT="${PROMPT//\{\{TASK_ID\}\}/${TASK_ID:-}}"
  PROMPT="${PROMPT//\{\{TASK_SLUG\}\}/$task_slug}"
  PROMPT="${PROMPT//\{\{BRANCH_PREFIX\}\}/$branch_prefix}"
}

# ── Post-merge bookkeeping ────────────────────────────────────────────────────

# shellcheck source=lib/cleanup.sh
source "$SCRIPT_DIR/lib/cleanup.sh"

# ── Startup detection ─────────────────────────────────────────────────────────

detect_review_backend

# ── Main loop ──────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Ralph — Copilot agentic loop                                ║"
if [[ -n "$MAX_ITERATIONS" ]]; then
  echo "║  Max iterations: $MAX_ITERATIONS$(printf '%*s' $((46 - ${#MAX_ITERATIONS})) '')║"
else
  echo "║  Max iterations: unlimited                                   ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"

run_loop() {
  local i="$1"
  echo ""
  printf "\033[1;36m"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ -n "$MAX_ITERATIONS" ]]; then
    echo "  🤖 Ralph — iteration $i / $MAX_ITERATIONS"
  else
    echo "  🤖 Ralph — iteration $i"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "\033[0m"

  # Update terminal tab/window title and tmux window name.
  if [[ -n "$MAX_ITERATIONS" ]]; then
    printf "\033]0;🤖 Ralph — iteration %s / %s\007" "$i" "$MAX_ITERATIONS"
    printf "\033k🤖 Ralph %s/%s\033\\" "$i" "$MAX_ITERATIONS"
  else
    printf "\033]0;🤖 Ralph — iteration %s\007" "$i"
    printf "\033k🤖 Ralph %s\033\\" "$i"
  fi

  MODE=""
  determine_mode

  # All done — no copilot needed
  if [[ "$MODE" == "complete" ]]; then
    echo ""
    printf "\033[1;32m"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ -n "$MAX_ITERATIONS" ]]; then
      echo "  ✅  Ralph completed all tasks at iteration $i / $MAX_ITERATIONS"
    else
      echo "  ✅  Ralph completed all tasks at iteration $i"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "\033[0m"
    exit 0
  fi

  build_prompt

  # In JIRA mode, transition the ticket to "In Progress" before invoking Copilot
  # for the implement step.
  if [[ "${TASK_BACKEND:-github}" == "jira" && "$MODE" == "implement" && -n "${TASK_ID:-}" ]]; then
    echo "  🎫 Transitioning ${TASK_ID} → In Progress"
    jira_transition "$TASK_ID" "In Progress" > /dev/null 2>&1 || \
      echo "  ⚠️  Could not transition ${TASK_ID} (continuing anyway)"
  fi

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
    if [[ -n "$MAX_ITERATIONS" ]]; then
      echo "  ✅  Ralph completed all tasks at iteration $i / $MAX_ITERATIONS"
    else
      echo "  ✅  Ralph completed all tasks at iteration $i"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "\033[0m"
    exit 0
  fi

  if echo "$OUTPUT" | grep -q "<promise>STOP</promise>"; then
    if [[ "$MODE" == "merge" ]]; then
      post_merge_cleanup "$PR_NUMBER"
    fi
    echo ""
    if [[ -n "$MAX_ITERATIONS" ]]; then
      echo "  ✔  Iteration $i / $MAX_ITERATIONS done — restarting"
    else
      echo "  ✔  Iteration $i done — restarting"
    fi
  fi

  if [[ -n "$MAX_ITERATIONS" ]]; then
    echo ""
    echo "  Iteration $i done. $(( MAX_ITERATIONS - i )) iteration(s) remaining."
  fi
  sleep 2
}

if [[ -n "$MAX_ITERATIONS" ]]; then
  for i in $(seq 1 "$MAX_ITERATIONS"); do
    run_loop "$i"
  done
else
  i=0
  while true; do
    i=$(( i + 1 ))
    run_loop "$i"
  done
fi

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
