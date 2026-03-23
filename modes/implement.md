# Ralph — Implement Mode

You are implementing the task described in `{{TASK_FILE}}`.

⚠️ **Never** use `gh pr comment --body "..."` — it hangs waiting for stdin. Always write the body to a temp file and use `--body-file <file> < /dev/null`.

## Step 1 — Get up to speed

- Read `{{TASK_FILE}}` to understand the task. The YAML front matter contains metadata; the body is the task specification.
- The PRD overview for broader context is: `{{PRD_OVERVIEW}}`
- Run `git log --oneline -10` to see recent commits.

## Step 2 — Mark task as `in_progress`

Before starting any implementation work, update `status` to `in_progress` in `{{TASK_FILE}}`'s YAML front matter:

```bash
python3 - <<'EOF'
import re
path = "{{TASK_FILE}}"
content = open(path).read()
content = re.sub(r'(?m)^(status:\s*)\S+', r'\g<1>in_progress', content, count=1)
open(path, "w").write(content)
EOF
git add "{{TASK_FILE}}"
git commit -m "chore: mark task {{TASK_ID}} in_progress"
```

## Step 3 — Create task branch

Check out a new **local** branch. Do **not** push it to the remote:

```bash
git checkout -b ralph/task-{{TASK_ID}}
```

## Step 4 — Implement

Implement everything required to satisfy the acceptance criteria in the task body. Delegate expensive work to sub-agents where possible (running the test suite, reading large files, summarising command output) to keep your primary context window lean.

## Step 5 — Verify

Run `{{BUILD_CMD}}` (skip if empty) and `{{TEST_CMD}}` using a sub-agent. **Both must pass before you continue.**

If either check fails and you cannot fix it after a genuine effort, **do not continue**. Instead:

- Revert any broken changes (`git checkout -- .` or `git stash`)
- Emit the following token as your final output and stop:

  <promise>STOP</promise>

## Step 6 — Update CHANGELOG and commit

**Update `CHANGELOG.md`** in the repo root before committing:

- If `CHANGELOG.md` does not exist, create it with this header:
  ```
  # Changelog

  All notable changes to this project will be documented in this file.

  The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

  ## [Unreleased]
  ```
- Add an entry under `## [Unreleased]` using the appropriate subsection (`### Added`, `### Changed`, `### Fixed`, `### Removed`). One concise bullet per logical change. Include the task ID in parentheses, e.g.:
  ```
  ### Added
  - New authentication flow (task-05)
  ```
- If `## [Unreleased]` already exists, append to the correct subsection (or create it if needed). Do not create a new `## [Unreleased]` block.
- Do not add version headers or dates.

**Commit** all implementation changes (code + CHANGELOG) together using conventional commits (`feat:`, `fix:`, `chore:`, `refactor:`).

## Step 7 — Return to feature branch and update task status

Switch back to the feature branch and update `{{TASK_FILE}}`'s front matter:
- Set `status` to `needs_review`
- Set `branch` to `ralph/task-{{TASK_ID}}`

```bash
git checkout {{FEATURE_BRANCH}}
python3 - <<'EOF'
import re
path = "{{TASK_FILE}}"
content = open(path).read()
content = re.sub(r'(?m)^(status:\s*)\S+', r'\g<1>needs_review', content, count=1)
if re.search(r'(?m)^branch:', content):
    content = re.sub(r'(?m)^(branch:\s*).*$', r'\g<1>ralph/task-{{TASK_ID}}', content, count=1)
else:
    content = re.sub(r'(?m)^(status:.*)', r'\g<1>\nbranch: ralph/task-{{TASK_ID}}', content, count=1)
open(path, "w").write(content)
EOF
git add "{{TASK_FILE}}"
git commit -m "chore: mark task {{TASK_ID}} needs_review, branch ralph/task-{{TASK_ID}}"
```

## Step 8 — Stop

Your work this iteration is done.

Emit this token as your **final output** and stop:

<promise>STOP</promise>

Any output after this token violates the rules.
