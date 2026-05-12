#!/usr/bin/env bash
set -euo pipefail

status=0

while IFS= read -r file; do
  [ -n "$file" ] || continue
  if git check-attr binary -- "$file" | grep -q ': binary: set'; then
    continue
  fi
  index_entry="$(git ls-files -s -- "$file")"
  index_mode="${index_entry%% *}"
  case "$index_mode" in
    100*) ;;
    *) continue ;;
  esac
  if ! git cat-file -e ":$file" 2>/dev/null; then
    continue
  fi
  if [ "$(git cat-file -s ":$file")" -gt 0 ] && [ "$(git cat-file blob ":$file" | tail -c 1 | wc -l)" -eq 0 ]; then
    echo "missing newline at EOF: $file" >&2
    status=1
  fi
done < <(git ls-files)

exit "$status"
