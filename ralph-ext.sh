#!/bin/bash
# Ralph External Review — GitHub Projects V2 entry point
#
# Usage:
#   ./ralph-ext.sh <issue> --label=<slug>
#
# Example:
#   ./ralph-ext.sh 63 --label=external-review
#
# End-to-end behavior:
#   1. Parse CLI args (issue number + label slug)
#   2. Load config from ralph.toml (repo, build, test)
#   3. Look up a GitHub Projects V2 board whose title matches the label
#   4. Read the first "Todo" item from the board (title sort order)
#   5. Extract task number from the item title (e.g. "01" from "01 — TOML parser")
#   6. Set the item status to "In Progress"
#   7. Create feat/<label> branch if it doesn't exist on origin
#   8. Set up a git worktree (torn down automatically on exit)
#   9. Build the implement-ext prompt and run Copilot to write code + open a PR
#  10. Capture the PR number; store the PR URL on the project item's "PR" field
#  11. Request a Copilot review on the PR
#  12. Poll for the review every 60 s (up to 20 min; re-request once on timeout)
#  13. On approval: merge PR, set status to "Done", sync worktree
#  14. On comments: enter fix mode — run Copilot fix, re-request review, loop
#  15. Fix loop continues until "no new comments" (merge) or threshold breach

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

# ── Config resolution ──────────────────────────────────────────────────────────

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
  echo "Usage: $(basename "$0") <issue> --label=<slug>"
  echo ""
  echo "  issue           A GitHub issue number (positive integer)."
  echo ""
  echo "  --label=<slug>  Required label slug. Derives FEATURE_BRANCH=feat/<slug>."
  echo "                  Must match the title of a GitHub Projects V2 board."
  echo ""
  echo "Examples:"
  echo "  $(basename "$0") 63 --label=external-review"
}

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

ISSUE=""
LABEL=""

for arg in "$@"; do
  case "$arg" in
    --label=*)
      LABEL="${arg#--label=}"
      ;;
    -*)
      usage
      exit 1
      ;;
    *)
      if [[ -z "$ISSUE" ]]; then
        ISSUE="$arg"
      else
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$ISSUE" ]]; then
  echo "Error: Missing <issue> argument."
  usage
  exit 1
fi

if ! [[ "$ISSUE" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: <issue> must be a positive integer, got '$ISSUE'."
  usage
  exit 1
fi

if [[ -z "$LABEL" ]]; then
  echo "Error: --label=<slug> is required."
  usage
  exit 1
fi

FEATURE_BRANCH="feat/${LABEL}"

# ── Preflight checks ──────────────────────────────────────────────────────────

if [[ -z "$REPO" ]]; then
  echo "Error: Could not determine the GitHub repo. Add 'repo = \"owner/repo\"' to"
  echo "ralph.toml in your project root, or run from inside a GitHub repository."
  exit 1
fi

# ── Validate gh token has project scope ────────────────────────────────────────

if ! gh api graphql -f query='{ viewer { projectsV2(first:1) { totalCount } } }' > /dev/null 2>&1; then
  echo "Error: Unable to query GitHub Projects. Your gh token may be missing the 'project' scope."
  echo ""
  echo "Fix with:  gh auth refresh -s project"
  exit 1
fi

# ── GitHub Projects V2 functions ───────────────────────────────────────────────

# Find a Projects V2 board whose title exactly matches the given label.
# Prints the board's node ID, or nothing if no match is found.
project_find_board() {
  local label="$1"
  gh api graphql -f query='
    query {
      viewer {
        projectsV2(first: 100) {
          nodes {
            id
            title
          }
        }
      }
    }
  ' | jq -r --arg title "$label" \
    '[.data.viewer.projectsV2.nodes[] | select(.title == $title) | .id] | first // empty'
}

# Read the first "Todo" item from a project board (sorted by title).
# Prints a JSON object with {id, title, number, body} or nothing if none found.
project_next_todo() {
  local project_id="$1"
  gh api graphql -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          items(first: 100) {
            nodes {
              id
              content {
                ... on Issue {
                  title
                  number
                  body
                }
                ... on DraftIssue {
                  title
                  body
                }
              }
              fieldValues(first: 20) {
                nodes {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name
                    field {
                      ... on ProjectV2SingleSelectField {
                        name
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  ' -f projectId="$project_id" | jq '
    [.data.node.items.nodes[]
      | select(any(.fieldValues.nodes[]; .field?.name == "Status" and .name == "Todo"))
    ]
    | sort_by(.content.title // "")
    | .[0]
    | if . == null then empty
      else {id, title: .content.title, number: .content.number, body: .content.body}
      end
  '
}

# Update the Status field of a project item to the given value.
project_set_status() {
  local project_id="$1"
  local item_id="$2"
  local status="$3"

  # Fetch the Status field ID and its option IDs.
  local field_info
  field_info=$(gh api graphql -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          field(name: "Status") {
            ... on ProjectV2SingleSelectField {
              id
              options {
                id
                name
              }
            }
          }
        }
      }
    }
  ' -f projectId="$project_id")

  local field_id option_id
  field_id=$(echo "$field_info" | jq -r '.data.node.field.id')
  option_id=$(echo "$field_info" | jq -r --arg status "$status" \
    '.data.node.field.options[] | select(.name == $status) | .id')

  if [[ -z "$option_id" ]]; then
    echo "Error: Status option '${status}' not found on the project board."
    exit 1
  fi

  gh api graphql -f query='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $projectId
        itemId: $itemId
        fieldId: $fieldId
        value: { singleSelectOptionId: $optionId }
      }) {
        projectV2Item {
          id
        }
      }
    }
  ' -f projectId="$project_id" \
    -f itemId="$item_id" \
    -f fieldId="$field_id" \
    -f optionId="$option_id" > /dev/null
}

# Find or create a "PR" custom text field on the project board.
# Prints the field ID.
project_ensure_pr_field() {
  local project_id="$1"

  # Try to find an existing "PR" text field.
  local field_id
  field_id=$(gh api graphql -f query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          fields(first: 50) {
            nodes {
              ... on ProjectV2Field {
                id
                name
                dataType
              }
            }
          }
        }
      }
    }
  ' -f projectId="$project_id" | jq -r '
    [.data.node.fields.nodes[] | select(.name == "PR" and .dataType == "TEXT")] | first | .id // empty
  ')

  if [[ -n "$field_id" ]]; then
    echo "$field_id"
    return 0
  fi

  # Field does not exist — create it.
  gh api graphql -f query='
    mutation($projectId: ID!, $name: String!, $dataType: ProjectV2CustomFieldType!) {
      createProjectV2Field(input: {
        projectId: $projectId
        name: $name
        dataType: $dataType
      }) {
        projectV2Field {
          ... on ProjectV2Field {
            id
          }
        }
      }
    }
  ' -f projectId="$project_id" \
    -f name="PR" \
    -f dataType="TEXT" | jq -r '.data.createProjectV2Field.projectV2Field.id'
}

# Set a text field value on a project item.
project_set_text_field() {
  local project_id="$1"
  local item_id="$2"
  local field_id="$3"
  local value="$4"

  gh api graphql -f query='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $value: String!) {
      updateProjectV2ItemFieldValue(input: {
        projectId: $projectId
        itemId: $itemId
        fieldId: $fieldId
        value: { text: $value }
      }) {
        projectV2Item {
          id
        }
      }
    }
  ' -f projectId="$project_id" \
    -f itemId="$item_id" \
    -f fieldId="$field_id" \
    -f value="$value" > /dev/null
}

# ── Find the project board ────────────────────────────────────────────────────

echo ""
echo "  🔍 Looking for project board: ${LABEL} …"
PROJECT_ID=$(project_find_board "$LABEL")

if [[ -z "$PROJECT_ID" ]]; then
  echo "  ❌  No project board found matching '${LABEL}'."
  exit 1
fi
echo "  ✅  Found board (${PROJECT_ID})"

# ── Get next Todo item ─────────────────────────────────────────────────────────

echo "  🔍 Looking for next Todo item …"
TODO_JSON=$(project_next_todo "$PROJECT_ID")

if [[ -z "$TODO_JSON" ]]; then
  echo "  ✅  No Todo items found on the board. Nothing to do."
  exit 0
fi

ITEM_ID=$(echo "$TODO_JSON" | jq -r '.id')
ITEM_TITLE=$(echo "$TODO_JSON" | jq -r '.title')
ITEM_NUMBER=$(echo "$TODO_JSON" | jq -r '.number // empty')
ITEM_BODY=$(echo "$TODO_JSON" | jq -r '.body // ""')

echo "  ▶  Next task: ${ITEM_TITLE}${ITEM_NUMBER:+ (#${ITEM_NUMBER})}"

# Extract the task number from the title (e.g. "01" from "01 — TOML parser").
TASK_NUMBER=""
if [[ "$ITEM_TITLE" =~ ^([0-9]+) ]]; then
  TASK_NUMBER="${BASH_REMATCH[1]}"
fi

if [[ -z "$TASK_NUMBER" ]]; then
  echo "  ❌  Could not extract a task number from item title: '${ITEM_TITLE}'"
  echo "     Expected title to start with a number, e.g. '01 — TOML parser'."
  exit 1
fi

echo "  🔢 Task number: ${TASK_NUMBER}"

# ── Set status to "In Progress" ───────────────────────────────────────────────

echo "  ⏳ Setting task status to 'In Progress' …"
project_set_status "$PROJECT_ID" "$ITEM_ID" "In Progress"

# ── Create feature branch if needed ───────────────────────────────────────────

git fetch origin --quiet
if ! git ls-remote --exit-code --heads origin "$FEATURE_BRANCH" > /dev/null 2>&1; then
  echo "  🌿 Branch origin/${FEATURE_BRANCH} not found — creating from origin/main …"
  git fetch origin main --quiet
  git push origin "origin/main:refs/heads/${FEATURE_BRANCH}" --quiet
  echo "  ✅  Branch ${FEATURE_BRANCH} created on origin."
else
  echo "  ✅  Branch ${FEATURE_BRANCH} already exists on remote."
fi

# ── Worktree setup ─────────────────────────────────────────────────────────────

_WORKTREE_CREATED=false

# Remove the worktree on exit (clean finish, error, or Ctrl-C).
cleanup() {
  if $_WORKTREE_CREATED && git -C "$GIT_ROOT" worktree list | grep -q "$WORKTREE_DIR"; then
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

echo "  🏗️  Setting up worktree at ${WORKTREE_DIR} …"
git -C "$GIT_ROOT" worktree add --detach "$WORKTREE_DIR" "origin/${FEATURE_BRANCH}"
_WORKTREE_CREATED=true

# ── Build implement prompt ─────────────────────────────────────────────────────

build_prompt() {
  local mode_file="$MODES_DIR/implement-ext.md"
  if [[ ! -f "$mode_file" ]]; then
    echo "  ❌  Mode file not found: $mode_file"
    exit 1
  fi

  PROMPT=$(cat "$mode_file")
  PROMPT="${PROMPT//\{\{REPO\}\}/$REPO}"
  PROMPT="${PROMPT//\{\{TASK_NUMBER\}\}/$TASK_NUMBER}"
  PROMPT="${PROMPT//\{\{BUILD_CMD\}\}/$BUILD_CMD}"
  PROMPT="${PROMPT//\{\{TEST_CMD\}\}/$TEST_CMD}"
  PROMPT="${PROMPT//\{\{FEATURE_BRANCH\}\}/$FEATURE_BRANCH}"

  # Task description may contain characters that break bash substitution,
  # so we use a temp file approach for safe replacement.
  local task_desc_file
  task_desc_file=$(mktemp)
  echo "$ITEM_BODY" > "$task_desc_file"

  # Replace {{TASK_DESCRIPTION}} with the actual task body.
  local task_desc
  task_desc=$(cat "$task_desc_file")
  PROMPT="${PROMPT//\{\{TASK_DESCRIPTION\}\}/$task_desc}"
  rm -f "$task_desc_file"
}

# ── Build fix prompt ───────────────────────────────────────────────────────────

build_fix_prompt() {
  local pr="$1"
  local mode_file="$MODES_DIR/fix-ext.md"
  if [[ ! -f "$mode_file" ]]; then
    echo "  ❌  Mode file not found: $mode_file"
    exit 1
  fi

  PROMPT=$(cat "$mode_file")
  PROMPT="${PROMPT//\{\{REPO\}\}/$REPO}"
  PROMPT="${PROMPT//\{\{OWNER\}\}/$OWNER}"
  PROMPT="${PROMPT//\{\{REPO_NAME\}\}/$REPO_NAME}"
  PROMPT="${PROMPT//\{\{PR_NUMBER\}\}/$pr}"
  PROMPT="${PROMPT//\{\{BUILD_CMD\}\}/$BUILD_CMD}"
  PROMPT="${PROMPT//\{\{TEST_CMD\}\}/$TEST_CMD}"
}

# ── Run implement ──────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Ralph External Review — implementing task ${TASK_NUMBER}$(printf '%*s' $((23 - ${#TASK_NUMBER})) '')║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Issue:    #${ISSUE}"
echo "  Task:     ${ITEM_TITLE}${ITEM_NUMBER:+ (#${ITEM_NUMBER})}"
echo "  Branch:   ralph/task-${TASK_NUMBER} → ${FEATURE_BRANCH}"
echo "  Worktree: ${WORKTREE_DIR}"
echo "  Config:   repo=${REPO} build='${BUILD_CMD}' test='${TEST_CMD}'"
echo ""

build_prompt

echo "  🚀 Running Copilot implement mode …"
echo ""

OUTPUT=$(
  cd "$WORKTREE_DIR" && copilot \
    --prompt "$PROMPT" \
    --allow-all \
    --autopilot \
    2>&1 | tee /dev/stderr
) || true

# ── Capture PR number ──────────────────────────────────────────────────────────

echo ""
echo "  🔍 Looking for PR from ralph/task-${TASK_NUMBER} → ${FEATURE_BRANCH} …"

PR_JSON=$(gh pr list --repo "$REPO" --state open \
  --head "ralph/task-${TASK_NUMBER}" \
  --base "$FEATURE_BRANCH" \
  --json number,url \
  --jq '.[0] // empty' \
  < /dev/null 2>/dev/null || echo "")

if [[ -z "$PR_JSON" ]]; then
  echo "  ⚠️  No PR found. Copilot may not have opened one."
  echo "     Leaving task in 'In Progress' status."
  exit 1
fi

PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number')
PR_URL=$(echo "$PR_JSON" | jq -r '.url')

echo "  ✅  Found PR #${PR_NUMBER}: ${PR_URL}"

# ── Store PR URL on project item ───────────────────────────────────────────────

echo "  📎 Storing PR URL on project item …"
PR_FIELD_ID=$(project_ensure_pr_field "$PROJECT_ID")
project_set_text_field "$PROJECT_ID" "$ITEM_ID" "$PR_FIELD_ID" "$PR_URL"
echo "  ✅  PR URL stored."

# ── Copilot review: request + poll + merge ─────────────────────────────────────

OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"

# Request a Copilot review on the PR.
# Prints the ISO-8601 timestamp at which the request was made.
request_copilot_review() {
  local pr="$1"
  if ! gh api "/repos/${REPO}/pulls/${pr}/requested_reviewers" \
    -X POST -f 'reviewers[]=Copilot' > /dev/null 2>&1; then
    echo "  ❌ Failed to request Copilot review (API error)." >&2
    return 1
  fi
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Poll for a Copilot review submitted after $since_ts.
# Returns a JSON object {state, body} on success, or empty string on timeout.
# Polls every 60 s, up to $max_polls attempts (default 20 = 20 minutes).
poll_copilot_review() {
  local pr="$1"
  local since_ts="$2"
  local max_polls="${3:-20}"
  local poll=0

  while (( poll < max_polls )); do
    sleep 60
    (( poll++ )) || true

    echo "  ⏳ Poll ${poll}/${max_polls} — checking for Copilot review …" >&2

    local review
    review=$(gh api "/repos/${REPO}/pulls/${pr}/reviews" \
      --jq '
        [ .[]
          | select(.user.login == "copilot-pull-request-reviewer[bot]")
          | select(.submitted_at > "'"${since_ts}"'")
        ] | last // empty
      ' 2>/dev/null || echo "")

    if [[ -n "$review" ]]; then
      echo "$review"
      return 0
    fi
  done

  # Timed out — no review found.
  return 1
}

echo ""
echo "  🤖 Requesting Copilot review on PR #${PR_NUMBER} …"
REQUEST_TS=$(request_copilot_review "$PR_NUMBER")
echo "  ✅  Review requested at ${REQUEST_TS}"

echo "  ⏳ Polling for Copilot review (up to 20 minutes) …"

REVIEW_JSON=""
REVIEW_ATTEMPT=1

# First attempt: poll up to 20 minutes.
if REVIEW_JSON=$(poll_copilot_review "$PR_NUMBER" "$REQUEST_TS" 20); then
  echo "  ✅  Copilot review received."
else
  # Timeout — re-request once and retry.
  echo "  ⚠️  Poll timed out. Re-requesting review (attempt 2/2) …"
  REVIEW_ATTEMPT=2
  REQUEST_TS=$(request_copilot_review "$PR_NUMBER")
  echo "  ✅  Review re-requested at ${REQUEST_TS}"
  echo "  ⏳ Polling again (up to 20 minutes) …"

  if REVIEW_JSON=$(poll_copilot_review "$PR_NUMBER" "$REQUEST_TS" 20); then
    echo "  ✅  Copilot review received on attempt 2."
  else
    echo "  ❌  Copilot review not received after two attempts (40 minutes total)."
    echo "     Leaving PR #${PR_NUMBER} open for manual review."
    exit 1
  fi
fi

# ── Parse the review result and fix loop ─────────────────────────────────────

MAX_FIX_COUNT=5
fix_count=0

handle_review() {
  local review_json="$1"
  local review_body
  review_body=$(echo "$review_json" | jq -r '.body // ""')

  if echo "$review_body" | grep -qi "no new comments"; then
    echo "  ✅  Review passed — no new comments."

    # Merge the PR.
    echo "  🔀 Merging PR #${PR_NUMBER} …"
    gh pr merge "$PR_NUMBER" --repo "$REPO" --merge < /dev/null

    # Update project item status to "Done".
    echo "  📋 Setting task status to 'Done' …"
    project_set_status "$PROJECT_ID" "$ITEM_ID" "Done"

    # Sync the worktree to the updated feature branch tip.
    echo "  🔄 Syncing worktree to ${FEATURE_BRANCH} …"
    git -C "$WORKTREE_DIR" fetch origin "$FEATURE_BRANCH" --quiet
    git -C "$WORKTREE_DIR" checkout --detach "origin/${FEATURE_BRANCH}" --quiet 2>/dev/null || true

    echo ""
    echo "  ──────────────────────────────────────────"
    echo "  PR_NUMBER=${PR_NUMBER}"
    echo "  PR_URL=${PR_URL}"
    echo "  TASK_NUMBER=${TASK_NUMBER}"
    echo "  STATUS=merged"
    echo "  FIX_COUNT=${fix_count}"
    echo "  ──────────────────────────────────────────"
    echo ""
    echo "  ✅  Task ${TASK_NUMBER} complete. PR merged and status set to Done."
    return 0
  fi

  # Detect comment count from various review body formats.
  local comment_count=""
  if echo "$review_body" | grep -qE 'generated [0-9]+ comment'; then
    comment_count=$(echo "$review_body" | sed -n 's/.*generated \([0-9][0-9]*\) comment.*/\1/p' | head -1)
  elif echo "$review_body" | grep -qiE '[0-9]+ comment'; then
    comment_count=$(echo "$review_body" | grep -oE '[0-9]+ comment' | head -1 | grep -oE '[0-9]+')
  fi

  if [[ -z "$comment_count" ]]; then
    echo ""
    echo "  ⚠️  Copilot review received but could not determine result."
    echo "     Review body: ${review_body}"
    echo ""
    echo "  ──────────────────────────────────────────"
    echo "  PR_NUMBER=${PR_NUMBER}"
    echo "  PR_URL=${PR_URL}"
    echo "  TASK_NUMBER=${TASK_NUMBER}"
    echo "  STATUS=unknown"
    echo "  ──────────────────────────────────────────"
    return 1
  fi

  # Review has comments — enter fix mode.
  (( fix_count++ )) || true
  echo ""
  echo "  ⚠️  Review has ${comment_count} comment(s). Entering fix mode (iteration ${fix_count}/${MAX_FIX_COUNT}) …"

  # Check threshold before attempting fix.
  if (( fix_count > MAX_FIX_COUNT )); then
    echo ""
    echo "  ❌  Fix count (${fix_count}) exceeds threshold (${MAX_FIX_COUNT})."
    echo "     Stopping — escalate for manual review."
    echo ""
    echo "  ──────────────────────────────────────────"
    echo "  PR_NUMBER=${PR_NUMBER}"
    echo "  PR_URL=${PR_URL}"
    echo "  TASK_NUMBER=${TASK_NUMBER}"
    echo "  STATUS=escalate"
    echo "  FIX_COUNT=${fix_count}"
    echo "  ──────────────────────────────────────────"
    return 1
  fi

  # Build and run the fix prompt.
  build_fix_prompt "$PR_NUMBER"

  echo ""
  echo "  🔧 Running Copilot fix mode (iteration ${fix_count}) …"
  echo ""

  local fix_output
  fix_output=$(
    cd "$WORKTREE_DIR" && copilot \
      --prompt "$PROMPT" \
      --allow-all \
      --autopilot \
      2>&1 | tee /dev/stderr
  ) || true

  # Re-request Copilot review and re-enter polling loop.
  echo ""
  echo "  🤖 Re-requesting Copilot review on PR #${PR_NUMBER} (after fix iteration ${fix_count}) …"
  local new_request_ts
  new_request_ts=$(request_copilot_review "$PR_NUMBER")
  echo "  ✅  Review re-requested at ${new_request_ts}"

  echo "  ⏳ Polling for Copilot review (up to 20 minutes) …"

  local new_review_json=""
  if new_review_json=$(poll_copilot_review "$PR_NUMBER" "$new_request_ts" 20); then
    echo "  ✅  Copilot review received."
    handle_review "$new_review_json"
    return $?
  else
    echo "  ⚠️  Poll timed out after fix. Re-requesting review (retry) …"
    new_request_ts=$(request_copilot_review "$PR_NUMBER")
    echo "  ✅  Review re-requested at ${new_request_ts}"
    echo "  ⏳ Polling again (up to 20 minutes) …"

    if new_review_json=$(poll_copilot_review "$PR_NUMBER" "$new_request_ts" 20); then
      echo "  ✅  Copilot review received on retry."
      handle_review "$new_review_json"
      return $?
    else
      echo "  ❌  Copilot review not received after fix iteration ${fix_count}."
      echo "     Leaving PR #${PR_NUMBER} open for manual review."
      return 1
    fi
  fi
}

handle_review "$REVIEW_JSON"
