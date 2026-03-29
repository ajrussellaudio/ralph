# Ralph

Ralph is a generic, self-contained AI agent loop that autonomously works through a GitHub project's open issues — implementing features, opening PRs, reviewing code, and merging — one iteration at a time.

## How it works

Each iteration Ralph:
1. Syncs to `origin/$FEATURE_BRANCH` (defaults to `origin/main`)
2. Checks for open PRs to review, fix, or merge
3. If none, picks the most important open issue and implements it
4. Pushes a draft PR (or updates an existing one) and stops — the next iteration reviews it
5. Loops the review → fix cycle until the code is approved or the escalation threshold is reached
6. Merges, then moves on to the next issue
7. Emits `<promise>COMPLETE</promise>` when all issues are closed and all PRs are merged

### Review backend

Ralph auto-detects how to post reviews:
- **GitHub Copilot bot** — if the Copilot code-review bot is installed on the repo, Ralph delegates review to it and waits for its verdict
- **HTML comments** — otherwise Ralph posts its own review as an HTML comment on the PR (`<!-- RALPH-REVIEW: APPROVED -->` / `<!-- RALPH-REVIEW: REQUEST_CHANGES -->`)

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
   ralph
   # work within a feature branch (scoped to issues labelled prd/foo-widget):
   ralph --label=foo-widget
   # target a single specific issue by number:
   ralph --issue=42
   # combine: implement issue #42 on the foo-widget feature branch:
   ralph --issue=42 --label=foo-widget
   # cap the number of iterations (runs unlimited by default):
   ralph --max-iterations=20 --label=foo-widget
   ```
   Ralph runs indefinitely by default, stopping only when all tasks are complete.
   Use `--max-iterations=N` as an escape hatch if you want a hard cap.

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
| `docs/routing.md` | Mermaid flowcharts showing Ralph's routing logic and task lifecycle |

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



## Stopping conditions

Ralph stops automatically when:
- All open issues are closed and all ralph PRs are merged (emits `COMPLETE`)
- The maximum iteration count is reached (if `--max-iterations=N` was given)
- A single `--issue=N` completes (Ralph exits after that issue is done)

You can also press `Ctrl-C` at any time — the worktree is cleaned up automatically.
