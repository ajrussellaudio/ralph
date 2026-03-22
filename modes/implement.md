# Ralph — Implement Mode

You are implementing task #{{TASK_ID}} from the local task database.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Get up to speed

Read the task details from the DB:

```bash
sqlite3 {{DB_PATH}} "SELECT title FROM tasks WHERE id={{TASK_ID}};"
sqlite3 {{DB_PATH}} "SELECT body FROM tasks WHERE id={{TASK_ID}};"
```

PRD overview:

> {{PRD_OVERVIEW}}

- Run `git log --oneline -10` to see recent commits.

## Step 2 — Implement

- Check out a new local branch: `git checkout -b ralph/task-{{TASK_ID}}`
- Implement everything required to satisfy all acceptance criteria.
- Delegate expensive work to sub-agents where possible (running the test suite, reading large files, summarising command output) to keep your primary context window lean.

## Step 3 — Verify

Run `{{BUILD_CMD}}` (skip if empty) and `{{TEST_CMD}}` using a sub-agent. **Both must pass before you continue.**

If either check fails and you cannot fix it after a genuine effort, **do not commit**. Instead:

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
- Add an entry under `## [Unreleased]` using the appropriate subsection (`### Added`, `### Changed`, `### Fixed`, `### Removed`). One concise bullet per logical change. Include the task ID in parentheses, e.g.:
  ```
  ### Added
  - Quit confirmation modal when there are unsaved changes (task #5)
  ```
- If `## [Unreleased]` already exists, append to the correct subsection (or create it if needed). Do not create a new `## [Unreleased]` block.
- Do not add version headers or dates.

**Commit** all changes (code + CHANGELOG) together using conventional commits (`feat:`, `fix:`, `chore:`, `refactor:`).

**Do not** `git push` or `gh pr create`.

## Step 5 — Update DB status

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='needs_review', branch='ralph/task-{{TASK_ID}}' WHERE id={{TASK_ID}};"
```

## Step 6 — Stop

Your work this iteration is done.

Emit this token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
