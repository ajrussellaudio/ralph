# Ralph — Fix Mode

Task #{{TASK_ID}} needs fixes based on review notes in the local task database.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read the review notes

```bash
TASK_BRANCH=$(sqlite3 {{DB_PATH}} "SELECT branch FROM tasks WHERE id={{TASK_ID}};")
REVIEW_NOTES=$(sqlite3 {{DB_PATH}} "SELECT review_notes FROM tasks WHERE id={{TASK_ID}};")
echo "$REVIEW_NOTES"
```

## Step 2 — Check out the branch

```bash
git checkout "$TASK_BRANCH"
```

## Step 3 — Fix

- Implement fixes for every raised issue. Delegate large file reads to sub-agents.
- Run `{{TEST_CMD}}` using a sub-agent. Fix any test failures.

## Step 4 — Commit

```bash
git add -A
git commit -m "fix: address review notes for task #{{TASK_ID}}"
```

## Step 5 — Update DB status

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='needs_review_2' WHERE id={{TASK_ID}};"
```

## Step 6 — Stop

Emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>
