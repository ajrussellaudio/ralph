# Ralph

Ralph is a generic, self-contained AI agent loop that autonomously works through a GitHub project's open issues — implementing features, opening PRs, reviewing code, and merging — one iteration at a time.

## How it works

Each iteration Ralph:
1. Syncs to `origin/main`
2. Checks for open PRs to review, fix, or merge
3. If none, picks the most important open issue and implements it
4. Opens a PR and stops — the next iteration reviews it
5. Emits `<promise>COMPLETE</promise>` when all issues are closed and all PRs are merged

## Setup

1. **Add Ralph to your repo:**
   ```bash
   git clone https://github.com/ajrussellaudio/ralph.git ralph
   echo 'ralph/project.toml' >> .gitignore   # keep project config local, or commit it
   ```

2. **Configure for your project** — copy and fill in the template:
   ```bash
   cp ralph/project.example.toml ralph/project.toml
   # Edit ralph/project.toml with your repo name, build/test commands, and permanent issue number
   ```

3. **Run:**
   ```bash
   ./ralph/ralph.sh 20
   ```
   Replace `20` with however many iterations you want to allow.

## Requirements

- [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli) (`copilot` in PATH)
- `gh` (GitHub CLI), authenticated
- `git`

## Files

| File | Purpose |
|------|---------|
| `ralph.sh` | The loop script — generic, no project-specific code |
| `modes/` | Per-mode agent prompts (`implement.md`, `review.md`, `fix.md`, `merge.md`, etc.) |
| `project.example.toml` | Annotated template — copy to `project.toml` and fill in |
| `project.toml` | Your project config — created from the template, not committed here |

## Stopping Ralph

Ralph stops automatically when:
- All open issues are closed and all ralph PRs are merged (emits `COMPLETE`)
- The maximum iteration count is reached

You can also press `Ctrl-C` at any time — the worktree is cleaned up automatically.
