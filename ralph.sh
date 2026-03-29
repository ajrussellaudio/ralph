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
    | sed -E 's/^[^=]+= *"?([^"]*)"? *$/\1/' || true
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
  exit 1
fi

# ── Status handler ─────────────────────────────────────────────────────────────

if [[ "$SUBCOMMAND" == "status" ]]; then
  FEATURE_LABEL=""
  FEATURE_BRANCH="main"

  for arg in "$@"; do
    if [[ "$arg" =~ ^--label=(.+)$ ]]; then
      FEATURE_LABEL="prd/${BASH_REMATCH[1]}"
      FEATURE_BRANCH="feat/${BASH_REMATCH[1]}"
    else
      echo "Usage: $(basename "$0") status [--label=<label>]"
      exit 1
    fi
  done

  if [[ "${RALPH_PARSE_ONLY:-}" == "1" ]]; then
    echo "SUBCOMMAND=status"
    echo "FEATURE_BRANCH=${FEATURE_BRANCH}"
    exit 0
  fi

  echo "ralph status: not yet implemented"
  exit 0
fi

# ── Argument validation (run subcommand) ───────────────────────────────────────

usage() {
  echo "Usage: $(basename "$0") run [--max-iterations=N] [--label=<label>] [--issue=<N>]"
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
  echo "Examples:"
  echo "  $(basename "$0") run"
  echo "  $(basename "$0") run --label=foo-widget"
  echo "  $(basename "$0") run --max-iterations=20 --label=foo-widget"
  echo "  $(basename "$0") run --max-iterations=20 --issue=82 --label=foo-widget"
}

MAX_ITERATIONS=""
FEATURE_LABEL=""
FEATURE_BRANCH="main"
PINNED_ISSUE=""

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
  else
    usage
    exit 1
  fi
done

# Test hook: exit 0 after successful arg parsing so bats tests can verify
# arg handling without requiring a full preflight environment.
if [[ "${RALPH_PARSE_ONLY:-}" == "1" ]]; then
  echo "MAX_ITERATIONS=${MAX_ITERATIONS}"
  echo "FEATURE_BRANCH=${FEATURE_BRANCH}"
  echo "PINNED_ISSUE=${PINNED_ISSUE}"
  exit 0
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

    # Push an empty init commit so GitHub allows PR creation and work-start is visible.
    git -C "$GIT_ROOT" fetch origin "$FEATURE_BRANCH" > /dev/null
    PARENT_SHA=$(git -C "$GIT_ROOT" rev-parse "origin/${FEATURE_BRANCH}")
    TREE_SHA=$(git -C "$GIT_ROOT" rev-parse "origin/${FEATURE_BRANCH}^{tree}")
    EMPTY_COMMIT=$(git -C "$GIT_ROOT" commit-tree "$TREE_SHA" -p "$PARENT_SHA" -m "chore: initialise ${FEATURE_BRANCH}")
    git -C "$GIT_ROOT" push origin "${EMPTY_COMMIT}:refs/heads/${FEATURE_BRANCH}" > /dev/null
    git -C "$GIT_ROOT" fetch origin "$FEATURE_BRANCH" > /dev/null
    echo "  📝  Empty init commit pushed."

    # Open a draft PR so the developer has instant visibility that work has started.
    DRAFT_PR_BODY="🤖 Ralph is working on this feature. This PR will be updated when all tasks are complete."
    DRAFT_PR_BODY_FILE=$(mktemp)
    echo "$DRAFT_PR_BODY" > "$DRAFT_PR_BODY_FILE"
    gh pr create \
      --repo "$UPSTREAM_REPO" \
      --base main \
      --head "${FORK_OWNER}:${FEATURE_BRANCH}" \
      --title "${FEATURE_BRANCH}: work in progress" \
      --body-file "$DRAFT_PR_BODY_FILE" \
      --draft \
      < /dev/null && echo "  🚀  Draft PR opened for ${FEATURE_BRANCH}." || echo "  ⚠️   Could not open draft PR (non-fatal)."
    rm -f "$DRAFT_PR_BODY_FILE"
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

  # Pre-resolve the PR branch name so mode files don't need to look it up.
  local pr_branch=""
  if [[ -n "$PR_NUMBER" ]]; then
    pr_branch=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
      --json headRefName --jq '.headRefName' < /dev/null 2>/dev/null || echo "")
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
}

# ── Post-merge bookkeeping ────────────────────────────────────────────────────

# Closes issues linked to a merged PR and removes the `blocked` label from any
# issue whose blockers are now all closed.  Runs after a merge-mode iteration.
post_merge_cleanup() {
  local pr_number="$1"

  local pr_state
  pr_state=$(gh pr view "$pr_number" --repo "$REPO" \
    --json state --jq '.state' < /dev/null 2>/dev/null || echo "")
  [[ "$pr_state" == "MERGED" ]] || return 0

  local closed_issues
  closed_issues=$(gh pr view "$pr_number" --repo "$REPO" \
    --json closingIssuesReferences \
    --jq '.closingIssuesReferences[].number' \
    < /dev/null 2>/dev/null || echo "")

  for issue_num in $closed_issues; do
    gh issue close "$issue_num" --repo "$REPO" < /dev/null 2>/dev/null || true
    echo "  ✅  Closed issue #${issue_num}"
  done

  [[ -n "$closed_issues" ]] || return 0

  local blocked_json
  blocked_json=$(gh issue list --repo "$REPO" --label blocked \
    --json number,body --limit 100 \
    < /dev/null 2>/dev/null || echo "[]")

  local unblock_script
  unblock_script=$(mktemp)
  cat > "$unblock_script" << 'EOF'
import sys, json, subprocess, re

repo        = sys.argv[1]
just_closed = {int(x) for x in sys.argv[2:]}
issues      = json.load(sys.stdin)

for issue in issues:
    body     = issue.get("body") or ""
    blockers = {int(m) for m in re.findall(r'[Bb]locked by #(\d+)', body)}
    if not blockers & just_closed:
        continue
    all_done = all(
        b in just_closed or subprocess.run(
            ["gh", "issue", "view", str(b), "--repo", repo,
             "--json", "state", "--jq", ".state"],
            capture_output=True, text=True, stdin=subprocess.DEVNULL
        ).stdout.strip() == "CLOSED"
        for b in blockers
    )
    if all_done:
        subprocess.run(
            ["gh", "issue", "edit", str(issue["number"]),
             "--repo", repo, "--remove-label", "blocked"],
            stdin=subprocess.DEVNULL
        )
        print(f"  🔓  Unblocked issue #{issue['number']}")
EOF
  echo "$blocked_json" | python3 "$unblock_script" "$REPO" $closed_issues
  rm -f "$unblock_script"
}

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
