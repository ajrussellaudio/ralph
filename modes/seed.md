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

Run the seeding script using the `bash` tool:

```bash
python3 "{{RALPH_DIR}}/lib/seed.py" "{{TASKS_FILE}}" "{{DB_PATH}}" "{{LABEL_SLUG}}"
```

After running, verify by querying the DB:

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
