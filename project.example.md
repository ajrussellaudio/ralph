# project.example.md — Ralph Project Configuration Template

Copy this file to `ralph/project.md` in your repository and fill in the values.
Ralph reads this file at Step 0 of every iteration.

## Project

**Name:** <your project name and one-line description>

**GitHub repo:** `<owner>/<repo>` (e.g. `acmecorp/my-app`)

## Build and test commands

```bash
# Replace with your actual build command (or remove if not applicable)
<build command>

# Replace with your actual test command
<test command>
```

## Permanent issue

Issue **#<N>** is the PRD (or equivalent long-lived anchor issue). It must never
be closed or touched. All references in the prompt to "excluding the permanent
issue" or "never touch the permanent issue" refer to this number.

## Branch prefix

Feature branches follow the convention `ralph/issue-<N>` (e.g. `ralph/issue-2`).
This is baked into the prompt as a convention and does not need to change.
