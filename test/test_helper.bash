# test/test_helper.bash — shared setup helpers for Ralph bats tests (markdown backend)

RALPH_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Minimal globals required by lib/functions.sh when sourced.
REPO="${REPO:-test/owner/repo}"
FEATURE_BRANCH="${FEATURE_BRANCH:-feat/test-label}"
GIT_ROOT="$RALPH_DIR"

source "$RALPH_DIR/lib/functions.sh"

# Creates a task .md file with YAML front matter.
# Usage: create_task_file <dir> <filename> [key=value ...]
# Supported keys: status, priority, fix_count, branch, blocked_by, review_notes
# blocked_by should be a bare number (e.g. blocked_by=2) — stored as YAML [2]
create_task_file() {
  local dir="$1" filename="$2"
  shift 2
  local file="$dir/$filename"

  local status="pending"
  local priority="normal"
  local fix_count="0"
  local branch=""
  local blocked_by=""
  local review_notes=""

  for kv in "$@"; do
    local key="${kv%%=*}" val="${kv#*=}"
    case "$key" in
      status)       status="$val" ;;
      priority)     priority="$val" ;;
      fix_count)    fix_count="$val" ;;
      branch)       branch="$val" ;;
      blocked_by)   blocked_by="$val" ;;
      review_notes) review_notes="$val" ;;
    esac
  done

  {
    printf -- '---\n'
    printf 'status: %s\n' "$status"
    printf 'priority: %s\n' "$priority"
    printf 'fix_count: %s\n' "$fix_count"
    [[ -n "$branch" ]]       && printf 'branch: %s\n' "$branch"
    [[ -n "$blocked_by" ]]   && printf 'blocked_by: [%s]\n' "$blocked_by"
    [[ -n "$review_notes" ]] && printf 'review_notes: "%s"\n' "$review_notes"
    printf -- '---\n\n'
    printf '# Task\n\nTask body.\n'
  } > "$file"
}
