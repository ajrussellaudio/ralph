# Ralph — Review Mode (Round 1)

You are reviewing task `{{TASK_ID}}` described in `{{TASK_FILE}}`.

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

## Step 2 — Review the diff

Delegate the review to a sub-agent. Do not review the code yourself.

Launch a **general-purpose sub-agent** with this prompt, substituting the real branch name and task file path:

> "Review the code changes for task {{TASK_ID}} in the `{{REPO}}` repository.
> Run: `git diff {{FEATURE_BRANCH}}...<branch>` to get the diff.
> Read the task spec at `{{TASK_FILE}}` to understand what was implemented.
> You are a strict code reviewer with no attachment to this code.
> Surface only: genuine bugs, logic errors, missing test coverage for new behaviour, or security issues.
> Do NOT comment on: style, formatting, naming conventions, or speculative concerns.
> For each issue found, return: file path, approximate line number, a clear description of the problem, and a concrete suggested fix.
> If you find no genuine issues, return exactly the word: LGTM"

**If LGTM:** proceed to steps 3–5 to merge and mark done.

**If issues found:** proceed to step 6 to save review notes and set `status: needs_fix`.

---

## Steps 3–5: Merge and mark done (LGTM path)

### Step 3 — Merge into feature branch

```bash
git checkout {{FEATURE_BRANCH}}
git merge --no-ff <branch>
```

If the merge exits non-zero (conflicts), run `git merge --abort`, then emit `<promise>STOP</promise>` as your final output and stop immediately.

### Step 4 — Delete the task branch

```bash
git branch -d <branch>
```

### Step 5 — Set `status: done` and commit

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
git commit -m "chore: mark task {{TASK_ID}} done after review approval"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.

---

## Step 6: Save review notes and set `status: needs_fix` (issues found path)

Write the review notes into `{{TASK_FILE}}`'s YAML front matter and set `status: needs_fix`. Use the following Python script, replacing the `review_notes` string with the actual issues:

```bash
python3 - <<'PYEOF'
import re, sys

path = "{{TASK_FILE}}"
with open(path) as f:
    content = f.read()

fm_m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
if not fm_m:
    sys.exit("No front matter found")

fm = fm_m.group(1)
rest = content[fm_m.end():]

# Update status
fm = re.sub(r'(?m)^(status:\s*)\S+', r'\g<1>needs_fix', fm)

# Remove existing review_notes (inline or block scalar)
fm = re.sub(r'(?m)^review_notes:[^\n]*(?:\n  [^\n]*)*\n?', '', fm)

# Append review_notes as a YAML block scalar
review_notes = """<paste the numbered list of issues here>"""
block = "review_notes: |\n" + "\n".join("  " + line for line in review_notes.strip().splitlines())
fm = fm.rstrip('\n') + '\n' + block + '\n'

with open(path, 'w') as f:
    f.write(f"---\n{fm}---\n{rest}")
PYEOF
git add "{{TASK_FILE}}"
git commit -m "chore: task {{TASK_ID}} needs_fix — review notes written"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.
