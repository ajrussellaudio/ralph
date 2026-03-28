# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- `merge.md` now uses `gh pr merge --squash --delete-branch` so per-task PRs are squash-merged into the feature branch and the `ralph/issue-N` remote branch is deleted after merge (#79)

### Added
- `modes/escalate.md`: new mode that ensures the `needs-human-review` label exists, labels the PR `needs-human-review`, labels the originating issue `blocked`, posts an explanatory comment on the PR, and emits STOP so the outer loop skips to the next unblocked task (#78)
- `detect_review_backend()` function in `ralph.sh` that queries the GitHub API at startup, sets `REVIEW_BACKEND` to `copilot` when `copilot-pull-request-reviewer` is installed on the repo, and defaults to `comments` on any API failure or when the app is absent (#76)
- `REVIEW_BACKEND` global exported at startup so all subsequent functions in the run can consume it (#76)
- Copilot bot review routing in `determine_mode()`: when `REVIEW_BACKEND=copilot`, queries the bot review state instead of HTML comment sentinels — no review → `wait`, `APPROVED` → `merge`, `CHANGES_REQUESTED` with fix_count < 10 → `fix-bot`, fix_count >= 10 → `escalate` (#77)
- `fix_count` tracking via `<!-- RALPH-FIX-BOT: RESPONSE -->` comment counting on the copilot bot path (#77)
- `modes/wait.md`: new mode that emits STOP so the outer loop retries on the next iteration while awaiting a Copilot bot review (#77)
- `modes/fix-bot.md`: new mode that reads all inline `copilot-pull-request-reviewer[bot]` comments, fixes them in one pass, commits, pushes, posts a fix-round marker comment, and re-requests Copilot review (#77)
- `{{REVIEW_BACKEND}}` placeholder substitution in `build_prompt()` so mode files can act conditionally on the review backend (#77)
- `lib/routing.sh` extracts `detect_review_backend()` and `determine_mode()` from `ralph.sh` into a separately sourceable library, enabling unit testing (#81)
- `test/routing.bats`: bats tests covering all 3 `detect_review_backend()` cases and the full 12-case `determine_mode()` routing matrix for both `REVIEW_BACKEND=copilot` and `REVIEW_BACKEND=comments`, using a mock `gh` binary in `test/helpers/` (#81)
- `implement.md` Step 4b: requests a Copilot review immediately after opening the PR when `REVIEW_BACKEND=copilot` (#77)
- `escalate_pr()` shell function orchestrating PR labeling, commenting, and project status update on fix threshold breach (#68)
- `ensure_label()` shell function for idempotent label creation on the repo (#68)
- `project_ensure_status_option()` shell function that creates a missing status option (e.g. "Blocked") on the project board's Status field via GraphQL (#68)
- `request_and_poll_review()` helper that encapsulates the request + poll + retry-on-timeout pattern (#68)
- `fix_count` tracking and `MAX_FIX_COUNT` threshold (default 5) for the fix loop — stops with escalation message on breach (#67)
- `request_copilot_review()` and `poll_copilot_review()` shell functions for requesting and polling Copilot PR reviews (#66)
- Reusable shell functions `project_find_board()`, `project_next_todo()`, `project_set_status()` for GitHub Projects V2 GraphQL queries (#64)
- `project_ensure_pr_field()` and `project_set_text_field()` shell functions for creating and setting a "PR" custom text field on a GitHub Projects V2 board (#65)
- `modes/feature-pr.md`: new mode that opens a `feat/<label> → main` PR when all task issues are closed and all task PRs are merged; includes explicit instruction never to review, approve, or merge the PR (#9)
- `determine_mode()` in PRD mode: after no open task issues, checks for an existing `feat/<label> → main` PR — sets `MODE=feature-pr` if none exists, `MODE=complete` if one is already open (#9)
- `--label=<label>` flag to `ralph.sh`; derives `FEATURE_BRANCH=feat/<label>` and `FEATURE_LABEL=prd/<label>` (#6)
- Auto-creates `feat/<label>` on `origin` from `origin/main` if it does not yet exist (#6)
- `{{FEATURE_BRANCH}}` placeholder substitution in `build_prompt()`; resolves to `main` when no `--label` is given (#6)
- Preflight validation in PRD mode: exits non-zero with a clear diagnostic if no `prd/<label>` issues exist and `feat/<label>` branch does not exist on origin (#7)

### Changed
- `handle_review()` refactored from recursive to iterative loop with explicit return codes (0=merged, 2=escalated, 3=budget exhausted) (#68)
- `MAX_FIX_COUNT` raised from 5 to 10 and threshold condition changed to `>=` to match escalation at exactly 10 fix rounds (#68)
- Review comment handling replaced placeholder "fix mode not yet implemented" messages with the full fix→review→fix loop (#67)
- `project_next_todo()` now returns `body` in its JSON output (fetched from both Issue and DraftIssue content fragments) (#65)
- Worktree and `determine_mode()` sync now use `origin/$FEATURE_BRANCH` instead of always `origin/main` (#6)
- PR filter in `determine_mode()` now includes `--base "$FEATURE_BRANCH"` so only PRs targeting the current feature branch are considered (#7)
- Issue filter in PRD mode uses `--label "prd/<label>"` to scope to the current PRD; excludes the PRD issue itself (`prd` label) and `blocked` issues (#7)
- Issue filter in standalone mode additionally excludes any issue carrying a `prd/*` label (#7)
- `implement.md` instructs Copilot to open PRs against `{{FEATURE_BRANCH}}` instead of `main` (#8)
- `merge.md` uses `{{FEATURE_BRANCH}}` as the base in all sync, merge, rebase, and downstream PR filter instructions (#8)

### Removed
- `permanent_issue` removed from `project.toml`, `project.example.toml`, `ralph.sh` parsing, and `build_prompt()` substitution (#6)

### Fixed
- Label filtering in `determine_mode()` used jq `contains`, which does substring matching on strings; a label like `prd/feature-branch-workflow` was incorrectly treated as matching `prd` and excluded from the work queue. Replaced with `any(. == "label")` for exact equality matching on all three label checks (`prd`, `blocked`, `high priority`).
- `merge.md` did not explicitly close the implemented issue after merging. GitHub only auto-closes issues referenced with `Closes #N` when a PR merges into the default branch — merging into a feature branch left the issue open, causing Ralph to loop. Added an explicit `gh issue close` step to `merge.md`.
- Added `⚠️ Never use gh pr comment --body "..."` ground rule immediately after the opening paragraph in all 7 mode files (`fix.md`, `implement.md`, `merge.md`, `review.md`, `review-round2.md`, `force-approve.md`, `feature-pr.md`) to prevent stdin hangs (#16)
- Replaced vague CI-failure prose in `merge.md` Step 1 with the full explicit shell template using `--body-file /tmp/ralph-review.md < /dev/null`, matching the pattern in `review.md` and `review-round2.md` (#16)

### Removed
- Redundant "Step 0 — Sync workspace" block from all mode files (`fix.md`, `force-approve.md`, `implement.md`, `merge.md`, `review.md`, `review-round2.md`); `ralph.sh` already syncs the worktree before building any prompt (#2)
- `ralph-ext.sh`, `modes/implement-ext.md`, and `modes/fix-ext.md` — all useful behaviour absorbed into `ralph.sh`, `fix-bot.md`, `escalate.md`, and `merge.md`; GitHub Projects V2 task tracking intentionally dropped in favour of Issues (#80)
