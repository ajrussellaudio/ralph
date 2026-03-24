# Ralph — Force-Approve Mode

Task `{{TASK_ID}}` in `{{TASK_FILE}}` has reached the fix-count cap (`fix_count >= 2`). Approve it unconditionally and merge.

## Step 1 — Read the task branch name

Read the `branch` field from `{{TASK_FILE}}`'s YAML front matter:

```bash
python3 - <<'EOF'
import re
path = "{{TASK_FILE}}"
with open(path) as f:
    content = f.read()
m = re.search(r'(?m)^branch:\s*(\S+)', content)
print(m.group(1) if m else "")
EOF
```

Record the branch name (e.g. `ralph/task-{{TASK_ID}}`).

## Step 2 — Merge into feature branch

```bash
git checkout {{FEATURE_BRANCH}}
git merge --no-ff <branch>
```

If the merge exits non-zero (conflicts), run `git merge --abort`, then emit `<promise>STOP</promise>` as your final output and stop immediately.

## Step 3 — Delete the task branch

```bash
git branch -d <branch>
```

## Step 4 — Set `status: done` and commit

```bash
python3 - <<'EOF'
import re
path = "{{TASK_FILE}}"
with open(path) as f:
    content = f.read()
content = re.sub(r'(?m)^(status:\s*)\S+', r'\g<1>done', content, count=1)
with open(path, 'w') as f:
    f.write(content)
EOF
git add "{{TASK_FILE}}"
git commit -m "chore: mark task {{TASK_ID}} done via force-approve (fix_count cap reached)"
```

## Step 5 — Stop

Emit this token as your **final output** and end your response immediately:

<promise>STOP</promise>
