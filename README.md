# Ralph

Ralph is a generic, self-contained AI agent loop that autonomously works through a GitHub project's open issues — implementing features, opening PRs, reviewing code, and merging — one iteration at a time.

## How it works

Each iteration Ralph:
1. Syncs to `origin/$FEATURE_BRANCH` (defaults to `origin/main`)
2. Checks for open PRs to review, fix, or merge
3. If none, picks the most important open issue and implements it
4. Opens a PR and stops — the next iteration reviews it
5. Emits `<promise>COMPLETE</promise>` when all issues are closed and all PRs are merged

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

   # Optional — for fork-based workflows (see below)
   upstream = ""

   # Leave empty if there is no build step
   build = "npm run build"

   # Required
   test = "npm test"
   ```
   Add `ralph.toml` to `.gitignore` to keep it local:
   ```bash
   echo 'ralph.toml' >> .gitignore
   ```

3. **Run from your project root:**
   ```bash
   ralph 20
   # or, to work within a feature branch:
   ralph 20 --label=foo-widget
   ```
   Replace `20` with however many iterations you want to allow.

4. **Update Ralph at any time:**
   ```bash
   git -C ~/.ralph pull
   ```

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

To override Ralph's prompts for a specific project, create a `ralph/modes/` directory in your project root and add mode files there. Ralph checks for this directory first before falling back to the bundled modes in `~/.ralph/modes/`.

## Label conventions

| Label | Purpose |
|---|---|
| `prd` | Marks an issue as a PRD — Ralph never implements it |
| `prd/<slug>` | Scopes an issue to a feature; Ralph targets `feat/<slug>` |
| `high-priority` | Ralph picks these issues first |
| `blocked` | Ralph skips these issues |

Use `/write-a-prd` and `/prd-to-issues` Copilot skills to create PRDs and task issues with the correct labels applied automatically.

## Fork-based workflows

If Ralph is doing all the work on your fork (`you/project`) but the final feature PR should land on the upstream repo (`org/project`), set `upstream` in `ralph.toml`:

```toml
repo     = "you/project"   # your fork — Ralph owns this
upstream = "org/project"   # upstream — final PR lands here
```

When `upstream` is set:
- All issues and intermediate PRs continue to use `repo` (your fork).
- The final `feature-pr` mode opens the PR against `upstream` with the correct cross-fork head (`you:feat/<label>`).
- Issue-close links in the PR body use the cross-repo syntax (`Closes you/project#<n>`) so they auto-close on merge.

When `upstream` is **not** set, behaviour is identical to today.



Ralph stops automatically when:
- All open issues are closed and all ralph PRs are merged (emits `COMPLETE`)
- The maximum iteration count is reached

You can also press `Ctrl-C` at any time — the worktree is cleaned up automatically.
