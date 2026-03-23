# Ralph

Ralph is a generic, self-contained AI agent loop that autonomously works through a GitHub project's open issues — implementing features, opening PRs, reviewing code, and merging — one iteration at a time.

## How it works

Each iteration Ralph:
1. Syncs to `origin/feat/<label>`
2. Scans `plans/<label>/` for the next task to work on
3. Implements, reviews, fixes, and merges tasks one at a time via local branches
4. When all tasks are `done`, opens a `feat/<label> → main` PR
5. Emits `<promise>COMPLETE</promise>` when the feature PR is open

## Setup

1. **Install Ralph once** (clone it somewhere permanent and symlink the script):
   ```bash
   git clone https://github.com/ajrussellaudio/ralph.git /path/to/ralph
   /path/to/ralph/install.sh
   ```
   This symlinks `ralph` into `~/.local/bin/`. Make sure that's on your `PATH`:
   ```bash
   export PATH="$HOME/.local/bin:$PATH"  # add to ~/.zshrc or ~/.bashrc
   ```

2. **Configure each project** — create a `ralph.toml` in your project root:
   ```bash
   cp /path/to/ralph/project.example.toml ralph.toml
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

3. **Create a `plans/` directory** in your project root (committed to the repo):
   ```bash
   mkdir -p plans/my-feature
   ```
   See [Markdown backend](#markdown-backend) below for the file format.

4. **Run from your project root:**
   ```bash
   ralph 20 --label=my-feature
   ```
   Replace `20` with however many iterations you want to allow and `my-feature` with your feature slug.

5. **Update Ralph at any time:**
   ```bash
   git -C /path/to/ralph pull
   ```

## Markdown backend

Ralph uses a `plans/` directory in your project repo as its task store. Commit this directory — it is the single source of truth for task state.

### Directory layout

```
plans/
├── my-feature.md          # PRD overview (optional but recommended)
└── my-feature/            # Task files for this feature
    ├── 01-first-task.md
    ├── 02-second-task.md
    └── ...
```

The `--label=my-feature` flag tells Ralph to:
- Read tasks from `plans/my-feature/`
- Target the `feat/my-feature` git branch for all work

### Task file format

Each task file is a Markdown file with a YAML front matter block followed by a human-readable description:

```markdown
---
status: pending
priority: normal
blocked_by: []
branch:
fix_count: 0
---

# Task title

## Description

What to build and why.

## Acceptance criteria

- [ ] ...
```

### YAML front matter fields

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `status` | Yes | `pending` | Task state (see [Status values](#status-values)) |
| `priority` | No | `normal` | `normal` or `high` — high tasks are picked before normal ones |
| `blocked_by` | No | `[]` | List of task ID prefixes that must be `done` before this task starts, e.g. `["01", "03"]` |
| `branch` | Auto | (empty) | Set by Ralph after implement — do not edit by hand |
| `fix_count` | Auto | `0` | Set by Ralph — incremented each time the fix mode runs |
| `review_notes` | Auto | (absent) | Set by Ralph after review — read by fix mode as context |

### Status values

| Status | Meaning |
|--------|---------|
| `pending` | Not yet started |
| `in_progress` | Ralph is implementing (also used to resume interrupted work) |
| `needs_review` | Implementation committed, awaiting review |
| `needs_fix` | Reviewer found issues; Ralph will fix |
| `needs_review_2` | Fixes committed, awaiting second review |
| `done` | Complete and merged into the feature branch |

### `--label` flag

The `--label` flag is the primary way to scope Ralph to a feature:

```bash
ralph 20 --label=my-feature
```

This sets:
- **Plans directory**: `plans/my-feature/` — where Ralph reads and writes task files
- **Feature branch**: `feat/my-feature` — the git branch all task work targets
- **Feature label**: `prd/my-feature` — used for GitHub label filtering if needed

### Full lifecycle

1. Create `plans/my-feature/` with numbered task files (`01-*.md`, `02-*.md`, …)
2. Set `status: pending` on all tasks; set `priority: high` on the most important ones
3. Use `blocked_by` to express dependencies between tasks
4. Commit `plans/` to the repo
5. Run `ralph 20 --label=my-feature`
6. Ralph picks the first unblocked pending task, implements it, reviews it, fixes any issues, and merges it — then loops to the next task
7. When all tasks are `done`, Ralph opens a `feat/my-feature → main` PR

## Requirements

- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli) (`copilot` in PATH)
- `gh` (GitHub CLI), authenticated
- `git`

## Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The loop script — generic, no project-specific code |
| `install.sh` | Symlinks `ralph.sh` into `~/.local/bin/` for global access |
| `modes/` | Per-mode agent prompts (`implement.md`, `review.md`, `fix.md`, `merge.md`, etc.) |
| `project.example.toml` | Annotated template — copy to `ralph.toml` in your project root and fill in |

## Customising modes

To override Ralph's prompts for a specific project, create a `ralph/modes/` directory in your project root and add mode files there. Ralph checks for this directory first before falling back to the bundled modes in the Ralph installation directory.

## Label conventions

| Label | Purpose |
|---|---|
| `prd/<slug>` | Scopes a GitHub issue to a feature (used for PRD issues only) |

Use `/write-a-prd` and `/prd-to-issues` Copilot skills to create PRDs and task issues with the correct labels applied automatically.

## Stopping Ralph

Ralph stops automatically when:
- All open issues are closed and all ralph PRs are merged (emits `COMPLETE`)
- The maximum iteration count is reached

You can also press `Ctrl-C` at any time — the worktree is cleaned up automatically.
