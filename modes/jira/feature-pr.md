# Ralph — Feature PR Mode (JIRA)

All open subtasks of parent ticket `{{PARENT_TICKET}}` are Done and their PRs have been merged into `{{FEATURE_BRANCH}}`. Your job is to open a pull request from `{{FEATURE_BRANCH}}` to `main` for human review.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Existing draft PR

{{FEATURE_PR_SECTION}}

## Step 1 — Gather context

Read the parent ticket for context (title, description, acceptance criteria):

```bash
jira issue view {{PARENT_TICKET}}
```

List every Done subtask of `{{PARENT_TICKET}}` (key + summary). Use `jira-cli` to query subtasks whose parent is `{{PARENT_TICKET}}` and whose status category is Done — for example:

```bash
jira issue list -q 'parent = {{PARENT_TICKET}} AND statusCategory = Done' \
  --plain --no-headers --columns key,summary
```

You will use these in the PR body.

## Step 2 — Open or update the pull request

Compose a PR description that:
- Opens with a one-paragraph summary of what the feature does (derived from the parent ticket).
- References the parent ticket key, e.g. `Parent ticket: {{PARENT_TICKET}}`. **Do not** use `Closes #N` — JIRA tickets are not closed by GitHub keywords.
- Lists every Done subtask of the parent ticket as `- {{PROJECT_KEY}}-NNN Short summary`.
- Notes any known limitations or rough edges.

Write the description to a temp file (never use `--body "..."` inline).

**If a draft PR already exists** (see above), update its title and body, then promote it to ready-for-review:

```bash
gh pr edit {{FEATURE_PR_NUMBER}} \
  --repo {{UPSTREAM_REPO}} \
  --title "feat({{PARENT_TICKET}}): <short summary>" \
  --body-file <body-file> \
  < /dev/null

gh pr ready {{FEATURE_PR_NUMBER}} --repo {{UPSTREAM_REPO}} < /dev/null
```

**If no draft PR exists**, create a new one:

```bash
gh pr create \
  --repo {{UPSTREAM_REPO}} \
  --base main \
  --head {{FORK_OWNER}}:{{FEATURE_BRANCH}} \
  --title "feat({{PARENT_TICKET}}): <short summary>" \
  --body-file <body-file> \
  < /dev/null
```

## ⚠️ Critical constraint

**You must never review, approve, or merge this PR.** Your role ends the moment the PR is opened (or promoted from draft to ready). This PR is for human review only. Do not request a review, do not approve it, and do not merge it under any circumstances.

## Step 3 — Complete

Emit this token as your **final output** and stop:

<promise>COMPLETE</promise>

Any output after this token violates the rules.
