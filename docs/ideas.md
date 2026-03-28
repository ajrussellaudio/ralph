# Ideas & Future Improvements

Rough notes on things worth building. None of these are tracked as issues yet.

## Observability

- **`ralph status`** — print current state of all open PRs and worktrees without starting work; a quick "where are we?" for long-running feature branches

## Developer experience

- **`ralph doctor`** — validate the environment before starting: check `gh auth`, `copilot` in `PATH`, `ralph.toml` present and valid, upstream reachable
- **`ralph init`** — interactive scaffold for `ralph.toml` instead of copying `project.example.toml` manually

## Robustness

- **Transient error retry** — wrap `gh` API calls with a simple retry (e.g. 3 attempts, exponential backoff); network blips currently abort a long run
- **Structured exit reasons** — when Ralph exits with code 1, the reason is often unclear; emit a machine-readable exit reason alongside the human message

## Notifications

- **Desktop / shell notifications** — fire a macOS `osascript` alert (or `terminal-notifier` if available) when Ralph finishes or gets stuck, so you can leave it running and walk away

## README / docs

- ~~**Update README**~~ — done 2026-03-28: `--issue=N`, draft PRs, fork workflow, review backend detection, updated stopping conditions
