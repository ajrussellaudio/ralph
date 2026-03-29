#!/usr/bin/env bash
# status.sh — ralph_status(): print a compact read-only snapshot of open ralph PRs.
#
# Expects REPO and FEATURE_BRANCH to be set by the caller (ralph.sh or tests).
# Makes no writes to GitHub and performs no git operations.

ralph_status() {
  local rule="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
    < /dev/null 2>/dev/null || echo "[]")

  local pr_count
  pr_count=$(echo "$prs_json" | jq 'length')

  if [[ "$pr_count" -eq 0 ]]; then
    echo "  (no open PRs)"
    return 0
  fi

  echo "$prs_json" | jq -r '.[] |
    (if .reviewDecision == "APPROVED" then "APPROVED ✅"
     elif .reviewDecision == "CHANGES_REQUESTED" then "CHANGES_REQUESTED 🔄"
     else "PENDING ⏳"
     end) as $review |
    (if (.statusCheckRollup == null or (.statusCheckRollup | length) == 0) then "pending ⏳"
     elif (.statusCheckRollup | any(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT")) then "failing ❌"
     elif (.statusCheckRollup | any(.status != "COMPLETED")) then "pending ⏳"
     else "passing ✅"
     end) as $ci |
    "  #\(.number)  \(.headRefName)  \($review)  \($ci)"'
}
