# Installing Ralph

## Add Ralph as a git submodule

Run this from the **root of your host repo**:

```bash
git submodule add https://github.com/ajrussellaudio/ralph.git ralph
git commit -m "chore: add ralph as submodule"
```

## Configure for your project

```bash
cp ralph/project.example.toml ralph/project.toml
```

Edit `ralph/project.toml`:

```toml
# GitHub repo slug (owner/repo)
repo = "your-org/your-repo"

# Build command — leave empty if no build step
build = "npm run build"

# Test command
test = "npm test"
```

Keep `project.toml` out of version control — add it to your host repo's `.gitignore`:

```bash
echo 'ralph/project.toml' >> .gitignore
git add .gitignore && git commit -m "chore: gitignore ralph/project.toml"
```

## Run

```bash
# Work on standalone issues (no PRD label)
./ralph/ralph.sh 20

# Work on a specific feature PRD
./ralph/ralph.sh 20 --label=my-feature
```

## Update Ralph to the latest version

```bash
git submodule update --remote ralph
git add ralph && git commit -m "chore: update ralph to latest"
```

## Requirements

- `copilot` CLI in PATH (GitHub Copilot CLI)
- `gh` CLI, authenticated (`gh auth login`)
- `git`

## Label conventions

| Label | Purpose |
|---|---|
| `prd` | Marks an issue as a PRD — Ralph never implements it |
| `prd/<slug>` | Scopes an issue to a feature; Ralph targets `feat/<slug>` |
| `high-priority` | Ralph picks these issues first |
| `blocked` | Ralph skips these issues |

Use `/write-a-prd` and `/prd-to-issues` Copilot skills to create PRDs and task issues with the correct labels applied automatically.
