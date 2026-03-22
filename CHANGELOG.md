# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `--label=<label>` flag to `ralph.sh`; derives `FEATURE_BRANCH=feat/<label>` and `FEATURE_LABEL=prd/<label>` (#6)
- Auto-creates `feat/<label>` on `origin` from `origin/main` if it does not yet exist (#6)
- `{{FEATURE_BRANCH}}` placeholder substitution in `build_prompt()`; resolves to `main` when no `--label` is given (#6)

### Changed
- Worktree and `determine_mode()` sync now use `origin/$FEATURE_BRANCH` instead of always `origin/main` (#6)

### Removed
- `permanent_issue` removed from `project.toml`, `project.example.toml`, `ralph.sh` parsing, and `build_prompt()` substitution (#6)

### Fixed
- Label filtering in `determine_mode()` used jq `contains`, which does substring matching on strings; a label like `prd/feature-branch-workflow` was incorrectly treated as matching `prd` and excluded from the work queue. Replaced with `any(. == "label")` for exact equality matching on all three label checks (`prd`, `blocked`, `high priority`).

### Removed
- Redundant "Step 0 — Sync workspace" block from all mode files (`fix.md`, `force-approve.md`, `implement.md`, `merge.md`, `review.md`, `review-round2.md`); `ralph.sh` already syncs the worktree before building any prompt (#2)
