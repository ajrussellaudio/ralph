#!/usr/bin/env bash
# routing.sh — detect_review_backend() and determine_mode()
#
# Sourced by ralph.sh and by bats unit tests (with RALPH_TESTING=1 to skip
# git-worktree sync).
#
# MODE is one of: implement | review | fix | escalate | merge | complete

# Queries the GitHub API for apps installed on the repo and sets REVIEW_BACKEND
# to 'copilot' if copilot-pull-request-reviewer is present, otherwise 'comments'.
# Defaults to 'comments' if the API call fails for any reason.
detect_review_backend() {
  echo "  🔍 Detecting review backend…"

  local found
  found=$(gh api "/repos/${REPO}/apps" \
    --jq '[.[].slug] | any(. == "copilot-pull-request-reviewer")' 2>/dev/null || echo "false")

  if [[ "$found" == "true" ]]; then
    REVIEW_BACKEND="copilot"
    echo "  🤖 Review backend: copilot"
  else
    REVIEW_BACKEND="comments"
    echo "  💬 Review backend: comments"
  fi

  export REVIEW_BACKEND
}

# Populates MODE, PR_NUMBER, ISSUE_NUMBER based on current GitHub state.
# MODE is one of: implement | review | fix | escalate | merge | complete
determine_mode() {
  PR_NUMBER=""
  ISSUE_NUMBER=""

  if [[ "${RALPH_TESTING:-}" != "1" ]]; then
    echo "  🔄 Syncing workspace…"
    (cd "$WORKTREE_DIR" && git fetch origin && git reset --hard "origin/$FEATURE_BRANCH") > /dev/null 2>&1
  fi

  echo "  🔍 Checking for open ralph PRs in ${REPO}…"
  OPEN_RALPH_PRS=$(gh pr list --repo "$REPO" --state open \
    --base "$FEATURE_BRANCH" \
    --json number,headRefName \
    --jq '[.[] | select(.headRefName | startswith("ralph/issue-"))] | sort_by(.number)' \
    < /dev/null 2>/dev/null || echo "[]")

  PR_COUNT=$(echo "$OPEN_RALPH_PRS" | jq length)

  if [[ "$PR_COUNT" -gt 0 ]]; then
    PR_NUMBER=$(echo "$OPEN_RALPH_PRS" | jq -r '.[0].number')

    if [[ "$REVIEW_BACKEND" == "copilot" ]]; then
      # Copilot bot review path: query review state instead of HTML comment sentinels.
      COPILOT_FIX_COMMENTS=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
        --json comments \
        --jq '[.comments[] | select(.body | contains("<!-- RALPH-FIX-BOT: RESPONSE -->"))]' \
        < /dev/null 2>/dev/null || echo "[]")

      FIX_COUNT=$(echo "$COPILOT_FIX_COMMENTS" | jq 'length')
      LAST_FIX_TIME=$(echo "$COPILOT_FIX_COMMENTS" | jq -r 'last | .createdAt // ""')

      COPILOT_REVIEW_JSON=$(gh api "/repos/${REPO}/pulls/${PR_NUMBER}/reviews" \
        --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | last | {state: (.state // ""), submitted_at: (.submitted_at // "")}' \
        < /dev/null 2>/dev/null || echo '{"state":"","submitted_at":""}')

      COPILOT_REVIEW_STATE=$(echo "$COPILOT_REVIEW_JSON" | jq -r '.state')
      LAST_BOT_REVIEW_TIME=$(echo "$COPILOT_REVIEW_JSON" | jq -r '.submitted_at')

      if [[ -z "$COPILOT_REVIEW_STATE" ]]; then
        MODE="wait"
      elif [[ "$COPILOT_REVIEW_STATE" == "APPROVED" ]]; then
        MODE="merge"
      elif [[ "$COPILOT_REVIEW_STATE" == "CHANGES_REQUESTED" ]]; then
        # If a fix-bot response was posted after the last review, treat the old
        # review as addressed and wait for a new one.
        if [[ -n "$LAST_FIX_TIME" && "$LAST_FIX_TIME" > "$LAST_BOT_REVIEW_TIME" ]]; then
          MODE="wait"
        elif [[ "${FIX_COUNT:-0}" -lt 10 ]]; then
          MODE="fix-bot"
        elif [[ -f "${MODES_DIR}/escalate.md" ]]; then
          MODE="escalate"
        else
          echo "  ⚠️  FIX_COUNT >= 10 but modes/escalate.md not found — falling back to wait"
          MODE="wait"
        fi
      else
        # COMMENTED or other non-terminal state — review not yet complete
        MODE="wait"
      fi
    else
      # HTML comment sentinel path.
      COMMENTS_JSON=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
        --json comments \
        < /dev/null 2>/dev/null || echo '{"comments":[]}')

      COMMENT_BODIES=$(echo "$COMMENTS_JSON" | jq -r '[.comments[].body // ""] | join("\n---\n")' || echo "")

      APPROVED=$(echo "$COMMENT_BODIES" | grep -c "RALPH-REVIEW: APPROVED" 2>/dev/null || true)
      CHANGES_REQUESTED=$(echo "$COMMENT_BODIES" | grep -c "RALPH-REVIEW: REQUEST_CHANGES" 2>/dev/null || true)
      FIX_COUNT=$(echo "$COMMENTS_JSON" | jq '[.comments[] | select(.body != null and (.body | contains("<!-- RALPH-FIX: RESPONSE -->"))) ] | length' || echo "0")

      if [[ "${APPROVED:-0}" -gt 0 ]]; then
        MODE="merge"
      elif [[ "${FIX_COUNT:-0}" -ge 10 ]]; then
        MODE="escalate"
      elif [[ "${CHANGES_REQUESTED:-0}" -ge 1 ]]; then
        # If commits were pushed after the last REQUEST_CHANGES comment → review
        # Otherwise → fix mode (no new commits yet)
        LAST_RC_TIME=$(echo "$COMMENTS_JSON" | jq -r '[.comments[] | select(.body != null and (.body | contains("RALPH-REVIEW: REQUEST_CHANGES")))] | last | .createdAt // ""' || echo "")
        LATEST_COMMIT_TIME=$(gh pr view "$PR_NUMBER" --repo "$REPO" \
          --json commits \
          --jq '.commits | last | .committedDate // ""' \
          < /dev/null 2>/dev/null || echo "")

        if [[ -n "$LATEST_COMMIT_TIME" && -n "$LAST_RC_TIME" && "$LATEST_COMMIT_TIME" > "$LAST_RC_TIME" ]]; then
          MODE="review"
        else
          MODE="fix"
        fi
      else
        MODE="review"
      fi
    fi

    echo "  ▶  Mode: $MODE  (PR #$PR_NUMBER)"
  else
    echo "  🔍 No open ralph PRs — checking issues…"

    if [[ -n "${PINNED_ISSUE:-}" ]]; then
      # Single-issue mode: check if the pinned issue is still open.
      PINNED_STATE=$(gh issue view "$PINNED_ISSUE" --repo "$REPO" --json state \
        --jq '.state' < /dev/null 2>/dev/null || echo "")
      if [[ -z "$PINNED_STATE" ]]; then
        echo "  ⚠  Could not determine state of pinned issue #${PINNED_ISSUE} — skipping"
        MODE="complete"
      elif [[ "$PINNED_STATE" == "CLOSED" ]]; then
        MODE="complete"
        echo "  ▶  Mode: $MODE  (pinned issue #${PINNED_ISSUE} is closed)"
      else
        ISSUE_NUMBER="$PINNED_ISSUE"
        MODE="implement"
        echo "  ▶  Mode: $MODE  (Issue #$ISSUE_NUMBER)"
      fi
    # Pick highest-priority open issue: high-priority label first, then lowest number.
    # PRD mode: --label scopes to prd/<label>; exclude the PRD issue itself (prd) and blocked.
    # Standalone mode: no label filter; additionally exclude any issue carrying a prd/* label.
    elif [[ -n "$FEATURE_LABEL" ]]; then
      ISSUE_NUMBER=$(gh issue list --repo "$REPO" --state open \
        --label "$FEATURE_LABEL" \
        --json number,labels --limit 100 \
        --jq '
          [.[] | select(.labels | map(.name) | (any(. == "prd") or any(. == "blocked")) | not)]
          | (
              (map(select(.labels | map(.name) | any(. == "high priority"))) | sort_by(.number) | first)
              // (sort_by(.number) | first)
            )
          | .number // empty
        ' \
        < /dev/null 2>/dev/null || echo "")
    else
      ISSUE_NUMBER=$(gh issue list --repo "$REPO" --state open \
        --json number,labels --limit 100 \
        --jq '
          [.[] | select(.labels | map(.name) | (any(. == "prd") or any(startswith("prd/")) or any(. == "blocked")) | not)]
          | (
              (map(select(.labels | map(.name) | any(. == "high priority"))) | sort_by(.number) | first)
              // (sort_by(.number) | first)
            )
          | .number // empty
        ' \
        < /dev/null 2>/dev/null || echo "")
    fi

    # The following block only runs in normal (non-pinned) mode; pinned issue routing
    # is fully handled above.
    if [[ -z "${PINNED_ISSUE:-}" ]]; then
      if [[ -n "$ISSUE_NUMBER" ]]; then
        MODE="implement"
        echo "  ▶  Mode: $MODE  (Issue #$ISSUE_NUMBER)"
      elif [[ -n "$FEATURE_LABEL" && "$FEATURE_BRANCH" != "main" ]]; then
        # PRD mode with no remaining task issues — check for an existing feat→main PR
        FEATURE_PR_COUNT=$(gh pr list --repo "$REPO" --state open \
          --base "main" \
          --head "$FEATURE_BRANCH" \
          --json number --jq 'length' \
          < /dev/null 2>/dev/null)

        if [[ "$FEATURE_PR_COUNT" == "0" ]]; then
          MODE="feature-pr"
          echo "  ▶  Mode: $MODE  (all task issues closed, opening feat→main PR)"
        else
          MODE="complete"
          echo "  ▶  Mode: $MODE  (feat→main PR already open or check failed)"
        fi
      else
        MODE="complete"
        echo "  ▶  Mode: $MODE  (no open issues or PRs)"
      fi
    fi
  fi
}
