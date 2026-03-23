#!/bin/bash
# lib/routing.sh — determine_mode() extracted for testability
#
# Required globals (set by ralph.sh or tests):
#   DB_PATH           path to the SQLite database
#   FEATURE_LABEL     e.g. "prd/foo-widget" (empty in standalone mode)
#   FEATURE_BRANCH    e.g. "feat/foo-widget" or "main"
#   REPO              e.g. "owner/repo"
#   WORKTREE_DIR      path to the git worktree (unused when RALPH_SKIP_SYNC=1)
#
# Set RALPH_SKIP_SYNC=1 to skip the git workspace sync step (used in tests).

# Populates MODE and TASK_ID by querying the local SQLite task database.
# MODE is one of: implement | review | review-round2 | fix | force-approve | merge | feature-pr | complete
determine_mode() {
  TASK_ID=""
  PR_NUMBER=""  # kept for compatibility with review.md / fix.md (always empty now)

  if [[ -z "${RALPH_SKIP_SYNC:-}" ]]; then
    echo "  🔄 Syncing workspace…"
    (cd "$WORKTREE_DIR" && git fetch origin && git reset --hard "origin/$FEATURE_BRANCH") > /dev/null 2>&1
  fi

  echo "  🔍 Checking task status in DB…"

  # 1. needs_review → review
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='needs_review' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="review"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 2. approved → merge
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='approved' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="merge"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 3. needs_review_2 → review-round2
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='needs_review_2' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="review-round2"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 4. needs_fix → force-approve (fix_count >= 2) or fix
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='needs_fix' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    local fix_count
    fix_count=$(sqlite3 "$DB_PATH" \
      "SELECT fix_count FROM tasks WHERE id='$TASK_ID';" 2>/dev/null || echo "0")
    if [[ "$fix_count" -ge 2 ]]; then
      MODE="force-approve"
    else
      MODE="fix"
    fi
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 5. in_progress → fix (resume interrupted work)
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks WHERE status='in_progress' ORDER BY id LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="fix"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID — resuming)"
    return
  fi

  # 6. unblocked pending task → implement (high priority first, then lowest id)
  if TASK_ID=$(sqlite3 "$DB_PATH" \
      "SELECT id FROM tasks
       WHERE status='pending'
         AND (blocked_by IS NULL
              OR blocked_by IN (SELECT id FROM tasks WHERE status='done'))
       ORDER BY CASE priority WHEN 'high' THEN 0 ELSE 1 END, id
       LIMIT 1;" 2>/dev/null) \
      && [[ -n "$TASK_ID" ]]; then
    MODE="implement"
    echo "  ▶  Mode: $MODE  (Task #$TASK_ID)"
    return
  fi

  # 7. pending tasks exist but all are blocked → wait
  local blocked_pending_count
  blocked_pending_count=$(sqlite3 "$DB_PATH" \
    "SELECT COUNT(*) FROM tasks
     WHERE status='pending'
       AND blocked_by IS NOT NULL
       AND blocked_by NOT IN (SELECT id FROM tasks WHERE status='done');" 2>/dev/null || echo "0")
  if [[ "$blocked_pending_count" -gt 0 ]]; then
    MODE="complete"
    COMPLETE_REASON="blocked"
    echo "  ⏸  All remaining tasks are blocked — waiting for dependencies to complete."
    return
  fi

  # 8. all tasks done → feature-pr or complete
  local total_tasks done_tasks
  total_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks;" 2>/dev/null || echo "0")
  done_tasks=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM tasks WHERE status='done';" 2>/dev/null || echo "0")

  if [[ "$total_tasks" -gt 0 && "$total_tasks" == "$done_tasks" ]]; then
    if [[ -n "$FEATURE_LABEL" && "$FEATURE_BRANCH" != "main" ]]; then
      FEATURE_PR_COUNT=$(gh pr list --repo "$REPO" --state open \
        --base "main" \
        --head "$FEATURE_BRANCH" \
        --json number --jq 'length' \
        < /dev/null 2>/dev/null || echo "0")

      if [[ "$FEATURE_PR_COUNT" == "0" ]]; then
        MODE="feature-pr"
        echo "  ▶  Mode: $MODE  (all tasks done, opening feat→main PR)"
      else
        MODE="complete"
        echo "  ▶  Mode: $MODE  (feat→main PR already open)"
      fi
    else
      MODE="complete"
      echo "  ▶  Mode: $MODE  (all tasks done)"
    fi
    return
  fi

  # 9. Default fallback
  MODE="complete"
  echo "  ▶  Mode: $MODE  (no actionable tasks)"
}
