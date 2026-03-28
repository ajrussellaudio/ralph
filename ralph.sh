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

# ── Argument validation ────────────────────────────────────────────────────────

usage() {
  echo "Usage: $(basename "$0") <max_iterations> [--label=<label>]"
  echo ""
  echo "  max_iterations  A positive integer — how many Copilot iterations to"
  echo "                  allow before giving up. There is no default; you must"
  echo "                  decide how many loops is reasonable for your task."
  echo ""
  echo "  --label=<label> Optional feature label. Derives FEATURE_BRANCH=feat/<label>"
  echo "                  and FEATURE_LABEL=prd/<label>. When omitted, FEATURE_BRANCH"
  echo "                  defaults to 'main'."
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") 20"
  echo "  $(basename "$0") 20 --label=foo-widget"
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
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

if [[ $# -eq 2 ]]; then
  if [[ "$2" =~ ^--label=(.+)$ ]]; then
    FEATURE_LABEL="prd/${BASH_REMATCH[1]}"
    FEATURE_BRANCH="feat/${BASH_REMATCH[1]}"
  else
    usage
    exit 1
  fi
fi

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

# In PRD mode, validate that either prd/* issues exist or the feature branch already
# exists on origin. If neither is true, the label is almost certainly a typo.
if [[ -n "$FEATURE_LABEL" ]]; then
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

# ── Review backend detection ───────────────────────────────────────────────────

# Queries the GitHub API for apps installed on the repo and sets REVIEW_BACKEND
# to 'copilot' if copilot-pull-request-reviewer is present, otherwise 'comments'.
# Defaults to 'comments' if the API call fails for any reason.
detect_review_backend() {
  echo "  🔍 Detecting review backend…"

  local found
  found=$(gh api "/repos/${REPO}/apps" \
    --jq '[.[].slug] | any(. == "copilot-pull-request-reviewer")' 2>/dev/null || echo "false")

  if [[ "$found" == "true" ]]; then
    REVIEW_BACKEND="copilot"
    echo "  🤖 Review backend: copilot"
  else
    REVIEW_BACKEND="comments"
    echo "  💬 Review backend: comments"
  fi

  export REVIEW_BACKEND
}

# ── Routing ────────────────────────────────────────────────────────────────────

# Populates MODE, PR_NUMBER, ISSUE_NUMBER based on current GitHub state.
# MODE is one of: implement | review | review-round2 | fix | force-approve | merge | complete
determine_mode() {
  PR_NUMBER=""
  ISSUE_NUMBER=""

  echo "  🔄 Syncing workspace…"
  (cd "$WORKTREE_DIR" && git fetch origin && git reset --hard "origin/$FEATURE_BRANCH") > /dev/null 2>&1

  echo "  🔍 Checking for open ralph PRs in ${REPO}…"
  OPEN_RALPH_PRS=$(gh pr list --repo "$REPO" --state open \
    --base "$FEATURE_BRANCH" \
    --json number,headRefName \
    --jq '[.[] | select(.headRefName | startswith("ralph/issue-"))] | sort_by(.number)' \
    < /dev/null 2>/dev/null || echo "[]")

  PR_COUNT=$(echo "$OPEN_RALPH_PRS" | jq length)

  if [[ "$PR_COUNT" -gt 0 ]]; then
    PR_NUMBER=$(echo "$OPEN_RALPH_PRS" | jq -r '.[0].number')

    if [[ "$REVIEW_BACKEND" == "copilot" ]]; then
      # Copilot bot review path: query review state instead of HTML comment sentinels.
      COPILOT_FIX_COMMENTS=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
        --json comments \
        --jq '[.comments[] | select(.body | contains("<!-- RALPH-FIX-BOT: RESPONSE -->"))]' \
        < /dev/null 2>/dev/null || echo "[]")

      FIX_COUNT=$(echo "$COPILOT_FIX_COMMENTS" | jq 'length')
      LAST_FIX_TIME=$(echo "$COPILOT_FIX_COMMENTS" | jq -r 'last | .createdAt // ""')

      COPILOT_REVIEW_JSON=$(gh api "/repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
        --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | last | {state: (.state // ""), submitted_at: (.submitted_at // "")}' \
        < /dev/null 2>/dev/null || echo '{"state":"","submitted_at":""}')

      COPILOT_REVIEW_STATE=$(echo "$COPILOT_REVIEW_JSON" | jq -r '.state')
      LAST_BOT_REVIEW_TIME=$(echo "$COPILOT_REVIEW_JSON" | jq -r '.submitted_at')

      if [[ -z "$COPILOT_REVIEW_STATE" ]]; then
        MODE="wait"
      elif [[ "$COPILOT_REVIEW_STATE" == "APPROVED" ]]; then
        MODE="merge"
      elif [[ "$COPILOT_REVIEW_STATE" == "CHANGES_REQUESTED" ]]; then
        # If a fix-bot response was posted after the last review, treat the old
        # review as addressed and wait for a new one.
        if [[ -n "$LAST_FIX_TIME" && "$LAST_FIX_TIME" > "$LAST_BOT_REVIEW_TIME" ]]; then
          MODE="wait"
        elif [[ "${FIX_COUNT:-0}" -lt 10 ]]; then
          MODE="fix-bot"
        elif [[ -f "${MODES_DIR}/escalate.md" ]]; then
          MODE="escalate"
        else
          echo "  ⚠️  FIX_COUNT >= 10 but modes/escalate.md not found — falling back to wait"
          MODE="wait"
        fi
      else
        # COMMENTED or other non-terminal state — review not yet complete
        MODE="wait"
      fi
    else
      # HTML comment sentinel path (existing logic).
      COMMENT_BODIES=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
        --json comments --jq '[.comments[].body] | join("\n---\n")' \
        < /dev/null 2>/dev/null || echo "")

      APPROVED=$(echo "$COMMENT_BODIES" | grep -c "RALPH-REVIEW: APPROVED" 2>/dev/null || true)
      CHANGES_REQUESTED=$(echo "$COMMENT_BODIES" | grep -c "RALPH-REVIEW: REQUEST_CHANGES" 2>/dev/null || true)

      if [[ "${APPROVED:-0}" -gt 0 ]]; then
        MODE="merge"
      elif [[ "${CHANGES_REQUESTED:-0}" -ge 2 ]]; then
        MODE="force-approve"
      elif [[ "${CHANGES_REQUESTED:-0}" -eq 1 ]]; then
        # If commits were pushed after the REQUEST_CHANGES comment → round 2 review
        # Otherwise → fix mode (no new commits yet)
        LAST_RC_TIME=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
          --json comments \
          --jq '[.comments[] | select(.body | contains("RALPH-REVIEW: REQUEST_CHANGES"))] | last | .createdAt // ""' \
          < /dev/null 2>/dev/null || echo "")
        LATEST_COMMIT_TIME=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
          --json commits \
          --jq '.commits | last | .committedDate // ""' \
          < /dev/null 2>/dev/null || echo "")

        if [[ -n "$LATEST_COMMIT_TIME" && -n "$LAST_RC_TIME" && "$LATEST_COMMIT_TIME" > "$LAST_RC_TIME" ]]; then
          MODE="review-round2"
        else
          MODE="fix"
        fi
      else
        MODE="review"
      fi
    fi

    echo "  ▶  Mode: $MODE  (PR #$PR_NUMBER)"
  else
    echo "  🔍 No open ralph PRs — checking issues…"

    # Pick highest-priority open issue: high-priority label first, then lowest number.
    # PRD mode: --label scopes to prd/<label>; exclude the PRD issue itself (prd) and blocked.
    # Standalone mode: no label filter; additionally exclude any issue carrying a prd/* label.
    if [[ -n "$FEATURE_LABEL" ]]; then
      ISSUE_NUMBER=$(gh issue list --repo "$REPO" --state open \
        --label "$FEATURE_LABEL" \
        --json number,labels --limit 100 \
        --jq '
          [.[] | select(.labels | map(.name) | (any(. == "prd") or any(. == "blocked")) | not)]
          | (
              (map(select(.labels | map(.name) | any(. == "high priority"))) | sort_by(.number) | first)
              // (sort_by(.number) | first)
            )
          | .number // empty
        ' \
        < /dev/null 2>/dev/null || echo "")
    else
      ISSUE_NUMBER=$(gh issue list --repo "$REPO" --state open \
        --json number,labels --limit 100 \
        --jq '
          [.[] | select(.labels | map(.name) | (any(. == "prd") or any(startswith("prd/")) or any(. == "blocked")) | not)]
          | (
              (map(select(.labels | map(.name) | any(. == "high priority"))) | sort_by(.number) | first)
              // (sort_by(.number) | first)
            )
          | .number // empty
        ' \
        < /dev/null 2>/dev/null || echo "")
    fi

    if [[ -n "$ISSUE_NUMBER" ]]; then
      MODE="implement"
      echo "  ▶  Mode: $MODE  (Issue #$ISSUE_NUMBER)"
    elif [[ -n "$FEATURE_LABEL" && "$FEATURE_BRANCH" != "main" ]]; then
      # PRD mode with no remaining task issues — check for an existing feat→main PR
      FEATURE_PR_COUNT=$(gh pr list --repo "$REPO" --state open \
        --base "main" \
        --head "$FEATURE_BRANCH" \
        --json number --jq 'length' \
        < /dev/null 2>/dev/null)

      if [[ "$FEATURE_PR_COUNT" == "0" ]]; then
        MODE="feature-pr"
        echo "  ▶  Mode: $MODE  (all task issues closed, opening feat→main PR)"
      else
        MODE="complete"
        echo "  ▶  Mode: $MODE  (feat→main PR already open or check failed)"
      fi
    else
      MODE="complete"
      echo "  ▶  Mode: $MODE  (no open issues or PRs)"
    fi
  fi
}

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
