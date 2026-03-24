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

## Step 2 — Squash merge into feature branch

Ensure you are on the feature branch, then squash-merge the task branch:

```bash
git checkout {{FEATURE_BRANCH}}
git merge --squash <branch-from-step-1>
```

If the merge exits non-zero (conflicts), run:

```bash
git reset --hard HEAD
```

Then emit `<promise>STOP</promise>` as your final output and stop immediately.

Once the squash succeeds, commit the staged changes to produce a single commit on the feature branch:

```bash
git commit -m "feat: complete task {{TASK_ID}}"
```

## Step 3 — Delete the task branch

Remove the task branch locally. Do **not** push anything — the remote must have no `ralph/task-*` branches:

```bash
git branch -D <branch-from-step-1>
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

## Step 5 — Log newly unblocked tasks

Scan all other task files in `{{PLANS_DIR}}` for any that list `{{TASK_ID}}` in their `blocked_by` field. Print the names of any tasks that are now unblocked. No changes are needed — routing will pick them up automatically on the next iteration.

```bash
python3 - <<'EOF'
import re, glob, os

task_id = int("{{TASK_ID}}")
plans_dir = "{{PLANS_DIR}}"
task_file = "{{TASK_FILE}}"

unblocked = []
for path in sorted(glob.glob(os.path.join(plans_dir, '*.md'))):
    if os.path.abspath(path) == os.path.abspath(task_file):
        continue
    content = open(path).read()
    m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not m:
        continue
    blocked_by_line = re.search(r'^blocked_by\s*:\s*(.+)$', m.group(1), re.MULTILINE)
    if not blocked_by_line:
        continue
    ids = [int(x) for x in re.findall(r'\d+', blocked_by_line.group(1))]
    if task_id in ids:
        status_match = re.search(r'^status\s*:\s*(\S+)', m.group(1), re.MULTILINE)
        status = status_match.group(1).strip('"\'') if status_match else 'unknown'
        if status == 'pending':
            unblocked.append(os.path.basename(path))

if unblocked:
    print(f"Tasks now unblocked by completing task {{TASK_ID}}: {', '.join(unblocked)}")
else:
    print("No pending tasks were waiting on task {{TASK_ID}}.")
EOF
```

## Step 6 — Stop

Emit this token as your **final output** and end your response immediately:

<promise>STOP</promise>
