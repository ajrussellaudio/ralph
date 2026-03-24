# Ralph — Implement Mode (External Review)

You are implementing a task from a GitHub Projects board in the `{{REPO}}` repository.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Task Description

{{TASK_DESCRIPTION}}

## Step 1 — Get up to speed

- Run `git log --oneline -10` to see recent commits.
- Read the task description above carefully. It is the source of truth for what to implement.

## Step 2 — Implement

- Check out a new branch: `git checkout -b ralph/task-{{TASK_NUMBER}}`
- Implement everything required by the task description.
- Delegate expensive work to sub-agents where possible (running the test suite, reading large files, summarising command output) to keep your primary context window lean.

## Step 3 — Verify

Run `{{BUILD_CMD}}` (skip if empty) and `{{TEST_CMD}}` (skip if empty) using a sub-agent. **Both must pass before you continue.**

If either check fails and you cannot fix it after a genuine effort, **do not open a PR**. Instead:

- Revert any broken changes (`git checkout -- .` or `git stash`)
- Emit the following token as your final output and stop:

  <promise>STOP</promise>

## Step 4 — Update CHANGELOG and commit

If the checks passed:

**Update `CHANGELOG.md`** in the repo root before committing:

- If `CHANGELOG.md` does not exist, create it with this header:
  ```
  # Changelog

  All notable changes to this project will be documented in this file.

  The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

  ## [Unreleased]
  ```
- Add an entry under `## [Unreleased]` using the appropriate subsection (`### Added`, `### Changed`, `### Fixed`, `### Removed`). One concise bullet per logical change.
- If `## [Unreleased]` already exists, append to the correct subsection (or create it if needed). Do not create a new `## [Unreleased]` block.
- Do not add version headers or dates.

**Commit** all changes (code + CHANGELOG) together using conventional commits (`feat:`, `fix:`, `chore:`, `refactor:`).

**Open a GitHub PR** from `ralph/task-{{TASK_NUMBER}}` targeting `{{FEATURE_BRANCH}}`. The PR body should:
- Summarise what was implemented
- Reference the task from the project board
- Note any limitations or known rough edges

Do **not** close any GitHub issues manually.

## Step 5 — Stop

Your work this iteration is done.

Emit this token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
