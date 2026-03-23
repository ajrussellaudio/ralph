---
# label: the feature slug passed to `ralph --label=<label>`.
#         Ralph uses this to derive the feature branch (feat/<label>)
#         and to scope PRD issues (prd/<label>).
label: foo-widget

# prd: one paragraph describing the feature and its goals.
#      Use the YAML literal block scalar (|) to preserve newlines.
prd: |
  Build a foo-widget that allows users to frobnicate their baz. The widget should
  support high-throughput frob operations and degrade gracefully under load.
---

<!-- Field reference (this block is ignored by the seed parser):

  ## Task N — Short title          required; N must be sequential from 1
  **Priority:** high               optional; omit for normal priority
  **Blocked by:** N                optional; Ralph skips until task N is done

  Everything else below the heading becomes the task body / acceptance criteria.
-->

## Task 1 — Implement core frob engine
**Priority:** high

Add `src/frob.ts` with the core frob algorithm.

### Acceptance criteria

- Exports a `frobEngine(baz: Baz): FrobResult` function
- Handles `null` / `undefined` inputs by returning `{ ok: false, error: "invalid input" }`
- Covered by unit tests in `src/frob.test.ts`

## Task 2 — Add REST endpoint

Expose `POST /frob` that accepts `{ baz: Baz }` and returns `FrobResult`.
Validate the request body and return 400 on bad input.

## Task 3 — Add rate limiting
**Blocked by:** 2

Wrap the `/frob` endpoint with a rate limiter (max 100 req/min per IP).
Use the existing `src/middleware/rateLimit.ts` pattern.

## Task 4 — Add metrics dashboard

Surface per-endpoint request counts and p99 latency on `GET /metrics`.
Read values from the in-memory counters already updated by the rate-limiter middleware.
