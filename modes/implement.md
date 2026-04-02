# Ralph — Implement Mode

You are implementing GitHub issue #{{ISSUE_NUMBER}} in the `{{REPO}}` repository.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Get up to speed

- Run `git log --oneline -10` to see recent commits.
- Read issue #{{ISSUE_NUMBER}} using GitHub MCP tools. The acceptance criteria are the source of truth.

## Step 2 — Implement

- Check out a new branch: `git checkout -b ralph/issue-{{ISSUE_NUMBER}}`
- Where practical, write tests before implementation (red → green). Tests should verify behaviour through public interfaces, not implementation details.
- Implement **only** what is required to satisfy the acceptance criteria. Do not refactor, extend, or improve code that is outside the scope of the issue.
- **Never delete or weaken existing tests** to make them pass. If a pre-existing test is failing, fix the code — not the test.
- Delegate expensive work to sub-agents where possible (running the test suite, reading large files, summarising command output) to keep your primary context window lean.

## Step 3 — Verify

Run `{{BUILD_CMD}}` (skip if empty) and `{{TEST_CMD}}` using a sub-agent. **Both must pass before you continue.**

If either check fails and you cannot fix it after a genuine effort, **do not open a PR**. Instead:

- Revert any broken changes (`git checkout -- .` or `git stash`)
- Emit the following token as your final output and stop:

  <promise>STOP</promise>

## Step 4 — Update CHANGELOG and commit

If the checks passed:

**Update `CHANGELOG.md`** in the repo root before committing — but **only if the file already exists**. If there is no `CHANGELOG.md`, log "No CHANGELOG.md found — skipping" and move on.

When updating an existing `CHANGELOG.md`:

- Add an entry under `## [Unreleased]` using the appropriate subsection (`### Added`, `### Changed`, `### Fixed`, `### Removed`). One concise bullet per logical change. Include the issue number in parentheses, e.g.:
  ```
  ### Added
  - Quit confirmation modal when there are unsaved changes (#53)
  ```
- If `## [Unreleased]` already exists, append to the correct subsection (or create it if needed). Do not create a new `## [Unreleased]` block.
- Do not add version headers or dates.

**Before committing**, review exactly what is staged:

```bash
git diff --staged --stat
```

Ensure no unintended files are included (config files, secrets, build artefacts, `.DS_Store`, `ralph.toml`, etc.). Unstage anything that should not be committed.

**Commit** all changes (code + CHANGELOG) together using conventional commits (`feat:`, `fix:`, `chore:`, `refactor:`).

**Open a GitHub PR** from `ralph/issue-{{ISSUE_NUMBER}}` targeting `{{FEATURE_BRANCH}}`. The PR body should:
- Reference the issue with `Closes #{{ISSUE_NUMBER}}`
- Summarise what was implemented
- Note any limitations or known rough edges

## Step 4b — Request Copilot review (bot path only)

**Only if `{{REVIEW_BACKEND}}` is `copilot`:** immediately after opening the PR, request a Copilot review:

```bash
gh api "/repos/{{REPO}}/pulls/<PR_NUMBER>/requested_reviewers" \
  -X POST -f "reviewers[]=copilot-pull-request-reviewer[bot]" < /dev/null
```

Skip this step entirely if `{{REVIEW_BACKEND}}` is `comments`.

## Step 5 — Stop

Your work this iteration is done.

Emit this token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
