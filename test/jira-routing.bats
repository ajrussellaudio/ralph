#!/usr/bin/env bats
# Tests for the JIRA branch of determine_mode() in lib/routing.sh.
#
# Mock `gh` and `jira` binaries in test/helpers/ are placed first on PATH; they
# read response data from MOCK_* environment variables.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export PATH="$REPO_ROOT/test/helpers:$PATH"

  # shellcheck source=../lib/routing.sh
  source "$REPO_ROOT/lib/routing.sh"

  export REPO="owner/repo"
  # Mirror the derivation done by ralph.sh before sourcing routing.sh so the
  # cross-fork-safe REST endpoint (/repos/${UPSTREAM_REPO}/pulls?head=${FORK_OWNER}:…)
  # is built with real values rather than empty strings.
  export UPSTREAM_REPO="${UPSTREAM_REPO:-$REPO}"
  export FORK_OWNER="${REPO%%/*}"
  export PARENT_TICKET="CAPP-100"
  export PROJECT_KEY="CAPP"
  export TASK_BACKEND="jira"
  export FEATURE_BRANCH="feat/capp-100"
  export FEATURE_LABEL=""
  export REVIEW_BACKEND="comments"
  export MODES_DIR="$REPO_ROOT/modes"
  export RALPH_TESTING=1

  unset MOCK_APPS_RESPONSE MOCK_APPS_EXIT \
        MOCK_REVIEWS_RESPONSE \
        MOCK_PR_LIST_RESPONSE MOCK_FEATURE_PR_LIST_RESPONSE \
        MOCK_PR_VIEW_COMMENTS_RESPONSE MOCK_PR_VIEW_COMMITS_RESPONSE \
        MOCK_ISSUE_LIST_RESPONSE MOCK_ISSUE_VIEW_RESPONSE \
        MOCK_JIRA_ISSUE_LIST_RESPONSE MOCK_JIRA_ISSUE_VIEW_RESPONSE \
        MOCK_JIRA_TRANSITION_LOG \
        MOCK_JIRA_BLOCKERS_CAPP_101 MOCK_JIRA_BLOCKERS_CAPP_102 \
        MOCK_JIRA_BLOCKERS_CAPP_201 MOCK_JIRA_BLOCKERS_CAPP_202 MOCK_JIRA_BLOCKERS_CAPP_203 \
        MOCK_JIRA_BLOCKERS_CAPP_301 MOCK_JIRA_BLOCKERS_CAPP_302 MOCK_JIRA_BLOCKERS_CAPP_303 \
        MODE TASK_ID TASK_TYPE TASK_SUMMARY \
        || true
}

# ─── No open subtasks → feat→main PR check ──────────────────────────────────

@test "jira: no open subtasks + no feat→main PR → feature-pr (no PR number)" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=''
  export MOCK_FEATURE_PR_LIST_RESPONSE='[]'

  determine_mode

  [ "$MODE" = "feature-pr" ]
  [ -z "${FEATURE_PR_NUMBER:-}" ]
  [ -z "${TASK_ID:-}" ]
}

@test "jira: no open subtasks + draft feat→main PR → feature-pr with PR number" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=''
  export MOCK_FEATURE_PR_LIST_RESPONSE='[{"number":7,"draft":true}]'

  determine_mode

  [ "$MODE" = "feature-pr" ]
  [ "$FEATURE_PR_NUMBER" = "7" ]
}

@test "jira: no open subtasks + open ready feat→main PR → complete" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=''
  export MOCK_FEATURE_PR_LIST_RESPONSE='[{"number":7,"draft":false}]'

  determine_mode

  [ "$MODE" = "complete" ]
}

# ─── One open subtask → implement ────────────────────────────────────────────

@test "jira: one open subtask → implement with TASK_ID set" {
  export MOCK_PR_LIST_RESPONSE='[]'
  # TSV: key<TAB>type<TAB>summary
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tTask\tAdd login button'

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$TASK_ID" = "CAPP-101" ]
  [ "$TASK_TYPE" = "Task" ]
  [ "$TASK_SUMMARY" = "Add login button" ]
}

@test "jira: multiple open subtasks → first one wins" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tBug\tFix the thing\nCAPP-102\tStory\tAnother thing'

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$TASK_ID" = "CAPP-101" ]
  [ "$TASK_TYPE" = "Bug" ]
}

# ─── PR identification: --author @me filter ──────────────────────────────────

@test "jira: PR list filter excludes other authors' open PRs" {
  # Mock_gh ignores --author entirely (treats it as a no-op shift); to verify
  # the filter is in place, we instead check that ralph's branch-pattern jq
  # filter excludes non-matching head branches.
  # Here: a PR exists but its head branch doesn't match the JIRA project key,
  # so determine_mode should fall through to subtask detection.
  export MOCK_PR_LIST_RESPONSE='[{"number":99,"headRefName":"someone/other-branch"}]'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tTask\tHello world'

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$TASK_ID" = "CAPP-101" ]
  [ -z "${PR_NUMBER:-}" ]
}

@test "jira: PR list with matching JIRA branch → existing PR detected" {
  export REVIEW_BACKEND="comments"
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"feat/capp-101-add-login"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[]}'

  determine_mode

  [ "$PR_NUMBER" = "42" ]
  # Without any review or fix comments, comments-backend defaults to "review".
  [ "$MODE" = "review" ]
}

@test "jira: PR list filter excludes branches with non-matching project key" {
  # A different project's PR (DIFF-*) must not be picked up when PROJECT_KEY=CAPP.
  export MOCK_PR_LIST_RESPONSE='[{"number":99,"headRefName":"feat/diff-1-other"}]'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tTask\tHello'

  determine_mode

  [ "$MODE" = "implement" ]
  [ -z "${PR_NUMBER:-}" ]
}

# ─── Priority ordering ───────────────────────────────────────────────────────

@test "jira: highest priority subtask wins across mixed priorities" {
  export MOCK_PR_LIST_RESPONSE='[]'
  # Three subtasks: Low, Highest, Medium — Highest should win regardless of order.
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-201\tTask\tLow one\tLow\nCAPP-202\tTask\tHighest one\tHighest\nCAPP-203\tTask\tMedium one\tMedium'

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$TASK_ID" = "CAPP-202" ]
  [ "$TASK_TYPE" = "Task" ]
  [ "$TASK_SUMMARY" = "Highest one" ]
}

@test "jira: ticket-key tie-break within same priority (ascending)" {
  export MOCK_PR_LIST_RESPONSE='[]'
  # All High; lowest key (CAPP-301) should win.
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-303\tTask\tThree\tHigh\nCAPP-301\tTask\tOne\tHigh\nCAPP-302\tTask\tTwo\tHigh'

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$TASK_ID" = "CAPP-301" ]
  [ "$TASK_SUMMARY" = "One" ]
}

# ─── Blocker filtering ───────────────────────────────────────────────────────

@test "jira: subtask with open 'is blocked by' link to non-Done ticket is skipped" {
  export MOCK_PR_LIST_RESPONSE='[]'
  # CAPP-101 is highest priority but blocked by an open ticket → CAPP-102 wins.
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tTask\tBlocked one\tHighest\nCAPP-102\tTask\tFree one\tMedium'
  export MOCK_JIRA_BLOCKERS_CAPP_101="CAPP-999"

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$TASK_ID" = "CAPP-102" ]
  [ "$TASK_SUMMARY" = "Free one" ]
}

@test "jira: subtask becomes eligible once its blocker is Done" {
  export MOCK_PR_LIST_RESPONSE='[]'
  # Same setup as above, but the blocker is now Done — JQL filter (statusCategory
  # != Done) returns no rows for CAPP-101's blockers, so it becomes eligible
  # and (being Highest priority) wins over CAPP-102.
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tTask\tWas blocked\tHighest\nCAPP-102\tTask\tFree one\tMedium'
  export MOCK_JIRA_BLOCKERS_CAPP_101=""

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$TASK_ID" = "CAPP-101" ]
  [ "$TASK_SUMMARY" = "Was blocked" ]
}

@test "jira: all open subtasks blocked → MODE unset (falls through to no-subtasks branch)" {
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_JIRA_ISSUE_LIST_RESPONSE=$'CAPP-101\tTask\tOne\tHigh\nCAPP-102\tTask\tTwo\tMedium'
  export MOCK_JIRA_BLOCKERS_CAPP_101="CAPP-998"
  export MOCK_JIRA_BLOCKERS_CAPP_102="CAPP-999"

  determine_mode

  [ -z "${MODE:-}" ]
  [ -z "${TASK_ID:-}" ]
}

# ─── Merge cycle (review backend = comments) ─────────────────────────────────

@test "jira (comments): open Ralph PR + APPROVED → merge" {
  export REVIEW_BACKEND="comments"
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"feat/capp-101-add-login"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[{"body":"<!-- RALPH-REVIEW: APPROVED -->","createdAt":"2024-01-01T00:00:00Z"}]}'

  determine_mode

  [ "$MODE" = "merge" ]
  [ "$PR_NUMBER" = "42" ]
}

@test "jira (comments): CHANGES_REQUESTED with no commits since → fix" {
  export REVIEW_BACKEND="comments"
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"feat/capp-101-add-login"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[{"body":"<!-- RALPH-REVIEW: REQUEST_CHANGES -->","createdAt":"2024-01-02T00:00:00Z"}]}'
  export MOCK_PR_VIEW_COMMITS_RESPONSE='{"commits":[{"committedDate":"2024-01-01T00:00:00Z"}]}'

  determine_mode

  [ "$MODE" = "fix" ]
  [ "$PR_NUMBER" = "42" ]
}

@test "jira (comments): CHANGES_REQUESTED with newer commit → review" {
  export REVIEW_BACKEND="comments"
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"feat/capp-101-add-login"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[{"body":"<!-- RALPH-REVIEW: REQUEST_CHANGES -->","createdAt":"2024-01-01T00:00:00Z"}]}'
  export MOCK_PR_VIEW_COMMITS_RESPONSE='{"commits":[{"committedDate":"2024-01-02T00:00:00Z"}]}'

  determine_mode

  [ "$MODE" = "review" ]
  [ "$PR_NUMBER" = "42" ]
}

# ─── Merge cycle (review backend = copilot) ──────────────────────────────────

@test "jira (copilot): open Ralph PR + APPROVED → merge" {
  export REVIEW_BACKEND="copilot"
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"feat/capp-101-add-login"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[]}'
  export MOCK_REVIEWS_RESPONSE='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","submitted_at":"2024-01-02T00:00:00Z"}]'

  determine_mode

  [ "$MODE" = "merge" ]
  [ "$PR_NUMBER" = "42" ]
}

@test "jira (copilot): CHANGES_REQUESTED with no fix-bot since → fix-bot" {
  export REVIEW_BACKEND="copilot"
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"feat/capp-101-add-login"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[]}'
  export MOCK_REVIEWS_RESPONSE='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"CHANGES_REQUESTED","submitted_at":"2024-01-02T00:00:00Z"}]'

  determine_mode

  [ "$MODE" = "fix-bot" ]
  [ "$PR_NUMBER" = "42" ]
}
