# Ralph — Routing Logic

## Per-iteration routing

Each iteration, Ralph syncs the worktree then picks a mode. If an open `ralph/issue-*` PR exists, the review backend determines the path. Otherwise Ralph looks for the next issue to implement.

```mermaid
flowchart TD
    START([🤖 Iteration starts]) --> SYNC[Sync worktree\nto origin/FEATURE_BRANCH]
    SYNC --> R1{Open ralph/issue-*\nPR on FEATURE_BRANCH?}

    R1 -->|Yes — first open PR| BACKEND{Review\nbackend?}

    BACKEND -->|Copilot bot| BOT{Bot review\nstate?}
    BOT -->|None yet| WAIT[wait.md]
    BOT -->|APPROVED| MERGE[merge.md]
    BOT -->|Other / COMMENTED| WAIT
    BOT -->|CHANGES_REQUESTED| BOT_RC{Fix posted\nafter last review?}
    BOT_RC -->|Yes — await re-review| WAIT
    BOT_RC -->|No, fix_count < 10| FIXBOT[fix-bot.md]
    BOT_RC -->|No, fix_count ≥ 10| ESCALATE[escalate.md]

    BACKEND -->|HTML comments| CMT{Comment\nsentinels?}
    CMT -->|APPROVED| MERGE
    CMT -->|fix_count ≥ 10| FORCE[force-approve.md]
    CMT -->|REQUEST_CHANGES\n+ new commits since| REVIEW[review.md]
    CMT -->|REQUEST_CHANGES\nno new commits| FIX[fix.md]
    CMT -->|No review yet| REVIEW

    R1 -->|No open PRs| PINNED{--issue=N\nset?}

    PINNED -->|Yes| PINSTATE{Issue\nstill open?}
    PINSTATE -->|Closed| COMPLETE([✅ Stop — complete])
    PINSTATE -->|Open| IMPL[implement.md]

    PINNED -->|No| LABEL{--label\nset?}

    LABEL -->|Yes — PRD mode| NEXT{Unblocked open\nissue with label?}
    NEXT -->|Yes| IMPL
    NEXT -->|No| FPRCHECK{feat→main PR\nalready open?}
    FPRCHECK -->|No| FPR[feature-pr.md]
    FPRCHECK -->|Yes| COMPLETE

    LABEL -->|No — standalone| STANDALONE{Open non-prd\nissue?}
    STANDALONE -->|Yes| IMPL
    STANDALONE -->|No| COMPLETE
```

## Task lifecycle

State machine for a single issue. State is inferred each iteration from the PR's review comments — nothing is stored explicitly.

```mermaid
stateDiagram-v2
    [*] --> open : issue created

    open --> implementing : implement.md\n(ralph/issue-N branch + draft PR opened)

    implementing --> awaiting_review : implement.md\n(commits pushed)

    awaiting_review --> approved : review ✓\n(APPROVED sentinel or bot approval)
    awaiting_review --> needs_fix : review ✗\n(REQUEST_CHANGES)

    needs_fix --> awaiting_review : fix.md / fix-bot.md\n(fix_count++)
    needs_fix --> done : force-approve.md / escalate.md\n(fix_count ≥ 10)

    approved --> done : merge.md\n(PR merged, branch deleted, issue closed)

    done --> [*]
```

> **Note:** `wait` is a transient hold state (not shown above) used when the Copilot bot has been asked to review but hasn't responded yet, or when a fix has been posted and Ralph is waiting for the bot to re-review.
