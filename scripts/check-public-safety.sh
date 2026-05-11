#!/usr/bin/env bash
set -euo pipefail

staged_and_tracked_files="$(
  {
    git ls-files
    git diff --cached --name-only
  } | sort -u
)"

exclude_regex='^(\.git/|scripts/check-public-safety\.sh$)'
secret_regex='(BEGIN (RSA|DSA|EC|OPENSSH|PGP) PRIVATE KEY|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,})'
assignment_regex='(api[_-]?key|access[_-]?token|secret|password|passwd|private[_-]?key)[[:space:]]*[:=][[:space:]]*["'\'']?[^"'\'']{8,}'

status=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || continue
  if [[ "$file" =~ $exclude_regex ]]; then
    continue
  fi
  secret_matches="$(grep -nIE "$secret_regex" -- "$file" || true)"
  if [ -n "$secret_matches" ]; then
    while IFS=: read -r line _; do
      echo "potential secret pattern in $file:$line" >&2
    done <<<"$secret_matches"
    status=1
  fi

  assignment_matches="$(grep -niIE -I "$assignment_regex" -- "$file" || true)"
  if [ -n "$assignment_matches" ]; then
    while IFS=: read -r line _; do
      echo "potential credential assignment in $file:$line" >&2
    done <<<"$assignment_matches"
    status=1
  fi
done <<<"$staged_and_tracked_files"

exit "$status"
