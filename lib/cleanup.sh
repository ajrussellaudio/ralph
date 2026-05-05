#!/usr/bin/env bash
# cleanup.sh — post_merge_cleanup() for both GitHub and JIRA task backends.
#
# Sourced by ralph.sh and by bats unit tests.

source "$(dirname "${BASH_SOURCE[0]}")/utils.sh"

# Closes issues linked to a merged PR (GitHub backend) or transitions the
# corresponding JIRA subtask to Done (JIRA backend). Runs after a merge-mode
# iteration. Branches on TASK_BACKEND.
post_merge_cleanup() {
  local pr_number="$1"

  local pr_state
  pr_state=$(gh_with_retry pr view "$pr_number" --repo "$REPO" \
    --json state --jq '.state' < /dev/null 2>/dev/null || echo "")
  [[ "$pr_state" == "MERGED" ]] || return 0

  if [[ "${TASK_BACKEND:-github}" == "jira" ]]; then
    local head_ref
    head_ref=$(gh_with_retry pr view "$pr_number" --repo "$REPO" \
      --json headRefName --jq '.headRefName' \
      < /dev/null 2>/dev/null || echo "")

    local proj_upper proj_lower
    proj_upper=$(printf '%s' "${PROJECT_KEY:-}" | tr '[:lower:]' '[:upper:]')
    proj_lower=$(printf '%s' "${PROJECT_KEY:-}" | tr '[:upper:]' '[:lower:]')

    if [[ -n "$proj_upper" && "$head_ref" =~ (${proj_upper}|${proj_lower})-([0-9]+) ]]; then
      local ticket_key="${proj_upper}-${BASH_REMATCH[2]}"
      if jira_transition "$ticket_key" "Done" > /dev/null 2>&1; then
        echo "  ✅  Transitioned ${ticket_key} → Done"
      else
        echo "  ⚠  Failed to transition ${ticket_key} → Done"
      fi
    else
      echo "  ⚠  Could not extract ${PROJECT_KEY:-?} ticket key from branch '${head_ref}'"
    fi
    return 0
  fi

  local closed_issues
  closed_issues=$(gh_with_retry pr view "$pr_number" --repo "$REPO" \
    --json closingIssuesReferences \
    --jq '.closingIssuesReferences[].number' \
    < /dev/null 2>/dev/null || echo "")

  # closingIssuesReferences is only populated by GitHub when the PR targets the
  # default branch.  In PRD mode the PR targets feat/<label>, so fall back to
  # parsing the issue number directly from the branch name (ralph/issue-<N>).
  if [[ -z "$closed_issues" ]]; then
    local head_ref
    head_ref=$(gh_with_retry pr view "$pr_number" --repo "$REPO" \
      --json headRefName --jq '.headRefName' \
      < /dev/null 2>/dev/null || echo "")
    if [[ "$head_ref" =~ ^ralph/issue-([0-9]+)$ ]]; then
      closed_issues="${BASH_REMATCH[1]}"
    fi
  fi

  for issue_num in $closed_issues; do
    gh_with_retry issue close "$issue_num" --repo "$REPO" < /dev/null 2>/dev/null || true
    echo "  ✅  Closed issue #${issue_num}"
  done

  [[ -n "$closed_issues" ]] || return 0

  local blocked_json
  blocked_json=$(gh_with_retry issue list --repo "$REPO" --label blocked \
    --json number,body --limit 100 \
    < /dev/null 2>/dev/null || echo "[]")

  local unblock_script
  unblock_script=$(mktemp)
  cat > "$unblock_script" << 'EOF'
import sys, json, subprocess, re

repo        = sys.argv[1]
just_closed = {int(x) for x in sys.argv[2:]}
issues      = json.load(sys.stdin)

for issue in issues:
    body     = issue.get("body") or ""
    blockers = {int(m) for m in re.findall(r'[Bb]locked by #(\d+)', body)}
    if not blockers & just_closed:
        continue
    all_done = all(
        b in just_closed or subprocess.run(
            ["gh", "issue", "view", str(b), "--repo", repo,
             "--json", "state", "--jq", ".state"],
            capture_output=True, text=True, stdin=subprocess.DEVNULL
        ).stdout.strip() == "CLOSED"
        for b in blockers
    )
    if all_done:
        subprocess.run(
            ["gh", "issue", "edit", str(issue["number"]),
             "--repo", repo, "--remove-label", "blocked"],
            stdin=subprocess.DEVNULL
        )
        print(f"  🔓  Unblocked issue #{issue['number']}")
EOF
  echo "$blocked_json" | python3 "$unblock_script" "$REPO" $closed_issues
  rm -f "$unblock_script"
}
