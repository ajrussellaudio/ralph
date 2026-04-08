# Ralph — Feature PR Mode

All task issues under `{{FEATURE_LABEL}}` are closed and all task PRs have been merged into `{{FEATURE_BRANCH}}`. Your job is to open a pull request from `{{FEATURE_BRANCH}}` to `main` for human review.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Existing draft PR

{{FEATURE_PR_SECTION}}

## Step 1 — Gather context

Find the parent PRD issue (the issue labelled both `{{FEATURE_LABEL}}` and `prd`):

```bash
gh issue list --repo {{REPO}} --state all --label "{{FEATURE_LABEL}}" --label "prd" --json number,title --limit 10 < /dev/null
```

Find all task issues closed under `{{FEATURE_LABEL}}` (excluding the PRD root issue itself):

```bash
gh issue list --repo {{REPO}} --state closed --label "{{FEATURE_LABEL}}" --json number,title,labels --limit 100 \
  --jq '[.[] | select(.labels | map(.name) | any(. == "prd") | not)]' < /dev/null
```

## Step 2 — Open or update the pull request

Compose a PR description that:
- Opens with a one-paragraph summary of what the feature does
- References the parent PRD issue with `Closes {{REPO}}#<prd-issue-number>` (cross-repo syntax)
- Lists every task issue closed as part of this feature (e.g. `- {{REPO}}#12 Short title`)
- Notes any known limitations or rough edges

Write the description to a temp file (never use `--body "..."` inline).

**If a draft PR already exists** (see above), update its title and body, then promote it to ready-for-review:

```bash
# Update the title and body
gh pr edit <draft-pr-number> \
  --repo {{UPSTREAM_REPO}} \
  --title "feat(<label>): <short summary>" \
  --body-file <body-file> \
  < /dev/null

# Promote from draft to ready-for-review
gh pr ready <draft-pr-number> --repo {{UPSTREAM_REPO}} < /dev/null
```

**If no draft PR exists**, create a new one:

```bash
gh pr create \
  --repo {{UPSTREAM_REPO}} \
  --base main \
  --head {{FORK_OWNER}}:{{FEATURE_BRANCH}} \
  --title "feat(<label>): <short summary>" \
  --body-file <body-file> \
  < /dev/null
```

Replace `<label>` with the short label name (e.g. `foo-widget` from `feat/foo-widget`).

When composing the PR description, use cross-repo issue-close syntax so the issue on the fork is closed when the upstream PR is merged:
- `Closes {{REPO}}#<prd-issue-number>` (instead of bare `Closes #<number>`)

## ⚠️ Critical constraint

**You must never review, approve, or merge this PR.** Your role ends the moment the PR is opened. This PR is for human review only. Do not request a review, do not approve it, and do not merge it under any circumstances.

## Step 3 — Complete

Emit this token as your **final output** and stop:

<promise>COMPLETE</promise>

Any output after this token violates the rules.
