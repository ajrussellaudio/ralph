---
label: foo-widget
prd: |
  Build a foo-widget that allows users to frobnicate their baz. The widget should
  support high-throughput frob operations and degrade gracefully under load.
---

## Task 1 — Implement core frob engine
**Priority:** high

Add `src/frob.ts` with the core frob algorithm. The engine must:
- Accept a `Baz` object and return a `FrobResult`
- Handle null/undefined inputs gracefully
- Be covered by unit tests

## Task 2 — Add REST endpoint
**Blocked by:** 1

Expose `POST /frob` that accepts `{ baz: Baz }` and returns `FrobResult`.
Validate the request body and return 400 on bad input.

## Task 3 — Add rate limiting

Wrap the `/frob` endpoint with a rate limiter (max 100 req/min per IP).
Use the existing `src/middleware/rateLimit.ts` pattern.
