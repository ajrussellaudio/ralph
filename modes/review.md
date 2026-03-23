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
> Run the test suite: `{{TEST_CMD}}`
> You are a strict code reviewer with no attachment to this code.
> Surface only: genuine bugs, logic errors, missing test coverage for new behaviour, or security issues.
> Do NOT comment on: style, formatting, naming conventions, or speculative concerns.
> For each issue found, return: file path, approximate line number, a clear description of the problem, and a concrete suggested fix.
> If you find no genuine issues, return exactly the word: LGTM"

**If LGTM:** proceed to steps 3–5 to set `status: approved`.

**If issues found:** proceed to step 6 to save review notes and set `status: needs_fix`.

---

## Steps 3–5: Approve (LGTM path)

### Step 3 — Set `status: approved` and commit

```bash
python3 - <<'EOF'
import re
path = "{{TASK_FILE}}"
with open(path) as f:
    content = f.read()
content = re.sub(r'(?m)^(status:\s*)\S+', r'\g<1>approved', content, count=1)
with open(path, 'w') as f:
    f.write(content)
EOF
git add "{{TASK_FILE}}"
git commit -m "chore: task {{TASK_ID}} approved — ready to merge"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.

---

## Step 6: Save review notes and set `status: needs_fix` (issues found path)

Update `{{TASK_FILE}}`'s YAML front matter: set `status: needs_fix` and **append** a new `|` block scalar entry to the `review_notes` list. Use the following Python script, replacing the placeholder with the actual issues:

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

# Parse existing | block scalar entries from review_notes
existing = []
rn_match = re.search(r'(?m)^review_notes:(?:[^\n]*\n?)((?:[ \t]+[^\n]*\n?)*)', fm)
if rn_match:
    for em in re.finditer(r'[ \t]+-[ \t]+\|\n((?:(?:[ \t]{4}[^\n]*)?\n)*)', rn_match.group(0)):
        lines = [l[4:] if l.startswith('    ') else '' for l in em.group(1).splitlines()]
        existing.append('\n'.join(lines).rstrip())

# Remove existing review_notes block
fm = re.sub(r'(?m)^review_notes:(?:[^\n]*\n?)(?:[ \t]+[^\n]*\n?)*', '', fm)

# New review note — replace this placeholder with the actual issues found
new_note = """<paste the numbered list of issues here>"""
existing.append(new_note.strip())

# Build YAML list of | block scalars
entries_yaml = ''
for note in existing:
    entries_yaml += '  - |\n'
    for line in note.splitlines():
        entries_yaml += '    ' + line + '\n'

block = 'review_notes:\n' + entries_yaml
fm = fm.rstrip('\n') + '\n' + block + '\n'

with open(path, 'w') as f:
    f.write(f"---\n{fm}---\n{rest}")
PYEOF
git add "{{TASK_FILE}}"
git commit -m "chore: task {{TASK_ID}} needs_fix — review notes written"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.
