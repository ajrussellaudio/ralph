#!/usr/bin/env bats
# Tests for detect_review_backend() and determine_mode() in lib/routing.sh.
#
# A mock gh binary in test/helpers/ is placed first on PATH; it reads response
# data from MOCK_* environment variables and applies any --jq filter via real jq.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  export PATH="$REPO_ROOT/test/helpers:$PATH"

  # Source routing functions into this shell.
  # shellcheck source=../lib/routing.sh
  source "$REPO_ROOT/lib/routing.sh"

  # Common defaults — individual tests override as needed.
  export REPO="owner/repo"
  export FEATURE_BRANCH="feat/now-with-forks"
  export FEATURE_LABEL=""
  export MODES_DIR="$REPO_ROOT/modes"
  export RALPH_TESTING=1

  # Clear all mock env vars so tests start from a clean slate.
  unset MOCK_APPS_RESPONSE  MOCK_APPS_EXIT \
        MOCK_REVIEWS_RESPONSE \
        MOCK_PR_LIST_RESPONSE  MOCK_FEATURE_PR_LIST_RESPONSE \
        MOCK_PR_VIEW_COMMENTS_RESPONSE  MOCK_PR_VIEW_COMMITS_RESPONSE \
        MOCK_ISSUE_LIST_RESPONSE \
        || true
}

# ─── detect_review_backend ────────────────────────────────────────────────────

@test "detect_review_backend: copilot app present → REVIEW_BACKEND=copilot" {
  export MOCK_APPS_RESPONSE='[{"slug":"copilot-pull-request-reviewer"},{"slug":"other-app"}]'
  detect_review_backend
  [ "$REVIEW_BACKEND" = "copilot" ]
}

@test "detect_review_backend: copilot app absent → REVIEW_BACKEND=comments" {
  export MOCK_APPS_RESPONSE='[{"slug":"some-other-app"}]'
  detect_review_backend
  [ "$REVIEW_BACKEND" = "comments" ]
}

@test "detect_review_backend: API call fails → REVIEW_BACKEND=comments" {
  export MOCK_APPS_EXIT=1
  detect_review_backend
  [ "$REVIEW_BACKEND" = "comments" ]
}

# ─── determine_mode: REVIEW_BACKEND=copilot ───────────────────────────────────

@test "copilot: open PR, no review yet → wait" {
  export REVIEW_BACKEND=copilot
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"ralph/issue-42"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[]}'
  export MOCK_REVIEWS_RESPONSE='[]'

  determine_mode

  [ "$MODE" = "wait" ]
  [ "$PR_NUMBER" = "42" ]
}

@test "copilot: open PR, review APPROVED → merge" {
  export REVIEW_BACKEND=copilot
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"ralph/issue-42"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[]}'
  export MOCK_REVIEWS_RESPONSE='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED","submitted_at":"2024-01-02T00:00:00Z"}]'

  determine_mode

  [ "$MODE" = "merge" ]
  [ "$PR_NUMBER" = "42" ]
}

@test "copilot: CHANGES_REQUESTED, fix_count=3 → fix-bot" {
  export REVIEW_BACKEND=copilot
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"ralph/issue-42"}]'
  # 3 fix-bot response comments posted before the review (Jan 1); review is Jan 2.
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-01T01:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-01T02:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-01T03:00:00Z"}
  ]}'
  export MOCK_REVIEWS_RESPONSE='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"CHANGES_REQUESTED","submitted_at":"2024-01-02T00:00:00Z"}]'

  determine_mode

  [ "$MODE" = "fix-bot" ]
}

@test "copilot: CHANGES_REQUESTED, fix_count=10 → escalate" {
  export REVIEW_BACKEND=copilot
  export MOCK_PR_LIST_RESPONSE='[{"number":42,"headRefName":"ralph/issue-42"}]'
  # 10 fix-bot response comments posted before the review (Jan 1-10); review is Jan 11.
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-01T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-02T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-03T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-04T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-05T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-06T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-07T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-08T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-09T00:00:00Z"},
    {"body":"<!-- RALPH-FIX-BOT: RESPONSE -->","createdAt":"2024-01-10T00:00:00Z"}
  ]}'
  export MOCK_REVIEWS_RESPONSE='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"CHANGES_REQUESTED","submitted_at":"2024-01-11T00:00:00Z"}]'

  determine_mode

  [ "$MODE" = "escalate" ]
}

@test "copilot: no open PRs, open issue → implement" {
  export REVIEW_BACKEND=copilot
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[{"number":5,"labels":[]}]'

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$ISSUE_NUMBER" = "5" ]
}

@test "copilot: no open PRs, no open issues, no feat→main PR → feature-pr" {
  export REVIEW_BACKEND=copilot
  export FEATURE_LABEL="prd/now-with-forks"
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[]'
  export MOCK_FEATURE_PR_LIST_RESPONSE='[]'

  determine_mode

  [ "$MODE" = "feature-pr" ]
}

# ─── determine_mode: REVIEW_BACKEND=comments ─────────────────────────────────

@test "comments: open PR, APPROVED comment → merge" {
  export REVIEW_BACKEND=comments
  export MOCK_PR_LIST_RESPONSE='[{"number":7,"headRefName":"ralph/issue-7"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[
    {"body":"RALPH-REVIEW: APPROVED","createdAt":"2024-01-01T00:00:00Z"}
  ]}'

  determine_mode

  [ "$MODE" = "merge" ]
  [ "$PR_NUMBER" = "7" ]
}

@test "comments: open PR, REQUEST_CHANGES x1, no new commits → fix" {
  export REVIEW_BACKEND=comments
  export MOCK_PR_LIST_RESPONSE='[{"number":7,"headRefName":"ralph/issue-7"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[
    {"body":"RALPH-REVIEW: REQUEST_CHANGES","createdAt":"2024-01-02T00:00:00Z"}
  ]}'
  # Last commit is before the review request.
  export MOCK_PR_VIEW_COMMITS_RESPONSE='{"commits":[{"committedDate":"2024-01-01T00:00:00Z"}]}'

  determine_mode

  [ "$MODE" = "fix" ]
}

@test "comments: open PR, REQUEST_CHANGES x1, new commits after review → review-round2" {
  export REVIEW_BACKEND=comments
  export MOCK_PR_LIST_RESPONSE='[{"number":7,"headRefName":"ralph/issue-7"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[
    {"body":"RALPH-REVIEW: REQUEST_CHANGES","createdAt":"2024-01-01T00:00:00Z"}
  ]}'
  # Last commit is after the review request.
  export MOCK_PR_VIEW_COMMITS_RESPONSE='{"commits":[{"committedDate":"2024-01-02T00:00:00Z"}]}'

  determine_mode

  [ "$MODE" = "review-round2" ]
}

@test "comments: open PR, REQUEST_CHANGES x2 → force-approve" {
  export REVIEW_BACKEND=comments
  export MOCK_PR_LIST_RESPONSE='[{"number":7,"headRefName":"ralph/issue-7"}]'
  export MOCK_PR_VIEW_COMMENTS_RESPONSE='{"comments":[
    {"body":"RALPH-REVIEW: REQUEST_CHANGES","createdAt":"2024-01-01T00:00:00Z"},
    {"body":"RALPH-REVIEW: REQUEST_CHANGES","createdAt":"2024-01-02T00:00:00Z"}
  ]}'

  determine_mode

  [ "$MODE" = "force-approve" ]
}

@test "comments: no open PRs, open issue → implement" {
  export REVIEW_BACKEND=comments
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[{"number":9,"labels":[]}]'

  determine_mode

  [ "$MODE" = "implement" ]
  [ "$ISSUE_NUMBER" = "9" ]
}

@test "comments: no open PRs, no open issues → complete" {
  export REVIEW_BACKEND=comments
  export MOCK_PR_LIST_RESPONSE='[]'
  export MOCK_ISSUE_LIST_RESPONSE='[]'

  determine_mode

  [ "$MODE" = "complete" ]
}
