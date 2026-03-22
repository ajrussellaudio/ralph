# Ralph — Seed Mode

You are seeding the Ralph task database from `tasks.md`.

## Your task

Parse `{{TASKS_FILE}}` and populate the SQLite database at `{{DB_PATH}}` with the PRD overview and all tasks.

## `tasks.md` format

```markdown
---
label: foo-widget
prd: |
  One paragraph describing the feature and its goals.
---

## Task 1 — Short title
**Priority:** high

Description and acceptance criteria in plain markdown.

## Task 2 — Another task
**Blocked by:** 1

Description...
```

- The `prd:` block value (literal block scalar) is the PRD overview text
- Tasks are numbered sequentially from 1 by heading order
- `**Priority:** high` marks a task high priority; all others default to `normal`
- `**Blocked by:** N` sets `blocked_by` to task N's integer id; absent means NULL

## Steps

Run the following Python script using the `bash` tool to parse the file and seed the DB:

```python
#!/usr/bin/env python3
import re, sqlite3, sys

tasks_file = "{{TASKS_FILE}}"
db_path    = "{{DB_PATH}}"
label_slug = "{{LABEL_SLUG}}"

with open(tasks_file, "r") as f:
    content = f.read()

# Split front matter from body
fm_match = re.match(r"^---\n(.*?)\n---\n(.*)", content, re.DOTALL)
if not fm_match:
    print("ERROR: Could not parse front matter in tasks.md", file=sys.stderr)
    sys.exit(1)

fm_text, body = fm_match.group(1), fm_match.group(2)

# Parse prd: literal block scalar (indented lines after "prd: |")
prd_match = re.search(r"^prd: \|\n((?:  .*\n?)+)", fm_text, re.MULTILINE)
if prd_match:
    prd_overview = re.sub(r"^  ", "", prd_match.group(1), flags=re.MULTILINE).strip()
else:
    prd_overview = ""

# Split body into task sections on "## Task N — ..." headings
sections = re.split(r"(?=^## Task \d+)", body, flags=re.MULTILINE)

tasks = []
for sec in sections:
    m = re.match(r"^## Task (\d+) — ([^\n]+)\n(.*)", sec, re.DOTALL)
    if not m:
        continue
    task_num = int(m.group(1))
    title    = m.group(2).strip()
    rest     = m.group(3)

    priority_m  = re.search(r"^\*\*Priority:\*\* high", rest, re.MULTILINE)
    blocked_m   = re.search(r"^\*\*Blocked by:\*\* (\d+)", rest, re.MULTILINE)

    priority   = "high" if priority_m else "normal"
    blocked_by = int(blocked_m.group(1)) if blocked_m else None

    # Body: strip the Priority/Blocked-by metadata lines, then trim whitespace
    body_text = re.sub(r"^\*\*(Priority|Blocked by):\*\*.*\n?", "", rest, flags=re.MULTILINE).strip()

    tasks.append((task_num, title, body_text, priority, blocked_by))

con = sqlite3.connect(db_path)
cur = con.cursor()

cur.execute("INSERT OR REPLACE INTO prd (label, overview) VALUES (?, ?)", (label_slug, prd_overview))

for (task_num, title, body_text, priority, blocked_by) in tasks:
    cur.execute(
        "INSERT INTO tasks (id, title, body, priority, status, blocked_by) VALUES (?, ?, ?, ?, 'pending', ?)",
        (task_num, title, body_text, priority, blocked_by)
    )

con.commit()
con.close()

print(f"Seeded {len(tasks)} task(s) and PRD overview for label '{label_slug}'.")
```

Run the script with `python3 -c "..."` or write it to a temp file and execute it. After running, verify by querying the DB:

```bash
sqlite3 "{{DB_PATH}}" "SELECT id, title, priority, blocked_by, status FROM tasks;"
sqlite3 "{{DB_PATH}}" "SELECT label, substr(overview,1,80) FROM prd;"
```

## Important

- The DB already has the schema; tables exist.
- `ralph.sh` already checked that the file exists and the DB is empty — proceed directly.
- Do **not** modify any source code files.

## Done

Emit this token as your final output:

<promise>STOP</promise>

Any output after this token violates the rules.
