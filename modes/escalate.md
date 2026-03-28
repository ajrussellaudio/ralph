# Ralph — Escalate Mode

PR #{{PR_NUMBER}} in `{{REPO}}` has received `CHANGES_REQUESTED` from `copilot-pull-request-reviewer[bot]` after 10 or more fix rounds. Ralph has exhausted its automated fix budget. Escalate to a human reviewer.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Ensure the `needs-human-review` label exists

Create the label on the repo if it does not already exist (the `--force` flag is a no-op if the label is already present):

```bash
gh label create "needs-human-review" \
  --repo {{REPO}} \
  --description "Requires a human reviewer — Ralph has exhausted its fix budget" \
  --color "B60205" \
  --force \
  < /dev/null
```

## Step 2 — Label the PR `needs-human-review`

```bash
gh pr edit {{PR_NUMBER}} --repo {{REPO}} --add-label "needs-human-review" < /dev/null
```

## Step 3 — Find the originating issue number

Look up which issue this PR closes:

```bash
gh pr view {{PR_NUMBER}} --repo {{REPO}} \
  --json closingIssuesReferences \
  --jq '.closingIssuesReferences[].number' \
  < /dev/null
```

If that returns nothing, fall back to parsing the branch name:

```bash
gh pr view {{PR_NUMBER}} --repo {{REPO}} --json headRefName --jq .headRefName < /dev/null
# Branch is ralph/issue-<N> — extract N from the name
```

Call the resolved issue number `<ISSUE_NUMBER>` in the steps below.

## Step 4 — Label the originating issue `blocked`

```bash
gh issue edit <ISSUE_NUMBER> --repo {{REPO}} --add-label "blocked" < /dev/null
```

## Step 5 — Post an escalation comment on the PR

```bash
cat > /tmp/ralph-escalate-{{PR_NUMBER}}.md << 'EOF'
<!-- RALPH-ESCALATE -->

Ralph has made **10 fix rounds** on this PR without receiving an approval from `copilot-pull-request-reviewer[bot]`. The automated fix budget is exhausted.

**A human reviewer is needed.** Please review the remaining inline comments from the Copilot bot, provide guidance, or approve the PR directly.

The originating issue has been labelled `blocked` and will be skipped by Ralph until the label is removed.

— Ralph 🤖
EOF
gh pr comment {{PR_NUMBER}} --repo {{REPO}} --body-file /tmp/ralph-escalate-{{PR_NUMBER}}.md < /dev/null
rm /tmp/ralph-escalate-{{PR_NUMBER}}.md
```

## Step 6 — Stop

Emit the following token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
