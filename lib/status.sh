#!/usr/bin/env bash
# status.sh — ralph_status(): print a compact read-only snapshot of open ralph PRs.
#
# Expects REPO and FEATURE_BRANCH to be set by the caller (ralph.sh or tests).
# Makes no writes to GitHub and performs no git operations.

# shellcheck source=utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

_format_pr_lines() {
  jq -r '.[] |
    (if .reviewDecision == "APPROVED" then "APPROVED ✅"
     elif .reviewDecision == "CHANGES_REQUESTED" then "CHANGES_REQUESTED 🔄"
     else "PENDING ⏳"
     end) as $review |
    (if (.statusCheckRollup == null or (.statusCheckRollup | length) == 0) then "pending ⏳"
     elif (.statusCheckRollup | any(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or .conclusion == "CANCELLED" or .conclusion == "ACTION_REQUIRED" or .conclusion == "STARTUP_FAILURE")) then "failing ❌"
     elif (.statusCheckRollup | any(.status != "COMPLETED")) then "pending ⏳"
     else "passing ✅"
     end) as $ci |
    "  #\(.number)  \(.headRefName)  \($review)  \($ci)"'
}

ralph_status() {
  local rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ -n "${PARENT_TICKET:-}" ]]; then
    _ralph_status_jira
    return $?
  fi

  echo "$rule"
  echo "🤖 Ralph — status"
  echo "$rule"
  echo ""
  echo "📋 PRs"
  echo ""

  local prs_json
  prs_json=$(gh pr list --repo "$REPO" --state open \
    --base "$FEATURE_BRANCH" \
    --json number,headRefName,reviewDecision,statusCheckRollup \
    --jq '[.[] | select(.headRefName | startswith("ralph/issue-"))] | sort_by(.number)' \
    < /dev/null 2>&1) || { echo "  ⚠️  gh pr list failed: $prs_json"; return 1; }

  local pr_count
  pr_count=$(echo "$prs_json" | jq 'length')

  if [[ "$pr_count" -eq 0 ]]; then
    echo "  (no open PRs)"
  else
    echo "$prs_json" | _format_pr_lines
  fi

  # Feature PR section (only when FEATURE_LABEL is set and a feat/→main PR exists)
  if [[ -n "${FEATURE_LABEL:-}" ]]; then
    local feature_pr_json
    feature_pr_json=$(gh pr list --repo "$REPO" --state open \
      --base "main" \
      --head "$FEATURE_BRANCH" \
      --json number,headRefName,reviewDecision,statusCheckRollup \
      < /dev/null 2>/dev/null || echo "[]")

    local feature_pr_count
    feature_pr_count=$(echo "$feature_pr_json" | jq 'length')

    if [[ "$feature_pr_count" -gt 0 ]]; then
      echo ""
      echo "🚀 Feature PR"
      echo ""
      echo "$feature_pr_json" | _format_pr_lines
    fi
  fi

  # Issues section
  echo ""
  echo "🎫 Issues"
  echo ""

  local issues_json
  if [[ -n "${FEATURE_LABEL:-}" ]]; then
    issues_json=$(gh issue list --repo "$REPO" --state open \
      --label "$FEATURE_LABEL" \
      --json number,title,labels --limit 100 \
      < /dev/null 2>/dev/null || echo "[]")
  else
    issues_json=$(gh issue list --repo "$REPO" --state open \
      --json number,title,labels --limit 100 \
      --jq '[.[] | select(.labels | map(.name) | any(startswith("prd/")) | not)]' \
      < /dev/null 2>/dev/null || echo "[]")
  fi

  local issue_count
  issue_count=$(echo "$issues_json" | jq 'length')

  if [[ "$issue_count" -eq 0 ]]; then
    echo "  (no open issues)"
  else
    echo "$issues_json" | jq -r 'sort_by(.number) | .[] |
      (if (.labels | map(.name) | any(. == "blocked")) then "⚠️  " else "   " end) as $blocked |
      "  \($blocked)#\(.number)  \(.title)"'
  fi
}

# _ralph_status_jira — JIRA-backend status output.
# Requires PARENT_TICKET (and REPO) to be set. Renders the parent ticket and a
# table of its subtasks, including any linked open Ralph PR authored by @me.
_ralph_status_jira() {
  local rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "$rule"
  echo "🤖 Ralph — status (JIRA: ${PARENT_TICKET})"
  echo "$rule"
  echo ""

  local parent_line parent_key parent_summary parent_status
  parent_line=$(jira_with_retry issue view "$PARENT_TICKET" \
    --plain --no-headers --columns "key,summary,status" < /dev/null 2>/dev/null \
    | head -n 1 || echo "")

  echo "🎫 Parent"
  echo ""
  if [[ -n "$parent_line" ]]; then
    parent_key=$(printf '%s' "$parent_line" | awk -F '\t' '{print $1}')
    parent_summary=$(printf '%s' "$parent_line" | awk -F '\t' '{print $2}')
    parent_status=$(printf '%s' "$parent_line" | awk -F '\t' '{print $3}')
    [[ -z "$parent_key" ]] && parent_key="$PARENT_TICKET"
    echo "  ${parent_key}  ${parent_summary:-—}  [${parent_status:-—}]"
  else
    echo "  ⚠️  Could not fetch parent ticket ${PARENT_TICKET}"
  fi
  echo ""

  # Open Ralph PRs authored by @me — used to find linked PRs by head branch.
  local prs_json
  prs_json=$(gh pr list --repo "$REPO" --state open --author "@me" \
    --json number,headRefName --limit 200 \
    < /dev/null 2>/dev/null || echo "[]")
  [[ -z "$prs_json" ]] && prs_json="[]"

  echo "📋 Subtasks"
  echo ""

  local subtasks_tsv
  subtasks_tsv=$(jira_all_subtasks "$PARENT_TICKET" 2>/dev/null || echo "")
  subtasks_tsv=$(printf '%s\n' "$subtasks_tsv" | sed '/^[[:space:]]*$/d')

  if [[ -z "$subtasks_tsv" ]]; then
    echo "  (no subtasks)"
    return 0
  fi

  printf '  %-12s  %-40s  %-15s  %-10s  %s\n' "Key" "Summary" "Status" "Priority" "PR"

  local key type summary status_col prio key_lower pr_num pr_field
  while IFS=$'\t' read -r key type summary status_col prio; do
    [[ -z "$key" ]] && continue
    key_lower=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
    # Match head branches that contain this ticket key (case-insensitive),
    # bounded by non-alphanumerics to avoid matching e.g. CAPP-12 inside CAPP-123.
    pr_field=$(printf '%s' "$prs_json" | jq -r --arg k "$key_lower" '
      [.[] | select(.headRefName | ascii_downcase | test("(^|[^a-z0-9])" + $k + "($|[^a-z0-9])"))]
      | first | .number // empty
    ' 2>/dev/null || echo "")
    if [[ -n "$pr_field" ]]; then
      pr_num="#${pr_field}"
    else
      pr_num="—"
    fi
    printf '  %-12s  %-40s  %-15s  %-10s  %s\n' \
      "$key" "${summary:0:40}" "${status_col:-—}" "${prio:-—}" "$pr_num"
  done <<< "$subtasks_tsv"
}
