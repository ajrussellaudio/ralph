#!/usr/bin/env bash
# utils.sh — shared utilities for ralph.sh and lib/*.sh
#
# Sourced by ralph.sh and individual lib scripts.

# gh_with_retry() — wrapper around `gh` that retries up to 3 times on failure.
#
# Usage: gh_with_retry [gh args...]
#
# Behaviour:
#   - Forwards all arguments and stdin verbatim to `gh`
#   - On success (exit 0): returns immediately with stdout/stderr intact
#   - On failure (non-zero exit):
#       - Prints a warning to stderr with attempt number and backoff delay
#       - Sleeps 1s before attempt 2, 2s before attempt 3
#       - Retries
#   - After 3 failed attempts: prints a final error to stderr and returns the
#     last non-zero exit code
gh_with_retry() {
  local max_attempts=3
  local attempt=1
  local exit_code

  while (( attempt <= max_attempts )); do
    gh "$@" && return 0
    exit_code=$?

    if (( attempt < max_attempts )); then
      local delay=$(( attempt ))
      printf '  ⚠️  gh call failed (attempt %d/%d) — retrying in %ds…\n' \
        "$attempt" "$max_attempts" "$delay" >&2
      sleep "$delay"
    fi

    (( attempt++ ))
  done

  printf '  ❌  gh call failed after %d attempts: gh %s\n' \
    "$max_attempts" "$*" >&2
  return "$exit_code"
}

# jira_with_retry() — wrapper around `jira` (jira-cli) that retries up to 3 times.
#
# Mirrors gh_with_retry: forwards args/stdin, prints warnings on retry, returns
# the last non-zero exit code after exhausting attempts.
jira_with_retry() {
  local max_attempts=3
  local attempt=1
  local exit_code

  while (( attempt <= max_attempts )); do
    jira "$@" && return 0
    exit_code=$?

    if (( attempt < max_attempts )); then
      local delay=$(( attempt ))
      printf '  ⚠️  jira call failed (attempt %d/%d) — retrying in %ds…\n' \
        "$attempt" "$max_attempts" "$delay" >&2
      sleep "$delay"
    fi

    (( attempt++ ))
  done

  printf '  ❌  jira call failed after %d attempts: jira %s\n' \
    "$max_attempts" "$*" >&2
  return "$exit_code"
}

# jira_branch_prefix ISSUE_TYPE
# Maps a JIRA issue type to a conventional-commit branch prefix.
#   Bug          → fix
#   Improvement  → refactor
#   anything else (Task, Sub-task, Story, Spike, Epic, …) → feat
jira_branch_prefix() {
  case "${1:-}" in
    Bug|bug) echo "fix" ;;
    Improvement|improvement) echo "refactor" ;;
    *) echo "feat" ;;
  esac
}

# jira_kebab_summary SUMMARY
# Lowercases the summary, replaces runs of non-alphanumerics with a single dash,
# trims leading/trailing dashes, and truncates to 50 chars (then re-trims).
jira_kebab_summary() {
  local summary="${1:-}"
  local out
  out=$(printf '%s' "$summary" \
    | tr '[:upper:]' '[:lower:]' \
    | LC_ALL=C sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
  out="${out:0:50}"
  out="${out%-}"
  printf '%s' "$out"
}

# jira_open_subtasks PARENT_KEY
# Lists open subtasks of the parent ticket via jira-cli.
# Output: TSV, one subtask per line — `key<TAB>type<TAB>summary<TAB>priority`.
jira_open_subtasks() {
  local parent="$1"
  jira_with_retry issue list \
    --jql "parent = $parent AND statusCategory != Done" \
    --plain --no-headers \
    --columns "key,type,summary,priority" < /dev/null
}

# jira_all_subtasks PARENT_KEY
# Lists every subtask of the parent ticket (open + closed) via jira-cli.
# Output: TSV, one subtask per line — `key<TAB>type<TAB>summary<TAB>status<TAB>priority`.
jira_all_subtasks() {
  local parent="$1"
  jira_with_retry issue list \
    --jql "parent = $parent" \
    --plain --no-headers \
    --columns "key,type,summary,status,priority" < /dev/null
}

# jira_blockers KEY
# Lists open "is blocked by" linked issues for KEY (i.e. tickets that block KEY
# whose statusCategory is not Done). Output: one ticket key per line, or empty.
jira_blockers() {
  local key="$1"
  jira_with_retry issue list \
    --jql "issue in linkedIssues(\"$key\", \"is blocked by\") AND statusCategory != Done" \
    --plain --no-headers \
    --columns "key" < /dev/null 2>/dev/null || true
}

# jira_filter_unblocked
# Reads TSV subtask rows on stdin (`key<TAB>type<TAB>summary[<TAB>priority]`)
# and drops any whose open "is blocked by" links point to non-Done tickets.
# Outputs the remaining rows verbatim on stdout.
jira_filter_unblocked() {
  local line key blockers
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key=$(printf '%s' "$line" | awk -F '\t' '{print $1}')
    [[ -z "$key" ]] && continue
    blockers=$(jira_blockers "$key" | sed '/^[[:space:]]*$/d')
    if [[ -z "$blockers" ]]; then
      printf '%s\n' "$line"
    fi
  done
}

# jira_priority_rank PRIORITY
# Maps a JIRA Priority name to a numeric sort rank (lower = higher priority).
#   Highest → 1, High → 2, Medium → 3, Low → 4, Lowest → 5
#   anything else (empty, unknown) → 6
jira_priority_rank() {
  case "${1:-}" in
    Highest|highest) echo 1 ;;
    High|high) echo 2 ;;
    Medium|medium) echo 3 ;;
    Low|low) echo 4 ;;
    Lowest|lowest) echo 5 ;;
    *) echo 6 ;;
  esac
}

# jira_pick_next
# Reads TSV subtask rows on stdin (`key<TAB>type<TAB>summary[<TAB>priority]`),
# sorts by Priority descending (Highest first) with ascending ticket-key tie-break,
# and prints the single highest-priority row to stdout. Empty input → no output.
jira_pick_next() {
  local line out=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key prio rank
    key=$(printf '%s' "$line" | awk -F '\t' '{print $1}')
    [[ -z "$key" ]] && continue
    prio=$(printf '%s' "$line" | awk -F '\t' '{print $4}')
    rank=$(jira_priority_rank "$prio")
    out+="${rank}	${key}	${line}"$'\n'
  done
  [[ -z "$out" ]] && return 0
  printf '%s' "$out" | LC_ALL=C sort -t$'\t' -k1,1n -k2,2 | head -n 1 | cut -f3-
}

# jira_transition KEY STATE
# Transitions a JIRA issue to the named state (e.g. "In Progress").
jira_transition() {
  local key="$1" state="$2"
  jira_with_retry issue move "$key" "$state" < /dev/null
}

# jira_feature_branch PARENT_KEY [SUMMARY]
# Derives a feature-branch name from the parent ticket.
#   feat/<lowercased-key>-<kebab-summary>     when summary is non-empty
#   feat/<lowercased-key>                     when summary is empty
# When SUMMARY is omitted, looks it up via `jira issue view`.
jira_feature_branch() {
  local key="$1"
  local summary="${2-}"
  if [[ $# -lt 2 ]]; then
    summary=$(jira_with_retry issue view "$key" \
      --plain --no-headers --columns "summary" < /dev/null 2>/dev/null \
      | head -n 1 || echo "")
  fi
  local key_lower
  key_lower=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
  local slug
  slug=$(jira_kebab_summary "$summary")
  if [[ -n "$slug" ]]; then
    printf 'feat/%s-%s' "$key_lower" "$slug"
  else
    printf 'feat/%s' "$key_lower"
  fi
}
