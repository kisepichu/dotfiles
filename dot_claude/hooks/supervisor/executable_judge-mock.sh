#!/usr/bin/env bash
# Test backend for the permission supervisor. Returns a fixed verdict so the
# orchestrator can be exercised without invoking a real AI.
#
# Behavior is controlled by env vars:
#   MOCK_DECISION : allow | deny | ask   (default: ask)
#   MOCK_REASON   : reason string        (default: "mock")
#   MOCK_SLEEP    : seconds to sleep      (to exercise timeout handling)
#   MOCK_EXIT     : exit code             (non-zero exercises error handling)
#   MOCK_RAW      : if set, print this raw string instead of JSON
set -uo pipefail

cat >/dev/null  # consume context

[ -n "${MOCK_SLEEP:-}" ] && sleep "$MOCK_SLEEP"

if [ -n "${MOCK_RAW:-}" ]; then
  printf '%s\n' "$MOCK_RAW"
else
  printf '{"decision":"%s","reason":"%s"}\n' "${MOCK_DECISION:-ask}" "${MOCK_REASON:-mock}"
fi

exit "${MOCK_EXIT:-0}"
