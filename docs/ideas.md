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

## Go migration

Ralph is currently Bash + inline Python. A rewrite in Go would:
- Keep the install simple (single compiled binary, no runtime deps — matches the current symlink approach)
- Replace `toml_get` hacks with a real TOML parser (e.g. `BurntSushi/toml`)
- Make `determine_mode` routing logic unit-testable
- Enable clean subcommands (`ralph status`, `ralph doctor`, `ralph init`) via Cobra
- Eliminate `set -o pipefail` / `|| true` error-handling noise

**Trigger:** wait until `determine_mode` grows significantly more complex (e.g. Markdown backend routing), or until subcommand UX becomes painful in Bash. Not worth the investment while the feature set is still stabilising.

## README / docs

- ~~**Update README**~~ — done 2026-03-28: `--issue=N`, draft PRs, fork workflow, review backend detection, updated stopping conditions
