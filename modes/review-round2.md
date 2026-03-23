# Ralph — Review Mode (Round 2)

You are verifying that round-1 review issues have been fixed for task `{{TASK_ID}}` in `{{TASK_FILE}}`.

## Step 1 — Read branch and prior review notes

Read the `branch` and `review_notes` fields from `{{TASK_FILE}}`'s YAML front matter:

```bash
python3 - <<'EOF'
import re, sys

path = "{{TASK_FILE}}"
with open(path) as f:
    content = f.read()

fm_m = re.match(r'^---\n(.*?)\n---\n', content, re.DOTALL)
if not fm_m:
    sys.exit("No front matter")
fm = fm_m.group(1)

# Read branch
bm = re.search(r'(?m)^branch:\s*(\S+)', fm)
print("branch:", bm.group(1) if bm else "")

# Read review_notes (block scalar or inline)
nm = re.search(r'(?m)^review_notes:\s*\|\n((?:  [^\n]*\n?)*)', fm)
if nm:
    notes = "\n".join(l[2:] if l.startswith("  ") else l for l in nm.group(1).splitlines())
else:
    nm = re.search(r'(?m)^review_notes:\s*(.+)$', fm)
    notes = nm.group(1).strip() if nm else ""
print("review_notes:", notes)
EOF
```

Record the branch name and the prior review notes.

## Step 2 — Verify the fixes

Delegate verification to a sub-agent. Do **not** re-review the whole diff.

Launch a **general-purpose sub-agent** with this prompt, substituting the real branch name and prior notes:

> "You are verifying fixes on task {{TASK_ID}} in the `{{REPO}}` repository.
> Get the diff with: `git diff {{FEATURE_BRANCH}}...<branch>`
> The previous review raised these specific issues:
> <paste prior review_notes here>
> Check only whether each of those issues has been resolved in the latest diff.
> Do NOT raise new issues — only assess the original ones.
> For each original issue, state: RESOLVED or UNRESOLVED (with a brief reason).
> If all are RESOLVED, return exactly the word: LGTM"

**If LGTM (all resolved):** proceed to steps 3–5 to merge and mark done.

**If any issues are UNRESOLVED:** proceed to step 6 to update review notes and set `status: needs_fix`.

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
git commit -m "chore: mark task {{TASK_ID}} done after round-2 review approval"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.

---

## Step 6: Update review notes and set `status: needs_fix` (issues unresolved path)

Update `{{TASK_FILE}}`'s YAML front matter with the still-unresolved issues and set `status: needs_fix`:

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

# Append updated review_notes as a YAML block scalar
review_notes = """<paste the unresolved issues here>"""
block = "review_notes: |\n" + "\n".join("  " + line for line in review_notes.strip().splitlines())
fm = fm.rstrip('\n') + '\n' + block + '\n'

with open(path, 'w') as f:
    f.write(f"---\n{fm}---\n{rest}")
PYEOF
git add "{{TASK_FILE}}"
git commit -m "chore: task {{TASK_ID}} needs_fix — unresolved issues after round-2 review"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.
