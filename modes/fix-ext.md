# Ralph — Fix Mode (External Review)

PR #{{PR_NUMBER}} in `{{REPO}}` has review comments from Copilot that need fixing.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read review comments

Fetch all inline review comments from `copilot-pull-request-reviewer[bot]` on the PR:

```bash
gh api "/repos/{{OWNER}}/{{REPO_NAME}}/pulls/{{PR_NUMBER}}/comments" \
  --jq '[ .[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {path, line: (.line // .original_line), side, body} ]' \
  < /dev/null
```

This returns an array of objects, each with:
- `path` — the file path relative to the repo root
- `line` — the line number in the file the comment refers to
- `body` — the review comment text describing the issue

Read **every** comment. You must address all of them in one pass.

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

## Step 3 — Fix each issue

Go through each review comment **one by one**:

1. Open the file at the given path
2. Navigate to the referenced line number
3. Read the comment body to understand what Copilot flagged
4. Fix the issue in the code

Do **not** post FIXED/DISPUTED responses — Copilot is stateless and does not read reply comments.

## Step 4 — Verify

Run `{{BUILD_CMD}}` (skip if empty) and `{{TEST_CMD}}` (skip if empty) using a sub-agent. Both must pass before you continue.

If either check fails, fix the failures before proceeding.

## Step 5 — Commit and push

```bash
git add -A
git commit -m "fix: address Copilot review comments on PR #{{PR_NUMBER}}"
git push origin <branch-name>
```

## Step 6 — Stop

Your work this iteration is done. Do **not** request another review or merge — the outer loop handles that.

Emit this token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
