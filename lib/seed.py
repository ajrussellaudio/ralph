#!/usr/bin/env python3
"""
lib/seed.py — Parse a tasks.md file and populate the Ralph SQLite database.

Usage: python3 seed.py <tasks_file> <db_path> <label_slug>
"""

import re
import sqlite3
import sys

if len(sys.argv) != 4:
    print(f"Usage: {sys.argv[0]} <tasks_file> <db_path> <label_slug>", file=sys.stderr)
    sys.exit(1)

tasks_file = sys.argv[1]
db_path    = sys.argv[2]
label_slug = sys.argv[3]

try:
    with open(tasks_file, "r") as f:
        content = f.read()
except FileNotFoundError:
    print(f"ERROR: tasks.md not found at '{tasks_file}'", file=sys.stderr)
    sys.exit(1)

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
        "INSERT OR IGNORE INTO tasks (id, title, body, priority, status, blocked_by) VALUES (?, ?, ?, ?, 'pending', ?)",
        (task_num, title, body_text, priority, blocked_by)
    )
    cur.execute(
        """UPDATE tasks
           SET title = ?, body = ?, priority = ?, blocked_by = ?
           WHERE id = ? AND status = 'pending'""",
        (title, body_text, priority, blocked_by, task_num)
    )

con.commit()
con.close()

print(f"Seeded {len(tasks)} task(s) and PRD overview for label '{label_slug}'.")
