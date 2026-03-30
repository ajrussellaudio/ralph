# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `lib/utils.sh` with `gh_with_retry()`: wraps `gh` with up to 3 attempts; sleeps 1 s before attempt 2 and 2 s before attempt 3; prints a ⚠️ warning to stderr on each failed attempt and a ❌ error after exhaustion; forwards all args, stdin, and exit codes transparently (#131)
- `test/utils.bats`: bats tests covering all retry paths — first-attempt success, single retry, full exhaustion, arg forwarding, and stdin forwarding (#131)
- `ralph doctor` subcommand dispatched from `ralph.sh` (#117)
- `test/doctor.bats`: bats tests covering all-pass, each hard failure in isolation, each warning in isolation, multiple simultaneous failures, mix of warnings and failures, and exit code behaviour (#117)
- `lib/init.sh` with `ralph_init()`: guided prompt sequence to scaffold `ralph.toml`; infers `repo` from `gh repo view`; prompts for all four fields with descriptions and defaults; shows file preview in a `━━━` box with `Write this file? [Y/n]` confirmation; writes file with inline comments matching `project.example.toml` style; calls `ralph_doctor()` after a successful write (#122)
- `ralph init` subcommand dispatched from `ralph.sh` (#122)
- `test/init.bats`: bats tests covering all-defaults accepted, user overrides, blank upstream, declined preview, file comments, repo inference, and doctor call (#122)
- Project-type detection in `ralph init`: scans CWD for `package.json`, `go.mod`, `Makefile`, `Cargo.toml` and suggests appropriate `build`/`test` defaults; verifies Makefile targets exist before suggesting them; presents numbered choices when multiple files are detected; user may pick by number or type a custom value (#123)
- `test/init.bats` extended to cover all detection cases: each project file type, Makefile with/without targets, multiple-match numbered list, custom freeform entry, no-match blank default (#123)
- `ralph init` pre-prompt overwrite check: when `ralph.toml` already exists, asks `ralph.toml already exists. Overwrite? [y/N]` before showing any prompts; default is No; declining exits cleanly without modifying the file (#124)
- Non-standard key preservation in `ralph init`: when overwriting an existing `ralph.toml`, any keys not in the standard set (`repo`, `upstream`, `build`, `test`) are carried over to the new file after the standard fields, each preceded by a `# (preserved from previous ralph.toml)` comment (#124)
- `test/init.bats` extended to cover all overwrite and preservation cases: decline with `n`, decline with Enter (default No), accept with `y`, single non-standard key preserved, multiple non-standard keys preserved, preserved keys appear after standard fields (#124)

### Changed
- `ralph run` preflight now calls `ralph_doctor()` instead of the old ad-hoc checks; aborts with exit 1 if any hard failure is found (#118)
- Missing `test` command in `ralph.toml` is now a ⚠️ warning (not a hard error) in both `ralph doctor` and `ralph run` (#118)

- `ralph status` issues section: lists all open in-scope issues with number and title; blocked issues marked with ⚠️; placeholder shown when none (#113)
- `ralph status --label=foo` filters issues to those labelled `prd/foo`; without `--label`, shows all issues excluding `prd/*`-labelled ones (#113)
- `ralph status --label=foo` feature PR section: shows the `feat/foo` → main aggregate PR (number, branch, review state, CI) when one exists; omitted entirely when none (#113)
- `lib/status.sh` with `ralph_status()`: prints open `ralph/issue-*` PRs with review state (APPROVED ✅ / CHANGES_REQUESTED 🔄 / PENDING ⏳) and CI status (passing ✅ / failing ❌ / pending ⏳); shows a placeholder when there are no open PRs (#112)
- `test/status.bats`: 6 bats tests covering approved+passing CI, changes-requested+failing CI, pending review+pending CI, multiple PRs, no open PRs, and header output (#112)
- Subcommand dispatch: `ralph run` starts the agent loop, `ralph status` prints a status stub, `ralph` with no args defaults to `ralph status` (#111)
- Migration error for run-style flags without a subcommand (e.g. `ralph --label=foo`): exits non-zero with a message directing the user to `ralph run` (#111)
- Usage error for unrecognised subcommands (e.g. `ralph unknown`) (#111)
- New `test/arg-parsing.bats` tests covering all subcommand routing cases (#111)
- `--max-iterations=N` optional named flag to `ralph.sh`; when omitted Ralph runs in an unlimited `while true` loop until a clean exit condition is reached (#89)
- Migration error message when a bare positional integer is passed (old interface): `"The positional <max_iterations> argument has been removed. Use --max-iterations=N instead."` (#89)
- `RALPH_PARSE_ONLY=1` test hook in `ralph.sh` to allow arg-parsing bats tests without requiring a full preflight environment (#89)
- `test/arg-parsing.bats`: 9 bats tests covering all arg-parsing scenarios for the new `--max-iterations` flag (#89)

### Changed
- Removed mandatory positional `<max_iterations>` argument from `ralph.sh`; `--max-iterations=N` is now optional (#89)
- Terminal header shows `Max iterations: unlimited` when no cap is set, `Max iterations: N` when `--max-iterations=N` is passed (#89)
- Iteration counter shows `iteration N` when uncapped, `iteration N / M` when capped (#89)
- `usage()` function updated to reflect the new interface (#89)
- README usage examples updated to show the new `--max-iterations=N` flag (#89)

### Changed
- `review.md` now reads all prior `<!-- RALPH-REVIEW: REQUEST_CHANGES -->` and `<!-- RALPH-FIX: RESPONSE -->` comments before delegating to the review sub-agent, providing full multi-round context (#86)
- After a fix (new commits pushed after a `REQUEST_CHANGES` comment), `determine_mode()` HTML path now routes to `review` instead of `review-round2` (#86)
- Force-approve threshold raised from 2 `REQUEST_CHANGES` comments to 10 `<!-- RALPH-FIX: RESPONSE -->` comments (#86)

### Removed
- `modes/review-round2.md` deleted; all post-fix reviews now cycle back through `review.md` (#86)

### Fixed
- `toml_get` no longer silently exits the script when a TOML key is missing; appended `|| true` to the `grep | sed` pipeline so a no-match is not fatal under `set -euo pipefail` (#82)

### Added
- Empty init commit (`chore: initialise feat/<label>`) pushed to the new feature branch before opening the draft PR, ensuring GitHub can create the PR and the branch is immediately distinguishable from `main` (#104)
- Draft PR opened automatically on GitHub when `ralph.sh` creates a new feature branch (`feat/`), giving instant visibility that work has started; skipped when resuming an existing branch (#98)
- `feature-pr` mode now detects an existing draft PR for the feature branch, updates its title and body with the full feature summary, and promotes it from draft to ready-for-review using `gh pr ready`; falls back to creating a new PR if no draft exists (#98)

- `--issue=<N>` flag to `ralph.sh` to pin Ralph to a single specific issue, skipping normal label-based routing; when the issue's PR is merged and closed, Ralph exits cleanly without opening a feature PR (#96)
- Pinned-issue routing in `determine_mode()` in `lib/routing.sh`: when `PINNED_ISSUE` is set, checks the issue state directly and routes to `implement` (open) or `complete` (closed) (#96)
- Preflight check in `ralph.sh` that exits immediately with a clear message if the pinned issue is already closed (#96)
- `gh issue view` support in `test/helpers/gh` mock binary via `MOCK_ISSUE_VIEW_RESPONSE` (#96)
- Four bats test cases for `PINNED_ISSUE` routing scenarios in `test/routing.bats` (#96)

- `upstream` config key in `project.example.toml` for fork-based workflows; when set, the final feature PR is opened against the upstream repo instead of the fork (#93)
- `UPSTREAM_REPO` variable in `ralph.sh` (defaults to `$REPO` when `upstream` is unset, preserving existing behaviour) (#93)
- `FORK_OWNER` variable derived from the owner prefix of `$REPO` (#93)
- `{{UPSTREAM_REPO}}` and `{{FORK_OWNER}}` placeholder substitutions in `build_prompt()` (#93)
- Fork-based workflow documentation in `README.md` (#93)

### Changed
- `modes/feature-pr.md` now checks for an existing PR against `{{UPSTREAM_REPO}}` with head `{{FORK_OWNER}}:{{FEATURE_BRANCH}}`, opens the PR with `--repo {{UPSTREAM_REPO}} --head {{FORK_OWNER}}:{{FEATURE_BRANCH}}`, and uses cross-repo `Closes {{REPO}}#` syntax in the PR body (#93)
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
