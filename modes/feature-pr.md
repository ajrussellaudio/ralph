# Ralph — Feature PR Mode

All task issues under `{{FEATURE_LABEL}}` are closed and all task PRs have been merged into `{{FEATURE_BRANCH}}`. Your job is to open a pull request from `{{FEATURE_BRANCH}}` to `main` and squash-merge it so the feature lands on `main` as a single commit.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Verify no existing PR

Check whether a `{{FEATURE_BRANCH}} → main` PR already exists:

```bash
gh pr list --repo {{REPO}} --state open --base main --head {{FEATURE_BRANCH}} --json number --jq '.[].number' < /dev/null
```

If one already exists, emit `<promise>STOP</promise>` immediately and do nothing else.

## Step 2 — Gather context

Find the parent PRD issue (the issue labelled both `{{FEATURE_LABEL}}` and `prd`):

```bash
gh issue list --repo {{REPO}} --state all --label "{{FEATURE_LABEL}}" --label "prd" --json number,title --limit 10 < /dev/null
```

Find all task issues closed under `{{FEATURE_LABEL}}` (excluding the PRD root issue itself):

```bash
gh issue list --repo {{REPO}} --state closed --label "{{FEATURE_LABEL}}" --json number,title,labels --limit 100 \
  --jq '[.[] | select(.labels | map(.name) | any(. == "prd") | not)]' < /dev/null
```

## Step 3 — Open the pull request

Compose a PR description that:
- Opens with a one-paragraph summary of what the feature does
- References the parent PRD issue with `Closes #<prd-issue-number>`
- Lists every task issue closed as part of this feature (e.g. `- #12 Short title`)
- Notes any known limitations or rough edges

Then open the PR:

```bash
gh pr create \
  --repo {{REPO}} \
  --base main \
  --head {{FEATURE_BRANCH}} \
  --title "feat(<label>): <short summary>" \
  --body "<PR description>" \
  < /dev/null
```

Replace `<label>` with the short label name (e.g. `foo-widget` from `feat/foo-widget`).

## Step 4 — Squash merge the pull request

Once the PR is open, immediately merge it using squash merge and delete the feature branch:

```bash
gh pr merge --repo {{REPO}} --squash --delete-branch < /dev/null
```

This ensures `main` receives a single squashed commit representing the entire feature, rather than exposing all of Ralph's intermediate working commits (implement, fix, re-review, merge task, etc.).

## Step 5 — Stop

Emit this token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
