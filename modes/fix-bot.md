# Ralph — Fix-Bot Mode

PR #{{PR_NUMBER}} in `{{REPO}}` has `CHANGES_REQUESTED` from `copilot-pull-request-reviewer[bot]`. Fix every inline comment in one pass.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read all inline review comments

Fetch all review comments left by `copilot-pull-request-reviewer[bot]` on PR #{{PR_NUMBER}}:

```bash
gh api "/repos/{{REPO}}/pulls/{{PR_NUMBER}}/comments" \
  --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {path: .path, line: .line, body: .body}]' \
  < /dev/null
```

Read every comment — you must address all of them in one pass.

## Step 2 — Check out the branch

```bash
gh pr view {{PR_NUMBER}} --repo {{REPO}} --json headRefName --jq .headRefName < /dev/null
```

Then check it out:

```bash
git fetch origin
git checkout <branch-name>
```

## Step 3 — Fix each comment

Go through each inline comment one by one and fix the issue described. Do not dispute or skip any comment — the bot is stateless so there is no point negotiating.

After fixing all comments, run `{{TEST_CMD}}` using a sub-agent. Fix any test failures before continuing.

## Step 4 — Commit and push

```bash
git add -A
git commit -m "fix: address Copilot bot review comments on PR #{{PR_NUMBER}}"
git push origin <branch-name>
```

## Step 5 — Post a fix-round marker comment

Post a `<!-- RALPH-FIX-BOT: RESPONSE -->` comment so the outer loop can count fix rounds:

```bash
cat > /tmp/ralph-fix-bot-response-{{PR_NUMBER}}.md << 'EOF'
<!-- RALPH-FIX-BOT: RESPONSE -->

Addressed all Copilot bot review comments. Pushed fixes and re-requesting review.

— Ralph 🤖
EOF
gh pr comment {{PR_NUMBER}} --repo {{REPO}} --body-file /tmp/ralph-fix-bot-response-{{PR_NUMBER}}.md < /dev/null
rm /tmp/ralph-fix-bot-response-{{PR_NUMBER}}.md
```

## Step 6 — Re-request Copilot review

```bash
gh api "/repos/{{REPO}}/pulls/{{PR_NUMBER}}/requested_reviewers" \
  -X POST -f "reviewers[]=copilot-pull-request-reviewer[bot]" < /dev/null
```

## Step 7 — Stop

Emit the following token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
