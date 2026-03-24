# Ralph — Fix Mode

Task `{{TASK_ID}}` in `{{TASK_FILE}}` has review notes that need addressing.

## Step 1 — Read the review notes and branch

Read `review_notes` (last entry only) and `branch` from `{{TASK_FILE}}`'s YAML front matter:

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

# Read last entry from review_notes list (the actionable instruction)
notes = []
rn_match = re.search(r'(?m)^review_notes:(?:[^\n]*\n?)((?:[ \t]+[^\n]*\n?)*)', fm)
if rn_match:
    for em in re.finditer(r'[ \t]+-[ \t]+\|\n((?:(?:[ \t]{4}[^\n]*)?\n)*)', rn_match.group(0)):
        lines = [l[4:] if l.startswith('    ') else '' for l in em.group(1).splitlines()]
        notes.append('\n'.join(lines).rstrip())

last_note = notes[-1] if notes else ""
print("review_notes:", last_note)
EOF
```

Read **every** issue listed — you must address all of them in one pass.

## Step 2 — Check out the task branch

```bash
git checkout <branch-from-step-1>
```

## Step 3 — Fix

Implement fixes for every raised issue. Delegate large file reads to sub-agents.

Run `{{TEST_CMD}}` using a sub-agent. Fix any test failures before continuing.

## Step 4 — Commit the fixes

```bash
git add -A
git commit -m "fix: address review notes for task {{TASK_ID}}"
```

## Step 5 — Update front matter: increment `fix_count`, set `status: needs_review_2`

Switch back to the feature branch and update `{{TASK_FILE}}`'s front matter:

```bash
git checkout {{FEATURE_BRANCH}}
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

# Update status to needs_review_2
fm = re.sub(r'(?m)^(status:\s*)\S+', r'\g<1>needs_review_2', fm)

# Increment fix_count (or insert it at 1 if missing)
fc_m = re.search(r'(?m)^fix_count:\s*(\d+)', fm)
if fc_m:
    new_count = int(fc_m.group(1)) + 1
    fm = re.sub(r'(?m)^(fix_count:\s*)\d+', f'fix_count: {new_count}', fm)
else:
    fm = fm.rstrip('\n') + '\nfix_count: 1\n'

with open(path, 'w') as f:
    f.write(f"---\n{fm}---\n{rest}")
PYEOF
git add "{{TASK_FILE}}"
git commit -m "chore: task {{TASK_ID}} needs_review_2 after fix (fix_count incremented)"
```

## Step 6 — Stop

Emit the following token as your **final output** and end your response immediately:

<promise>STOP</promise>
