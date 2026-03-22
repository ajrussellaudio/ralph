# Ralph — Merge Mode

Task #{{TASK_ID}} has been approved. Merge its local branch into `{{FEATURE_BRANCH}}`.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read the branch name

```bash
TASK_BRANCH=$(sqlite3 {{DB_PATH}} "SELECT branch FROM tasks WHERE id={{TASK_ID}};")
echo "$TASK_BRANCH"
```

## Step 2 — Merge

Check out the feature branch, ensure it is up to date, then merge:

```bash
git checkout {{FEATURE_BRANCH}}
git fetch origin {{FEATURE_BRANCH}}
git reset --hard origin/{{FEATURE_BRANCH}}
git merge --no-ff "$TASK_BRANCH"
```

## Step 3 — Delete the task branch

```bash
git branch -d "$TASK_BRANCH"
```

## Step 4 — Update DB status

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='done' WHERE id={{TASK_ID}};"
```

## Step 5 — Push feature branch

```bash
git push origin {{FEATURE_BRANCH}}
```

## Step 6 — Stop

Emit this token as your **final output** and end your response immediately:

<promise>STOP</promise>
