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

## Step 3 — Investigate and address each issue

Go through each review issue **one by one**. For each issue, investigate whether it is a genuine problem in the code:

- **If the issue is real:** fix it.
- **If the issue does not exist** (hallucinated, stale, or not applicable): do NOT make speculative changes. Instead, prepare a DISPUTED rebuttal with concrete evidence (e.g. cite the line that already handles it, the test that already covers it, or why the scenario is impossible).

After addressing all issues, build a **structured summary** tagging each issue as FIXED or DISPUTED:

```
Issue 1: "<original issue summary>" — FIXED: <brief description of what you changed>
Issue 2: "<original issue summary>" — DISPUTED: <concrete evidence why this is not an issue>
Issue 3: "<original issue summary>" — FIXED: <brief description of what you changed>
```

If you made any code changes, run `{{TEST_CMD}}` using a sub-agent. Fix any test failures before continuing.

## Step 4 — Commit, push, and comment

If you made code changes:

```bash
git add -A
git commit -m "fix: address review comments on PR #{{PR_NUMBER}}"
git push origin <branch-name>
```

If all issues were DISPUTED (no code changes), skip the commit and push above.

Now post a comment on the PR with your FIXED/DISPUTED summary so the reviewer has context:

```bash
cat > /tmp/ralph-fix-response.md << 'EOF'
<!-- RALPH-FIX: RESPONSE -->

<paste the structured FIXED/DISPUTED summary here>

— Ralph 🤖
EOF
gh pr comment {{PR_NUMBER}} --repo {{REPO}} --body-file /tmp/ralph-fix-response.md < /dev/null
rm /tmp/ralph-fix-response.md
```

## Step 5 — Stop

Emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>
