---
title: Mode template instructions (implement + fix)
priority: normal
blocked_by: [2]
status: pending
branch: ""
review_notes: ""
fix_count: 0
---

## Parent PRD

`plans/pre-commit-checks.md`

## What to build

Add pre-commit check instructions to the `implement` and `fix` mode templates so the agent knows to run the configured checks before making code commits. The instructions must be conditional (skip if no checks configured), specify fail-fast execution, auto-fix behavior, restart-from-beginning after fixes, a 2-retry cap, and revert+STOP on exhaustion.

### `modes/implement.md` changes

Insert a new step **before** the current Step 5 (Verify). This means the current Step 5 becomes Step 6, and all subsequent steps are renumbered.

The new step should be titled something like "Pre-Commit Checks" and contain instructions like:

```markdown
## Step 5 — Pre-Commit Checks

**If `{{PRE_COMMIT_CHECKS}}` is empty, skip this step entirely.**

Before committing code, run the following checks in order:

{{PRE_COMMIT_CHECKS}}

**Rules:**
- Run each check in sequence using a sub-agent. **Stop at the first failure** (fail-fast).
- If a check fails, attempt to **auto-fix** the issue (e.g. run the formatter, fix the lint error).
- After any fix, **restart all checks from check 1** — a fix for one check may break an earlier one.
- Track how many times each check has failed and been retried. After **2 failed fix attempts for the same check**, give up.
- If you exhaust retries: revert changes (`git checkout -- .` or `git stash`), emit `<promise>STOP</promise>`, and stop.
```

Then the existing Verify step (build+test) follows as Step 6.

**Important:** The pre-commit checks only gate the code commit (the `git add -A && git commit -m "feat/fix/..."` in the Commit step). They do NOT gate bookkeeping chore commits (like `git commit -m "chore: mark task X in_progress"`).

### `modes/fix.md` changes

Insert a similar pre-commit check step **before** the line that runs `{{TEST_CMD}}` in the current Step 3 (Fix). The pre-commit checks should run before the test command, since the design is: pre-commit checks → build+test.

The fix mode currently says:
```
Run `{{TEST_CMD}}` using a sub-agent. Fix any test failures before continuing.
```

Insert pre-commit check instructions above this, with the same rules (fail-fast, auto-fix, restart from top, 2-retry cap, revert+STOP). The instructions should be conditional on `{{PRE_COMMIT_CHECKS}}` being non-empty.

### Instruction details to get right

1. **Conditional execution:** The step must be clearly skippable when `{{PRE_COMMIT_CHECKS}}` is empty. Use bold text or an explicit "skip" instruction so the agent doesn't hallucinate checks.

2. **Fail-fast:** Run checks sequentially, stop at the first failure. Do NOT run remaining checks after a failure.

3. **Auto-fix + restart:** After fixing a failing check, restart ALL checks from check 1 (not just re-run the one that failed). This catches regressions.

4. **Retry cap:** 2 attempts per check. The retry count is per individual check, not per sequence. Example: if check 1 passes, check 2 fails (attempt 1), fix, restart → check 1 passes, check 2 fails (attempt 2) → give up.

5. **Exhaustion behavior:** Same as build/test failure — revert and emit `<promise>STOP</promise>`.

6. **Scope:** Only gates code commits (feat/fix/refactor), not chore commits. Make this explicit in the instructions.

### No changes to other modes

Do NOT modify: `review.md`, `merge.md`, `force-approve.md`, `review-round2.md`.

## Acceptance criteria

- [ ] `modes/implement.md` has a new pre-commit checks step before the existing Verify (build+test) step
- [ ] `modes/fix.md` has pre-commit check instructions before the `{{TEST_CMD}}` line
- [ ] Both templates skip the step when `{{PRE_COMMIT_CHECKS}}` is empty
- [ ] Instructions specify fail-fast (stop at first failure)
- [ ] Instructions specify auto-fix then restart all checks from check 1
- [ ] Instructions specify 2-retry cap per check
- [ ] Instructions specify revert+STOP on exhaustion
- [ ] Instructions clarify that only code commits are gated, not chore commits
- [ ] Step numbering in implement.md is correct after insertion (no duplicate or missing step numbers)
- [ ] No changes to review.md, merge.md, force-approve.md, or review-round2.md

## User stories addressed

- User story 3 (checks run in defined order)
- User story 4 (pre-commit checks run before build+test)
- User story 5 (fail fast on first failure)
- User story 6 (auto-fix on failure)
- User story 7 (restart all checks after a fix)
- User story 8 (2-retry cap)
- User story 9 (revert and STOP on exhaustion)
- User story 10 (only gate code commits, not chore commits)
- User story 11 (implement and fix modes only)
