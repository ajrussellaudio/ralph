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
RAW_LABEL=""

if [[ $# -eq 2 ]]; then
  if [[ "$2" =~ ^--label=(.+)$ ]]; then
    RAW_LABEL="${BASH_REMATCH[1]}"
    FEATURE_LABEL="prd/${RAW_LABEL}"
    FEATURE_BRANCH="feat/${RAW_LABEL}"
  else
    usage
    exit 1
  fi
fi

PLANS_DIR="${GIT_ROOT}/plans/${RAW_LABEL}"

# ── Preflight checks ───────────────────────────────────────────────────────────

if ! command -v copilot &>/dev/null; then
  echo "Error: 'copilot' not found in PATH. Install the GitHub Copilot CLI first."
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required but not found in PATH."
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
  echo "ralph.toml in your project root (copy from project.example.toml)."
  exit 1
fi

# In label mode, validate that the plans directory exists and contains task files.
if [[ -n "$RAW_LABEL" ]]; then
  if [[ ! -d "$PLANS_DIR" ]]; then
    echo "Error: Plans directory not found at ${PLANS_DIR}"
    echo "Create it and add at least one task file (e.g. 01-first-task.md)."
    exit 1
  fi
  if ! ls "${PLANS_DIR}"/*.md &>/dev/null; then
    echo "Error: No .md task files found in ${PLANS_DIR}"
    echo "Add at least one task file (e.g. 01-first-task.md)."
    exit 1
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

# ── YAML front matter helpers ──────────────────────────────────────────────────

# Reads a single YAML front matter field value from a .md file.
# Usage: get_front_matter_field <file> <field>
get_front_matter_field() {
  local file="$1" field="$2"
  python3 - "$file" "$field" <<'PYEOF'
import sys, re
file_path, field = sys.argv[1], sys.argv[2]
with open(file_path) as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(0)
for line in m.group(1).splitlines():
    if re.match(r'^' + re.escape(field) + r'\s*:', line):
        val = line.split(':', 1)[1].strip().strip('"').strip("'")
        print(val, end='')
        break
PYEOF
}

# Overwrites a single YAML front matter field in a .md file without corrupting
# the rest of the file.
# Usage: set_front_matter_field <file> <field> <value>
set_front_matter_field() {
  local file="$1" field="$2" value="$3"
  python3 - "$file" "$field" "$value" <<'PYEOF'
import sys, re
file_path, field, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(file_path) as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(1)
fm = m.group(1)
new_fm = re.sub(
    r'^(' + re.escape(field) + r'\s*:).*$',
    lambda _: field + ': ' + value,
    fm,
    flags=re.MULTILINE
)
if new_fm == fm:
    sys.stderr.write(f"Warning: field '{field}' not found in front matter\n")
    sys.exit(1)
new_content = '---\n' + new_fm + '\n---' + content[m.end():]
with open(file_path, 'w') as f:
    f.write(new_content)
PYEOF
}

# ── Routing ────────────────────────────────────────────────────────────────────

# Populates MODE, TASK_FILE, TASK_ID based on YAML front matter in task files.
# MODE is one of: implement | review | review-round2 | fix | force-approve | feature-pr | complete
determine_mode() {
  PR_NUMBER=""
  ISSUE_NUMBER=""
  TASK_FILE=""
  TASK_ID=""

  if [[ -z "$RAW_LABEL" ]]; then
    MODE="complete"
    echo "  ▶  Mode: $MODE  (no --label given)"
    return
  fi

  echo "  🔍 Scanning task files in ${PLANS_DIR}…"

  local routing
  if ! routing=$(python3 - "$PLANS_DIR" <<'PYEOF'
import sys, os, re, glob

plans_dir = sys.argv[1]

def parse_front_matter(path):
    with open(path) as f:
        content = f.read()
    m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not m:
        return {}
    fm = {}
    for line in m.group(1).splitlines():
        if ':' in line:
            k, _, v = line.partition(':')
            fm[k.strip()] = v.strip().strip('"').strip("'")
    return fm

files = sorted(glob.glob(os.path.join(plans_dir, '*.md')))
tasks = []
for f in files:
    fm = parse_front_matter(f)
    tid_m = re.match(r'^(\d+)', os.path.basename(f))
    if not tid_m:
        continue
    tasks.append({
        'file': f,
        'id': tid_m.group(1),
        'status': fm.get('status', 'pending'),
        'priority': fm.get('priority', 'normal'),
        'blocked_by': [int(x) for x in re.findall(r'\d+', fm.get('blocked_by', '[]'))],
        'branch': fm.get('branch', ''),
        'fix_count': int(fm.get('fix_count', '0') or '0'),
    })

if not tasks:
    print('complete\t\t')
    sys.exit(0)

status_map = {int(t['id']): t['status'] for t in tasks}

def deps_done(blocked_by):
    return all(status_map.get(dep) == 'done' for dep in blocked_by)

# Priority 1: needs_review — always route to review (branch read from front matter)
for t in tasks:
    if t['status'] == 'needs_review':
        print(f"review\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 2: needs_review_2 — force-approve if fix_count >= 2, else review-round2
for t in tasks:
    if t['status'] == 'needs_review_2':
        if t['fix_count'] >= 2:
            print(f"force-approve\t{t['file']}\t{t['id']}")
        else:
            print(f"review-round2\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 3: needs_fix — force-approve if fix_count >= 2, else fix
for t in tasks:
    if t['status'] == 'needs_fix':
        if t['fix_count'] >= 2:
            print(f"force-approve\t{t['file']}\t{t['id']}")
        else:
            print(f"fix\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 4: in_progress (resume interrupted work)
for t in tasks:
    if t['status'] == 'in_progress':
        print(f"fix\t{t['file']}\t{t['id']}")
        sys.exit(0)

# Priority 5: pending with all blocked_by deps done (high priority first)
ready = [t for t in tasks if t['status'] == 'pending' and deps_done(t['blocked_by'])]
high = [t for t in ready if t['priority'] == 'high']
if high:
    t = high[0]
    print(f"implement\t{t['file']}\t{t['id']}")
    sys.exit(0)
if ready:
    t = ready[0]
    print(f"implement\t{t['file']}\t{t['id']}")
    sys.exit(0)

# All done?
if all(t['status'] == 'done' for t in tasks):
    print('all-done\t\t')
    sys.exit(0)

# Otherwise (all remaining tasks are blocked)
print('blocked\t\t')
PYEOF
); then
    echo "Error: routing script failed — check task files in ${PLANS_DIR}"
    exit 1
  fi

  local mode task_file task_id
  IFS=$'\t' read -r mode task_file task_id <<< "$routing"

  if [[ "$mode" == "all-done" ]]; then
    local feature_pr_count
    feature_pr_count=$(gh pr list --repo "$REPO" --state open \
      --base "main" \
      --head "$FEATURE_BRANCH" \
      --json number --jq 'length' \
      < /dev/null 2>/dev/null || echo "1")
    if [[ "$feature_pr_count" == "0" ]]; then
      MODE="feature-pr"
      echo "  ▶  Mode: $MODE  (all tasks done, opening feat→main PR)"
    else
      MODE="complete"
      echo "  ▶  Mode: $MODE  (all tasks done, feature PR already open)"
    fi
  elif [[ "$mode" == "blocked" ]]; then
    MODE="blocked"
    echo "  ▶  Mode: blocked  (all remaining pending tasks are blocked)"
  else
    MODE="$mode"
    TASK_FILE="$task_file"
    TASK_ID="$task_id"
    if [[ "$MODE" == "complete" ]]; then
      echo "  ▶  Mode: $MODE  (no work to do)"
    else
      echo "  ▶  Mode: $MODE  (Task $TASK_ID)"
    fi
  fi
}

# Loads the mode file and substitutes all placeholders.
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
  PROMPT="${PROMPT//\{\{TASK_FILE\}\}/$TASK_FILE}"
  PROMPT="${PROMPT//\{\{TASK_ID\}\}/$TASK_ID}"
  PROMPT="${PROMPT//\{\{PLANS_DIR\}\}/$PLANS_DIR}"

  # Populate {{PRD_OVERVIEW}} from plans/<label>.md — body only, front matter stripped.
  local prd_overview=""
  local prd_file="${GIT_ROOT}/plans/${RAW_LABEL}.md"
  if [[ -n "$RAW_LABEL" && -f "$prd_file" ]]; then
    prd_overview=$(python3 - "$prd_file" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
body = re.sub(r'^---\n.*?\n---\n?', '', content, count=1, flags=re.DOTALL).strip()
print(body)
PYEOF
)
  fi
  PROMPT="${PROMPT//\{\{PRD_OVERVIEW\}\}/$prd_overview}"
}

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

  # Blocked — all remaining pending tasks are waiting on unfinished dependencies
  if [[ "$MODE" == "blocked" ]]; then
    echo ""
    printf "\033[1;33m"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🚫  Ralph stopped: all remaining tasks are blocked by unfinished dependencies"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "\033[0m"
    exit 1
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
