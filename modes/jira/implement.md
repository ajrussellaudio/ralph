# Ralph — Implement Mode (JIRA)

You are implementing JIRA ticket `{{TASK_ID}}` (a subtask of `{{PARENT_TICKET}}`) in the `{{REPO}}` repository.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Get up to speed

- Run `git log --oneline -10` to see recent commits.
- Read ticket `{{TASK_ID}}` using `jira issue view {{TASK_ID}}`. The acceptance criteria in the ticket description are the source of truth.
- If helpful, also read the parent ticket `{{PARENT_TICKET}}` for context.

## Step 2 — Implement

- Check out a new branch: `git checkout -b {{BRANCH_PREFIX}}/{{TASK_ID}}-{{TASK_SLUG}}`
- Where practical, write tests before implementation (red → green). Tests should verify behaviour through public interfaces, not implementation details.
- Implement **only** what is required to satisfy the acceptance criteria. Do not refactor, extend, or improve code that is outside the scope of the ticket.
- **Never delete or weaken existing tests** to make them pass. If a pre-existing test is failing, fix the code — not the test.
- Delegate expensive work to sub-agents where possible (running the test suite, reading large files, summarising command output) to keep your primary context window lean.

## Step 3 — Verify

Run `{{BUILD_CMD}}` (skip if empty) and `{{TEST_CMD}}` using a sub-agent. **Both must pass before you continue.**

If either check fails and you cannot fix it after a genuine effort, **do not open a PR**. Instead:

- Revert any broken changes (`git checkout -- .` or `git stash`)
- Emit the following token as your final output and stop:

  <promise>STOP</promise>

## Step 4 — Commit

If the checks passed:

**Before committing**, review exactly what is staged:

```bash
git diff --staged --stat
```

Ensure no unintended files are included (config files, secrets, build artefacts, `.DS_Store`, `ralph.toml`, etc.). Unstage anything that should not be committed.

**Commit** all changes using conventional commits (`feat:`, `fix:`, `chore:`, `refactor:`). Reference the ticket key in the commit message, e.g. `feat({{TASK_ID}}): <summary>`.

**Open a GitHub PR** from `{{BRANCH_PREFIX}}/{{TASK_ID}}-{{TASK_SLUG}}` targeting `{{FEATURE_BRANCH}}`. The PR body should:
- Reference the ticket: `Implements {{TASK_ID}}`
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
