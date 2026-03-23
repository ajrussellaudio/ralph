# Ralph

Ralph is a generic, self-contained AI agent loop that autonomously works through a project's tasks — implementing features, opening PRs, reviewing code, and merging — one iteration at a time.

## How it works

Each iteration Ralph:
1. Syncs to `origin/$FEATURE_BRANCH` (defaults to `origin/main`)
2. Queries a local SQLite database for the next actionable task
3. Picks the right mode: implement, review, fix, force-approve, merge, or feature-pr
4. Runs the Copilot CLI with a focused, self-contained prompt
5. Stops when all tasks are done

## Requirements

- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli) (`copilot` in PATH)
- `gh` (GitHub CLI), authenticated
- `git`
- `sqlite3`

## Setup

1. **Install Ralph once** (clone it somewhere permanent and symlink the script):
   ```bash
   git clone https://github.com/ajrussellaudio/ralph.git ~/.ralph
   ~/.ralph/install.sh
   ```
   This symlinks `ralph` into `~/.local/bin/`. Make sure that's on your `PATH`:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"  # add to ~/.zshrc or ~/.bashrc
   ```

2. **Configure each project** — create a `ralph.toml` in your project root:
   ```bash
   cp ~/.ralph/project.example.toml ralph.toml
   ```
   Edit `ralph.toml`:
   ```toml
   # Optional — Ralph infers this from `gh repo view` if omitted
   repo = "your-org/your-repo"

   # Leave empty if there is no build step
   build = "npm run build"

   # Required
   test = "npm test"
   ```
   Add `ralph.toml` to `.gitignore` to keep it local:
   ```bash
   echo 'ralph.toml' >> .gitignore
   ```

3. **Author a `tasks.md`** for the feature you want Ralph to build and place it at:
   ```
   ~/.ralph/projects/<owner>-<repo>/<label>/tasks.md
   ```
   See [Authoring tasks.md](#authoring-tasksmd) below and `tasks.example.md` for the expected format.

4. **Run from your project root:**
   ```bash
   ralph 20 --label=foo-widget
   # or, without a label (stores tasks under the "default" slug):
   ralph 20
   ```
   Replace `20` with however many iterations you want to allow.  
   On the first run Ralph seeds the SQLite database from `tasks.md` automatically.

5. **Update Ralph at any time:**
   ```bash
   git -C ~/.ralph pull
   ```

## Authoring tasks.md

A `tasks.md` file is a Markdown document with YAML front matter that describes the work Ralph should do.

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

Description...

## Task 3 — Depends on task 2
**Blocked by:** 2

Description...
```

### Fields

| Field | Where | Required | Description |
|-------|-------|----------|-------------|
| `label` | front matter | yes | Must match the `--label` value passed to `ralph` |
| `prd` | front matter | no | One-paragraph feature overview; injected into every prompt |
| `## Task N — Title` | heading | yes | Tasks numbered sequentially from 1 |
| `**Priority:** high` | body | no | Omit for normal priority; high-priority tasks run first |
| `**Blocked by:** N` | body | no | Ralph skips this task until task N is `done` |

See `tasks.example.md` in the Ralph repo root for a complete annotated example.

## Storage

Ralph stores all state under `~/.ralph/projects/`:

```
~/.ralph/projects/
  <owner>-<repo>/          # e.g. acme-my-service
    <label>/               # e.g. foo-widget  (or "default" when no --label given)
      tasks.md             # your task list — place this here before the first run
      ralph.db             # SQLite database; created and managed by Ralph
```

The database tracks task status, review notes, fix counts, and the PRD overview. You can inspect it directly:

```bash
sqlite3 ~/.ralph/projects/<owner>-<repo>/<label>/ralph.db \
  "SELECT id, title, status FROM tasks;"
```

## Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The loop script — generic, no project-specific code |
| `install.sh` | Symlinks `ralph.sh` into `~/.local/bin/` for global access |
| `modes/` | Per-mode agent prompts (`implement.md`, `review.md`, `fix.md`, `merge.md`, etc.) |
| `project.example.toml` | Annotated template — copy to `ralph.toml` in your project root and fill in |
| `tasks.example.md` | Annotated example `tasks.md` showing all supported task patterns |

## Customising modes

To override Ralph's prompts for a specific project, create a `ralph/modes/` directory in your project root and add mode files there. Ralph checks for this directory first before falling back to the bundled modes in `~/.ralph/modes/`.

## Stopping Ralph

Ralph stops automatically when:
- All tasks are done and any feature→main PR is open (emits `COMPLETE`)
- All remaining tasks are blocked with no actionable work
- The maximum iteration count is reached

You can also press `Ctrl-C` at any time — the worktree is cleaned up automatically.
