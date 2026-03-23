---
# status — required. Controls where Ralph routes this task next.
# Allowed values:
#   pending        — not yet started; Ralph will implement this when its turn comes
#   in_progress    — Ralph is currently implementing (set automatically; also used to resume interrupted work)
#   needs_review   — implementation is committed; waiting for code review
#   needs_fix      — reviewer found issues; Ralph will apply fixes
#   needs_review_2 — fixes committed; waiting for a second review pass
#   done           — task is complete; branch has been merged into the feature branch
status: done

# priority — optional. Controls which pending task Ralph picks first.
# Allowed values:
#   normal  — default; tasks are picked in filename order
#   high    — picked before any normal-priority pending task
priority: normal

# blocked_by — optional. List of task IDs (filename prefixes) that must be done first.
# Use the numeric prefix from the filename, e.g. "01" for "01-example-task.md".
# Ralph skips this task until all listed IDs have status: done.
# Example: blocked_by: ["02", "03"]
blocked_by: []

# branch — set automatically by Ralph. Do not edit by hand.
# Ralph writes the local git branch name here after implement mode creates it,
# e.g. ralph/task-01. Review, fix, and merge modes read it from here.
branch:

# fix_count — set automatically by Ralph. Do not edit by hand.
# Incremented each time the fix mode runs. When fix_count reaches 2,
# Ralph escalates to force-approve mode instead of requesting another review.
fix_count: 0

# review_notes — set automatically by Ralph. Do not edit by hand.
# An append-only list of | block scalars. Each review round adds a new entry.
# The fix mode reads the last entry as its actionable instruction.
# review-round2 reads the full list for context before writing a new entry.
review_notes: []
---

# Example Task: Add notification preferences API endpoint

## Description

Create a `POST /api/notifications/preferences` endpoint that accepts a JSON body with `email`, `push`, and `in_app` boolean fields and persists them to the database for the authenticated user.

## Acceptance criteria

- [ ] `POST /api/notifications/preferences` returns `200 OK` with the saved preferences
- [ ] Invalid payloads return `400 Bad Request` with a descriptive error message
- [ ] Unauthenticated requests return `401 Unauthorized`
- [ ] Unit tests cover the happy path and the two error cases above
