# Ralph — Routing Logic

## Per-iteration routing

Each iteration, Ralph scans task state and picks a mode using the following priority order:

```mermaid
flowchart TD
    START([🤖 Iteration starts]) --> R1{Any task\nneeds_review?}

    R1 -->|Yes| REVIEW[review.md]
    R1 -->|No| R2{Any task\napproved?}

    R2 -->|Yes| MERGE[merge.md]
    R2 -->|No| R3{Any task\nneeds_review_2?}

    R3 -->|Yes| REVIEW2[review-round2.md]
    R3 -->|No| R4{Any task\nneeds_fix?}

    R4 -->|fix_count ≥ 2| FORCE[force-approve.md]
    R4 -->|fix_count < 2| FIX[fix.md]
    R4 -->|No| R5{Any task\nin_progress?}

    R5 -->|Yes — resume| FIX
    R5 -->|No| R6{Unblocked\npending task?}

    R6 -->|Yes| IMPL[implement.md]
    R6 -->|No| R7{All pending\ntasks blocked?}

    R7 -->|Yes| BLOCKED([⏸ Stop — blocked])
    R7 -->|No| R8{All tasks\ndone?}

    R8 -->|No| FALLBACK([✅ Stop — no work])
    R8 -->|Yes| R9{feat→main PR\nalready open?}

    R9 -->|No| FPR[feature-pr.md]
    R9 -->|Yes| COMPLETE([✅ Stop — complete])
    FPR --> COMPLETE
```

## Task lifecycle

State machine for a single task, driven by mode file outcomes:

```mermaid
stateDiagram-v2
    [*] --> pending
    pending --> in_progress : implement.md starts
    in_progress --> needs_review : implement.md commits

    needs_review --> approved : review.md ✓
    needs_review --> needs_fix : review.md ✗

    needs_fix --> needs_review_2 : fix.md\n(fix_count++)
    needs_fix --> done : force-approve.md\n(fix_count ≥ 2)

    needs_review_2 --> approved : review-round2.md ✓
    needs_review_2 --> needs_fix : review-round2.md ✗

    approved --> done : merge.md

    done --> [*]
```

> **Note:** `in_progress` is a crash-recovery sentinel. If Ralph is killed mid-implement, the next iteration sees `in_progress` and routes to `fix.md` to resume. Within a normal run it is transient.
