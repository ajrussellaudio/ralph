# Ralph — Merge Mode

Task `{{TASK_ID}}` in `{{PLANS_DIR}}` is ready to merge into `{{FEATURE_BRANCH}}`.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Read the task branch name

Read the `branch` field from `{{TASK_FILE}}`'s YAML front matter:

```bash
python3 - <<'EOF'
import re
path = "{{TASK_FILE}}"
content = open(path).read()
m = re.search(r'(?m)^branch:\s*(\S+)', content)
print(m.group(1) if m else "")
EOF
```

Record the branch name (e.g. `ralph/task-{{TASK_ID}}`).

## Step 2 — Merge into feature branch

Ensure you are on the feature branch, then merge the task branch with `--no-ff`:

```bash
git checkout {{FEATURE_BRANCH}}
git merge --no-ff <branch-from-step-1>
```

## Step 3 — Delete the task branch

Remove the task branch locally. Do **not** push anything — the remote must have no `ralph/task-*` branches:

```bash
git branch -d <branch-from-step-1>
```

## Step 4 — Set `status: done` and commit

Update `{{TASK_FILE}}`'s YAML front matter on the feature branch:

```bash
python3 - <<'EOF'
import re
path = "{{TASK_FILE}}"
content = open(path).read()
content = re.sub(r'(?m)^(status:\s*)\S+', r'\g<1>done', content, count=1)
open(path, "w").write(content)
EOF
git add "{{TASK_FILE}}"
git commit -m "chore: mark task {{TASK_ID}} done"
```

## Step 5 — Stop

Emit this token as your **final output** and end your response immediately:

<promise>STOP</promise>
