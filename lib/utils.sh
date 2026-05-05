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
# Output: TSV, one subtask per line — `key<TAB>type<TAB>summary`.
jira_open_subtasks() {
  local parent="$1"
  jira_with_retry issue list \
    --jql "parent = $parent AND statusCategory != Done" \
    --plain --no-headers \
    --columns "key,type,summary" < /dev/null
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
