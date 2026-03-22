# Ralph — Review Mode (Round 1)

You are reviewing task #{{TASK_ID}} from the local task database.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read the task details

```bash
TASK_BRANCH=$(sqlite3 {{DB_PATH}} "SELECT branch FROM tasks WHERE id={{TASK_ID}};")
sqlite3 {{DB_PATH}} "SELECT title FROM tasks WHERE id={{TASK_ID}};"
```

## Step 2 — Review

Delegate the review to a sub-agent. Do not review the code yourself.

Launch a **general-purpose sub-agent** with this prompt:

> "Review the local branch `$TASK_BRANCH` against `{{FEATURE_BRANCH}}`.
> Get the diff with: `git diff {{FEATURE_BRANCH}}...$TASK_BRANCH`
> Run the test suite: `{{TEST_CMD}}`
> You are a strict code reviewer with no attachment to this code.
> Surface only: genuine bugs, logic errors, missing test coverage for new behaviour, or security issues.
> Do NOT comment on: style, formatting, naming conventions, or speculative concerns.
> For each issue found, return: file path, approximate line number, a clear description of the problem, and a concrete suggested fix.
> If you find no genuine issues, return exactly the word: LGTM"

**If LGTM:** update the task status to `approved`:

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='approved' WHERE id={{TASK_ID}};"
```

Then emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>

**If issues found:** write the review notes to the DB (escape single quotes as `''`) and update the task status to `needs_fix`:

```bash
sqlite3 {{DB_PATH}} "UPDATE tasks SET status='needs_fix', review_notes='<review notes here>' WHERE id={{TASK_ID}};"
```

Then emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>
