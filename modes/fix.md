# Ralph — Fix Mode

PR #{{PR_NUMBER}} in `{{REPO}}` has a `<!-- RALPH-REVIEW: REQUEST_CHANGES -->` comment that needs addressing.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read the review

Use `gh pr view {{PR_NUMBER}} --repo {{REPO}} --comments` or GitHub MCP tools to read the REQUEST_CHANGES comment. Read **every** issue listed — you must address all of them in one pass, not just some.

## Step 2 — Check out the branch

Look up the branch name:

```bash
gh pr view {{PR_NUMBER}} --repo {{REPO}} --json headRefName --jq .headRefName < /dev/null
```

Then check it out:

```bash
git fetch origin
git checkout <branch-name>
```

## Step 3 — Fix

- Implement fixes for every raised issue. Delegate large file reads to sub-agents.
- Run `{{TEST_CMD}}` using a sub-agent. Fix any test failures.

## Step 4 — Commit and push

```bash
git commit -m "fix: address review comments on PR #{{PR_NUMBER}}"
git push origin <branch-name>
```

## Step 5 — Stop

Emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>
