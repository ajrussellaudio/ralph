# Ralph — Review Mode (Round 2)

You are verifying that round-1 review issues have been fixed for task #{{TASK_ID}}.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read the original issues

```bash
TASK_BRANCH=$(sqlite3 {{DB_PATH}} "SELECT branch FROM tasks WHERE id={{TASK_ID}};")
REVIEW_NOTES=$(sqlite3 {{DB_PATH}} "SELECT review_notes FROM tasks WHERE id={{TASK_ID}};")
echo "$REVIEW_NOTES"
```

## Step 2 — Verify fixes

Delegate verification to a sub-agent. Do **not** re-review the whole diff.

Launch a **general-purpose sub-agent** with this prompt:

> "You are verifying fixes on local branch `$TASK_BRANCH` against `{{FEATURE_BRANCH}}`.
> Get the diff with: `git diff {{FEATURE_BRANCH}}...$TASK_BRANCH`
> Run the test suite: `{{TEST_CMD}}`
> The previous review raised these specific issues:
> <paste the value of REVIEW_NOTES here>
> Check only whether each of those issues has been resolved in the latest diff.
> Do NOT raise new issues — only assess the original ones.
> For each original issue, state: RESOLVED or UNRESOLVED (with a brief reason).
> If all are RESOLVED, return exactly the word: LGTM"

**If LGTM (all resolved):** update the task status to `approved`:

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='approved' WHERE id={{TASK_ID}};"
```

Then emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>

**If any issues are UNRESOLVED:** write only the still-unresolved items to the DB (escape single quotes as `''`) and set status back to `needs_fix` to trigger another fix cycle (or force-approve if the fix cap is reached):

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='needs_fix', review_notes='<unresolved items>' WHERE id={{TASK_ID}};"
```

Then emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>
