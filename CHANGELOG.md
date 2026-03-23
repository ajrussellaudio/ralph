# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `test/routing.bats`: bats test suite covering all `determine_mode()` routing cases — pending→implement, needs_review→review, needs_fix (fix_count=0)→fix, needs_fix (fix_count≥2)→force-approve, needs_review_2→review-round2, all-done→feature-pr/complete, blocked-pending→complete, high-priority selection (#27)
- `test/seeding.bats`: bats test suite for `tasks.md` parsing — row count, title/priority/status fields, `blocked_by` mapping, NULL blocked_by, idempotency, and missing-file error (#27)
- `test/test_helper.bash`: shared bats helpers for creating test DBs and inserting task rows (#27)
- `lib/routing.sh`: `determine_mode()` extracted from `ralph.sh` into its own file; supports `RALPH_SKIP_SYNC=1` env var to skip git workspace sync during tests (#27)
- `lib/seed.py`: seeding Python script extracted from `modes/seed.md` into a standalone CLI script (`python3 lib/seed.py <tasks_file> <db_path> <label_slug>`) (#27)
- `{{RALPH_DIR}}` placeholder substitution in `build_prompt()` (resolves to the Ralph installation directory) (#27)
- `## Running tests` section in README documenting `brew install bats-core` and `bats test/` (#27)
- `lib/routing.sh`, `lib/seed.py`, and `test/` added to the Files table in README (#27)

### Added
- `tasks.example.md` updated with all four task patterns: high-priority with acceptance criteria, normal priority, blocked-by dependency, and a fourth task; annotated with YAML comments and an HTML comment field reference (#26)
- `## Authoring tasks.md` section in README documenting the `tasks.md` format (front matter fields, task headings, priority, blocked-by) (#26)
- `## Storage` section in README explaining where `ralph.db` and `tasks.md` live (`~/.ralph/projects/<owner>-<repo>/<label>/`) (#26)
- `sqlite3` listed as a requirement in README (#26)
- `tasks.example.md` added to the Files table in README (#26)
- `blocked_by` dependency enforcement in `determine_mode()`: tasks whose `blocked_by` dependency is not `done` are skipped; when all pending tasks are blocked, Ralph exits with a clear "blocked" message (exit 1) rather than falsely declaring complete (#25)
- `modes/merge.md`: after marking a task `done`, queries for tasks blocked by it and emits a `🔓 Task N is now unblocked.` log line for each (#25)
- `fix_count INTEGER DEFAULT 0` column on `tasks` table; existing DBs migrated via `ALTER TABLE` on startup (#24)
- `force-approve` routing: when `status='needs_fix'` and `fix_count >= 2`, `determine_mode()` routes to `force-approve` instead of `fix` (#24)
- `modes/seed.md`: new mode that parses `tasks.md` and populates the DB on first run (#22)
- `tasks.example.md`: reference example showing the `tasks.md` format (#22)
- `seed_if_empty()` in `ralph.sh`: checks if the tasks table is empty before the main loop; exits with a clear error (including the expected path) if `tasks.md` is missing, otherwise invokes the seed mode (#22)
- `{{LABEL_SLUG}}` placeholder substitution in `build_prompt()` (#22)
- `modes/feature-pr.md`: new mode that opens a `feat/<label> → main` PR when all task issues are closed and all task PRs are merged; includes explicit instruction never to review, approve, or merge the PR (#9)
- `determine_mode()` in PRD mode: after no open task issues, checks for an existing `feat/<label> → main` PR — sets `MODE=feature-pr` if none exists, `MODE=complete` if one is already open (#9)
- `--label=<label>` flag to `ralph.sh`; derives `FEATURE_BRANCH=feat/<label>` and `FEATURE_LABEL=prd/<label>` (#6)
- Auto-creates `feat/<label>` on `origin` from `origin/main` if it does not yet exist (#6)
- `{{FEATURE_BRANCH}}` placeholder substitution in `build_prompt()`; resolves to `main` when no `--label` is given (#6)
- Preflight validation in PRD mode: exits non-zero with a clear diagnostic if no `prd/<label>` issues exist and `feat/<label>` branch does not exist on origin (#7)
- `sqlite3` preflight check: `ralph` exits with a clear error if `sqlite3` is not found in PATH (#21)
- Storage path derivation: `~/.ralph/projects/<repo-slug>/<label-slug>/` created automatically on startup; defaults to `default` when no `--label` is given (#21)
- `ralph.db` initialised on startup with `prd` and `tasks` tables if the DB does not already exist (#21)
- `{{DB_PATH}}`, `{{TASKS_FILE}}`, `{{TASK_ID}}`, and `{{PRD_OVERVIEW}}` placeholder substitutions in `build_prompt()` (#21)

### Changed
- `modes/seed.md` simplified: the embedded Python script replaced by a one-line call to `lib/seed.py` (#27)
- `ralph.sh` routing logic moved to `lib/routing.sh`; `ralph.sh` now sources it (#27)
- README intro updated to describe the SQLite-based workflow rather than GitHub Issues (#26)
- README Setup section reordered and updated to describe the SQLite workflow as the primary path (#26)
- `modes/force-approve.md` rewritten to mark task `done` in SQLite and do a local `git merge --no-ff` — all `gh pr` calls removed (#24)
- `modes/fix.md` now increments `fix_count` alongside setting `status='needs_review_2'` (#24)
- `modes/review-round2.md` unresolved path now sets `status='needs_fix'` (was `approved`) so the fix/force-approve cycle is triggered correctly (#24)
- `determine_mode()` now queries SQLite task statuses (`needs_review`, `approved`, `needs_review_2`, `needs_fix`, `in_progress`, `pending`) instead of `gh issue list` / `gh pr list`; priority ordering uses `high` priority first then lowest `id` (#23)
- `modes/implement.md` rewritten to read task details from SQLite, create a local-only branch `ralph/task-<id>`, commit, and update DB status to `needs_review` — no `git push` or `gh pr create` (#23)
- `modes/merge.md` rewritten to do a local `git merge --no-ff`, delete the task branch, mark the task `done` in DB, and push only the feature branch — all `gh pr merge`, `gh pr checks`, `gh issue close`, and rebase steps removed (#23)
- `modes/merge.md`: added empty-branch guard — exits with a clear error if the `branch` column is NULL for the task (#23)
- `modes/merge.md`: added conflict handling — runs `git merge --abort` and exits non-zero if `git merge --no-ff` fails (#23)
- `modes/review.md` rewritten to review local task branches via `git diff` and store results in SQLite (`status='approved'` or `status='needs_fix'` + `review_notes`) — `{{PR_NUMBER}}` references removed (#23)
- `modes/fix.md` rewritten to read `review_notes` from SQLite, check out the task branch, fix issues, commit, and set `status='needs_review_2'` — `{{PR_NUMBER}}` references removed (#23)
- `modes/review-round2.md` rewritten to read `review_notes` from SQLite and verify fixes via `git diff` — `{{PR_NUMBER}}` references removed (#23)
- `TASK_ID` is now set directly in `determine_mode()`; `{{TASK_ID}}` placeholder no longer mirrors `ISSUE_NUMBER` (#23)
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
