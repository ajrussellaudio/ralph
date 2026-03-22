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
#   4. Substitutes {{REPO}}, {{PR_NUMBER}}, {{TASK_ID}}, {{FEATURE_BRANCH}}
#      placeholders
#   5. Runs Copilot with that focused, self-contained prompt
#
# The loop stops early if Copilot emits <promise>COMPLETE</promise> or if
# bash routing finds no open PRs and no open issues.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

if ! command -v sqlite3 &>/dev/null; then
  echo "Error: 'sqlite3' not found in PATH. Install SQLite first."
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

# ── Storage paths ─────────────────────────────────────────────────────────────

# Derive slug: replace '/' with '-' in REPO (e.g. "owner/repo" → "owner-repo")
REPO_SLUG="${REPO//\//-}"

# Label slug: strip "prd/" prefix if present; default to "default" when no label given.
if [[ -n "$FEATURE_LABEL" ]]; then
  LABEL_SLUG="${FEATURE_LABEL#prd/}"
else
  LABEL_SLUG="default"
fi

STORAGE_DIR="${HOME}/.ralph/projects/${REPO_SLUG}/${LABEL_SLUG}"
DB_PATH="${STORAGE_DIR}/ralph.db"
TASKS_FILE="${STORAGE_DIR}/tasks.md"

# Ensure the storage directory exists and the DB schema is initialised.
init_storage() {
  mkdir -p "$STORAGE_DIR"
  sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS prd (
  label    TEXT PRIMARY KEY,
  overview TEXT
);
CREATE TABLE IF NOT EXISTS tasks (
  id           INTEGER PRIMARY KEY,
  title        TEXT,
  body         TEXT,
  priority     TEXT    DEFAULT 'normal',
  status       TEXT    DEFAULT 'pending',
  branch       TEXT,
  review_notes TEXT,
  fix_count    INTEGER DEFAULT 0,
  blocked_by   INTEGER REFERENCES tasks(id)
);
SQL
  # Migrate existing DBs that predate the fix_count column.
  sqlite3 "$DB_PATH" \
    "ALTER TABLE tasks ADD COLUMN fix_count INTEGER DEFAULT 0;" 2>/dev/null || true
}

init_storage

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

# ── Routing ────────────────────────────────────────────────────────────────────

# Populates MODE and TASK_ID by querying the local SQLite task database.
# MODE is one of: implement | review | review-round2 | fix | force-approve | merge | feature-pr | complete
determine_mode() {
  TASK_ID=""
  PR_NUMBER=""  # kept for compatibility with review.md / fix.md (always empty now)

  echo "  🔄 Syncing workspace…"
  (cd "$WORKTREE_DIR" && git fetch origin && git reset --hard "origin/$FEATURE_BRANCH") > /dev/null 2>&1

  echo "  🔍 Checking task status in DB…"

  # 1. needs_review → review
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='needs_review' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="review"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 2. approved → merge
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='approved' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="merge"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 3. needs_review_2 → review-round2
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='needs_review_2' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="review-round2"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 4. needs_fix → force-approve (fix_count >= 2) or fix
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='needs_fix' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    local fix_count
    fix_count=$(sqlite3 "$DB_PATH" \
      "SELECT fix_count FROM tasks WHERE id=$TASK_ID;" 2>/dev/null || echo "0")
    if [[ "$fix_count" -ge 2 ]]; then
      MODE="force-approve"
    else
      MODE="fix"
    fi
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 5. in_progress → fix (resume interrupted work)
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='in_progress' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="fix"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID — resuming)"
    return
  fi

  # 6. unblocked pending task → implement (high priority first, then lowest id)
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks
       WHERE status='pending'
         AND (blocked_by IS NULL
              OR blocked_by IN (SELECT id FROM tasks WHERE status='done'))
       ORDER BY CASE priority WHEN 'high' THEN 0 ELSE 1 END, id
       LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="implement"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 7. all tasks done → feature-pr or complete
  local total_tasks done_tasks
  total_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks;" 2>/dev/null || echo "0")
  done_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='done';" 2>/dev/null || echo "0")

  if [[ "$total_tasks" -gt 0 && "$total_tasks" == "$done_tasks" ]]; then
    if [[ -n "$FEATURE_LABEL" && "$FEATURE_BRANCH" != "main" ]]; then
      FEATURE_PR_COUNT=$(gh pr list --repo "$REPO" --state open \
        --base "main" \
        --head "$FEATURE_BRANCH" \
        --json number --jq 'length' \
        < /dev/null 2>/dev/null || echo "0")

      if [[ "$FEATURE_PR_COUNT" == "0" ]]; then
        MODE="feature-pr"
        echo "  ▶  Mode: $MODE  (all tasks done, opening feat→main PR)"
      else
        MODE="complete"
        echo "  ▶  Mode: $MODE  (feat→main PR already open)"
      fi
    else
      MODE="complete"
      echo "  ▶  Mode: $MODE  (all tasks done)"
    fi
    return
  fi

  # 8. Default fallback
  MODE="complete"
  echo "  ▶  Mode: $MODE  (no actionable tasks)"
}

# Loads the mode file and substitutes all {{PLACEHOLDER}} values.
build_prompt() {
  local mode_file="$MODES_DIR/$MODE.md"
  if [[ ! -f "$mode_file" ]]; then
    echo "  ❌  Mode file not found: $mode_file"
    exit 1
  fi

  # Derive PRD overview from the DB (empty string if not set).
  local prd_overview
  prd_overview=$(sqlite3 "$DB_PATH" \
    "SELECT overview FROM prd WHERE label = ?;" "$LABEL_SLUG" 2>/dev/null || echo "")

  PROMPT=$(cat "$mode_file")
  PROMPT="${PROMPT//\{\{REPO\}\}/$REPO}"
  PROMPT="${PROMPT//\{\{PR_NUMBER\}\}/$PR_NUMBER}"
  PROMPT="${PROMPT//\{\{TASK_ID\}\}/$TASK_ID}"
  PROMPT="${PROMPT//\{\{BUILD_CMD\}\}/$BUILD_CMD}"
  PROMPT="${PROMPT//\{\{TEST_CMD\}\}/$TEST_CMD}"
  PROMPT="${PROMPT//\{\{FEATURE_BRANCH\}\}/$FEATURE_BRANCH}"
  PROMPT="${PROMPT//\{\{FEATURE_LABEL\}\}/$FEATURE_LABEL}"
  PROMPT="${PROMPT//\{\{DB_PATH\}\}/$DB_PATH}"
  PROMPT="${PROMPT//\{\{TASKS_FILE\}\}/$TASKS_FILE}"
  PROMPT="${PROMPT//\{\{LABEL_SLUG\}\}/$LABEL_SLUG}"
  PROMPT="${PROMPT//\{\{PRD_OVERVIEW\}\}/$prd_overview}"
}

# ── Seeding ───────────────────────────────────────────────────────────────────

# Checks whether the tasks table is empty. If so:
#   - Exits with a clear error if tasks.md does not exist.
#   - Otherwise invokes the seed mode (Copilot) to parse tasks.md and populate the DB.
seed_if_empty() {
  local task_count
  task_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks;" 2>/dev/null || echo "0")

  if [[ "$task_count" -gt 0 ]]; then
    return 0
  fi

  if [[ ! -f "$TASKS_FILE" ]]; then
    echo ""
    echo "Error: DB is empty and tasks.md was not found at:"
    echo "  $TASKS_FILE"
    echo ""
    echo "Create a tasks.md file at that path to seed the DB on first run."
    echo "See tasks.example.md in the Ralph repo for the expected format."
    exit 1
  fi

  echo ""
  echo "  📋 DB is empty — seeding from ${TASKS_FILE} …"

  MODE="seed"
  PR_NUMBER=""
  TASK_ID=""
  build_prompt

  (cd "$WORKTREE_DIR" && copilot \
    --prompt "$PROMPT" \
    --allow-all \
    --autopilot \
    2>&1 | tee /dev/stderr)

  local seeded_count
  seeded_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks;" 2>/dev/null || echo "0")
  if [[ "$seeded_count" -eq 0 ]]; then
    echo "Error: Seeding ran but no tasks were inserted. Check tasks.md format." >&2
    exit 1
  fi
}

seed_if_empty

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
