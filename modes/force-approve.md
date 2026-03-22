# Ralph — Force-Approve Mode

Task #{{TASK_ID}} has reached the review round cap. Approve it unconditionally and merge locally.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read the branch name

```bash
TASK_BRANCH=$(sqlite3 {{DB_PATH}} "SELECT branch FROM tasks WHERE id={{TASK_ID}};")
echo "$TASK_BRANCH"
```

If `TASK_BRANCH` is empty, abort:

```bash
if [[ -z "$TASK_BRANCH" ]]; then
  echo "Error: no branch recorded for task {{TASK_ID}} — cannot merge."
  exit 1
fi
```

## Step 2 — Mark task done in DB

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='done', review_notes='' WHERE id={{TASK_ID}};"
```

## Step 3 — Merge locally

Check out the feature branch, ensure it is up to date, then merge:

```bash
git checkout {{FEATURE_BRANCH}}
git fetch origin {{FEATURE_BRANCH}}
git reset --hard origin/{{FEATURE_BRANCH}}
if ! git merge --no-ff "$TASK_BRANCH"; then
  git merge --abort
  echo "Error: merge conflict on task {{TASK_ID}} — resolve manually and re-run."
  exit 1
fi
```

## Step 4 — Delete the task branch

```bash
git push origin --delete "$TASK_BRANCH" 2>/dev/null || true
git branch -d "$TASK_BRANCH"
```

## Step 5 — Push feature branch

```bash
git push origin {{FEATURE_BRANCH}}
```

## Step 6 — Stop

Emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>
