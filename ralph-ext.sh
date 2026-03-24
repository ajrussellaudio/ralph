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
#   5. Set the item status to "In Progress"
#   6. Create feat/<label> branch if it doesn't exist on origin
#   7. Set up a git worktree (torn down automatically on exit)
#   8. (placeholder — future slices add implement/review logic here)
#   9. Set the item status to "Done"

set -euo pipefail

GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WORKTREE_DIR="${GIT_ROOT%/*}/$(basename "$GIT_ROOT")-ralph-workspace"

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
# Prints a JSON object with {id, title, number} or nothing if none found.
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
                }
                ... on DraftIssue {
                  title
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
      else {id, title: .content.title, number: .content.number}
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

echo "  ▶  Next task: ${ITEM_TITLE}${ITEM_NUMBER:+ (#${ITEM_NUMBER})}"

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

# ── Placeholder for actual work ───────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Ralph External Review — task in progress                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Issue:    #${ISSUE}"
echo "  Task:     ${ITEM_TITLE}${ITEM_NUMBER:+ (#${ITEM_NUMBER})}"
echo "  Branch:   ${FEATURE_BRANCH}"
echo "  Worktree: ${WORKTREE_DIR}"
echo "  Config:   repo=${REPO} build='${BUILD_CMD}' test='${TEST_CMD}'"
echo ""
echo "  (placeholder — implement/review logic will be added in future slices)"
echo ""

# ── Set status to "Done" ──────────────────────────────────────────────────────

echo "  ✅  Setting task status to 'Done' …"
project_set_status "$PROJECT_ID" "$ITEM_ID" "Done"

echo ""
echo "  Task complete."
