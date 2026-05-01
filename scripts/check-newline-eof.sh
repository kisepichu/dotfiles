#!/usr/bin/env bash
set -euo pipefail

status=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  [ -f "$file" ] || continue
  if git check-attr binary -- "$file" | grep -q ': binary: set'; then
    continue
  fi
  if [ -s "$file" ] && [ "$(tail -c 1 "$file" | wc -l)" -eq 0 ]; then
    echo "missing newline at EOF: $file" >&2
    status=1
  fi
done < <(git ls-files --others --cached --exclude-standard)

exit "$status"
