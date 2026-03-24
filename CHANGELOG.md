# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed
- `review.md`: LGTM path now sets `status: approved` and commits instead of immediately merging; merge is deferred to `merge` mode (#51)
- `review-round2.md`: LGTM path now sets `status: approved` and commits instead of immediately merging; merge is deferred to `merge` mode (#51)
- `lib/functions.sh`: renumbered routing priorities 2→3 (needs_review_2), 3→4 (needs_fix), 4→5 (in_progress), 5→6 (pending) to make room for new priority 2 (approved) (#51)
- `review_notes` in task file front matter changed from a single overwritten block scalar to an append-only list of `|` block scalars; each review round appends a new entry preserving full history (#50)
- `review.md`: Step 6 now appends a new `|` block scalar entry to the `review_notes` list instead of overwriting it (#50)
- `review-round2.md`: Step 1 now reads and displays all `review_notes` entries for context; Step 6 appends a new entry instead of overwriting (#50)
- `fix.md`: Step 1 now reads only the last entry in `review_notes` as the actionable instruction (#50)
- `plans/example-feature/01-example-task.md`: `review_notes` initialises to `[]` (#50)
- `test/test_helper.bash`: `create_task_file` now always emits `review_notes: []` by default (#50)

### Added
- `lib/functions.sh`: `append_review_note`, `get_last_review_note`, and `get_all_review_notes` helper functions for review notes array manipulation (#50)
- `test/yaml_helpers.bats`: tests for `append_review_note` (empty list, two rounds, colons, multi-line, field preservation, body preservation), `get_last_review_note`, and `get_all_review_notes` (#50)
- `test/yaml_helpers.bats`: bats tests for `get_front_matter_field` with `|` block scalar `review_notes` — empty-string return, no corruption of sibling fields, colons in block scalar content, multiline block scalar content, and two-round append preserving all front matter fields (#52)
- `status: approved` as a distinct intermediate state between review and merge; `determine_mode()` routes `approved → merge` at priority 2 (#51)
- `test/routing.bats`: tests for `approved → merge` routing and priority ordering of `approved` vs `needs_review` and `needs_review_2` (#51)


- `test/routing.bats`: bats test suite covering all `determine_mode()` routing cases — pending→implement, in_progress→fix, needs_review→review, needs_fix (fix_count=0)→fix, needs_fix (fix_count≥2)→force-approve, needs_review_2→review-round2/force-approve, all-done→feature-pr/complete, all-blocked→blocked, priority ordering, and blocked-by dependency skipping (#42)
- `test/yaml_helpers.bats`: bats tests for `get_front_matter_field` (string, integer, list, missing field) and `set_front_matter_field` (update, no side effects on other fields, body preservation, error on missing field) (#42)
- `test/test_helper.bash`: shared bats test helper defining `create_task_file` and sourcing `lib/functions.sh` with minimal required globals (#42)
- `lib/functions.sh`: extracted YAML front matter helpers and routing functions from `ralph.sh` into a standalone sourceable library, enabling bats tests to import only the functions they exercise (#42)
- `ralph.toml`: project configuration file for ralph's self-test workflow; sets `test = "bats test/"` (#42)
- `plans/example-feature.md`: example PRD overview file demonstrating the `plans/` directory structure (#41)
- `plans/example-feature/01-example-task.md`: example task file documenting every YAML front matter field (`status`, `priority`, `blocked_by`, `branch`, `fix_count`, `review_notes`) with inline comments explaining each field and its allowed values (#41)

### Changed
- README: replaced GitHub Issues workflow description with a "Markdown backend" section covering `plans/` directory layout, task file format, all YAML front matter fields, status values, `--label` usage, and full lifecycle (#41)
- README: removed references to `~/.ralph/` installation path and old GitHub Issues-based workflow (#41)

### Added
- `blocked_by` dependency enforcement in `determine_mode()`: pending tasks whose `blocked_by` list contains any task ID not yet `status: done` are skipped; if all remaining pending tasks are blocked, routing exits with a `🚫 blocked` message and exit code 1 rather than looping (#40)
- Step 5 in `merge.md`: after marking a task `done`, scans all other task files for any pending tasks that listed the completed task in their `blocked_by` field and logs which tasks are now unblocked (#40)

### Added
- `review.md` (markdown-backend): reads branch from task file front matter, diffs local task branch against feature branch via sub-agent, writes `review_notes` as a YAML block scalar and sets `status: needs_fix` on issues, or performs local merge and sets `status: done` on approval — no GitHub PR comments (#39)
- `review-round2.md` (markdown-backend): same as `review.md` but also reads prior `review_notes` from front matter as context for the verification sub-agent (#39)
- `fix.md` (markdown-backend): reads `review_notes` and `branch` from task file front matter, checks out the task branch, applies fixes, increments `fix_count`, and sets `status: needs_review_2` (#39)
- `force-approve.md` (markdown-backend): reads branch from task file front matter, performs local merge into feature branch, and sets `status: done` — triggered when `fix_count >= 2` (#39)

### Changed
- Routing in `determine_mode()`: `status: needs_review` now always routes to `review` mode (branch is read from front matter by the mode itself); previously routed to `merge` when `branch` was set (#39)
- Routing in `determine_mode()`: `status: needs_review_2` routes to `force-approve` when `fix_count >= 2`, otherwise to `review-round2`; `status: needs_fix` routes to `force-approve` when `fix_count >= 2`, otherwise to `fix` (#39)
- `fix_count` field from task file front matter is now parsed in the routing script to drive the force-approve escalation (#39)

### Added
- `implement.md` (markdown-backend): reads task body from `{{TASK_FILE}}` and PRD context from `{{PRD_OVERVIEW}}`, creates a local `ralph/task-{{TASK_ID}}` branch (never pushed to remote), sets `status: in_progress` before starting and `status: needs_review` + `branch: ralph/task-{{TASK_ID}}` after committing (#38)
- `merge.md` (markdown-backend): reads the task branch from the task file's YAML front matter, performs a local `git merge --no-ff`, deletes the task branch, and sets `status: done` in the task file (#38)
- Routing in `determine_mode()`: `status: needs_review` with a `branch` field set now routes to `merge` mode (local branch); without a `branch` field it continues to route to `review` mode (PR-based) (#38)


- `get_front_matter_field` and `set_front_matter_field` python3-based helpers in `ralph.sh` to read/write individual YAML front matter fields in task `.md` files (#37)
- `determine_mode()` now scans `./plans/<label>/*.md` sorted by filename, parses YAML front matter, and applies the routing priority: `needs_review` → `review`, `needs_review_2` → `review-round2`, `needs_fix` → `fix`, `in_progress` → `fix` (resume), ready `pending` (high-priority first) → `implement`, all `done` → `feature-pr`, otherwise → `complete` (#37)
- `{{TASK_FILE}}`, `{{TASK_ID}}`, `{{PRD_OVERVIEW}}`, and `{{PLANS_DIR}}` placeholder substitutions in `build_prompt()` (#37)
- Preflight check: exits with a clear error when `./plans/<label>/` does not exist or contains no `.md` files (#37)

### Changed
- `RAW_LABEL` variable added to argument parsing; `PLANS_DIR` derived as `$GIT_ROOT/plans/$RAW_LABEL` (#37)
- Preflight check in label mode now validates the local plans directory instead of checking GitHub Issues (#37)

### Removed
- GitHub Issues and PR-based routing logic from `determine_mode()` — replaced by Markdown/YAML front matter routing (#37)
- `~/.ralph/` path reference removed from error messages (#37)

### Added
- `modes/feature-pr.md`: new mode that opens a `feat/<label> → main` PR when all task issues are closed and all task PRs are merged; includes explicit instruction never to review, approve, or merge the PR (#9)
- `determine_mode()` in PRD mode: after no open task issues, checks for an existing `feat/<label> → main` PR — sets `MODE=feature-pr` if none exists, `MODE=complete` if one is already open (#9)
- `--label=<label>` flag to `ralph.sh`; derives `FEATURE_BRANCH=feat/<label>` and `FEATURE_LABEL=prd/<label>` (#6)
- Auto-creates `feat/<label>` on `origin` from `origin/main` if it does not yet exist (#6)
- `{{FEATURE_BRANCH}}` placeholder substitution in `build_prompt()`; resolves to `main` when no `--label` is given (#6)
- Preflight validation in PRD mode: exits non-zero with a clear diagnostic if no `prd/<label>` issues exist and `feat/<label>` branch does not exist on origin (#7)

### Changed
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
