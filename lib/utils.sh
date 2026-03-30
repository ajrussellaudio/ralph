#!/usr/bin/env bash
# utils.sh — shared utilities for ralph.sh and lib/*.sh
#
# Sourced by ralph.sh and individual lib scripts.

# gh_with_retry() — wrapper around `gh` that retries up to 3 times on failure.
#
# Usage: gh_with_retry [gh args...]
#
# Behaviour:
#   - Forwards all arguments and stdin verbatim to `gh`
#   - On success (exit 0): returns immediately with stdout/stderr intact
#   - On failure (non-zero exit):
#       - Prints a warning to stderr with attempt number and backoff delay
#       - Sleeps 1s before attempt 2, 2s before attempt 3
#       - Retries
#   - After 3 failed attempts: prints a final error to stderr and returns the
#     last non-zero exit code
gh_with_retry() {
  local max_attempts=3
  local attempt=1
  local exit_code

  while (( attempt <= max_attempts )); do
    gh "$@" && return 0
    exit_code=$?

    if (( attempt < max_attempts )); then
      local delay=$(( attempt ))
      printf '  ⚠️  gh call failed (attempt %d/%d) — retrying in %ds…\n' \
        "$attempt" "$max_attempts" "$delay" >&2
      sleep "$delay"
    fi

    (( attempt++ ))
  done

  printf '  ❌  gh call failed after %d attempts: gh %s\n' \
    "$max_attempts" "$*" >&2
  return "$exit_code"
}
