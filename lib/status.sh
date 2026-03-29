#!/usr/bin/env bash
# status.sh — ralph_status(): print a compact read-only snapshot of open ralph PRs.
#
# Expects REPO and FEATURE_BRANCH to be set by the caller (ralph.sh or tests).
# Makes no writes to GitHub and performs no git operations.

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
