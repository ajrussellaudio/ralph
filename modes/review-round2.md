# Ralph — Review Mode (Round 2)

You are verifying that round-1 review issues have been fixed for task `{{TASK_ID}}` in `{{TASK_FILE}}`.

## Step 1 — Read branch and prior review notes

Read the `branch` and all `review_notes` entries from `{{TASK_FILE}}`'s YAML front matter:

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

# Read all review_notes entries (full history)
notes = []
rn_match = re.search(r'(?m)^review_notes:(?:[^\n]*\n?)((?:[ \t]+[^\n]*\n?)*)', fm)
if rn_match:
    for em in re.finditer(r'[ \t]+-[ \t]+\|\n((?:(?:[ \t]{4}[^\n]*)?\n)*)', rn_match.group(0)):
        lines = [l[4:] if l.startswith('    ') else '' for l in em.group(1).splitlines()]
        notes.append('\n'.join(lines).rstrip())

if notes:
    print(f"review_notes ({len(notes)} entr{'y' if len(notes)==1 else 'ies'}):")
    for i, note in enumerate(notes, 1):
        print(f"  [Entry {i}]")
        for line in note.splitlines():
            print(f"    {line}")
else:
    print("review_notes: (none)")
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

**If LGTM (all resolved):** proceed to steps 3–5 to set `status: approved`.

**If any issues are UNRESOLVED:** proceed to step 6 to update review notes and set `status: needs_fix`.

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
git commit -m "chore: task {{TASK_ID}} approved after round-2 review — ready to merge"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.

---

## Step 6: Update review notes and set `status: needs_fix` (issues unresolved path)

Update `{{TASK_FILE}}`'s YAML front matter: set `status: needs_fix` and **append** a new `|` block scalar entry to the `review_notes` list with the still-unresolved issues:

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

# New review note — replace this placeholder with the still-unresolved issues
new_note = """<paste the unresolved issues here>"""
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
git commit -m "chore: task {{TASK_ID}} needs_fix — unresolved issues after round-2 review"
```

Then emit `<promise>STOP</promise>` as your **final output** and stop immediately.
