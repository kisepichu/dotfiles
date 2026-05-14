#!/usr/bin/env bash
set -euo pipefail

status=0

while IFS= read -r skill; do
  python3 - "$skill" <<'PY' || status=1
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

if not text.startswith("---\n"):
    print(f"{path}: missing YAML frontmatter", file=sys.stderr)
    raise SystemExit(1)

try:
    _, frontmatter, _ = text.split("---\n", 2)
except ValueError:
    print(f"{path}: unterminated YAML frontmatter", file=sys.stderr)
    raise SystemExit(1)

required = ("name", "description")
for key in required:
    if not re.search(rf"^{key}:\s*.+$", frontmatter, re.MULTILINE):
        print(f"{path}: missing {key} in frontmatter", file=sys.stderr)
        raise SystemExit(1)
PY
done < <(find dot_claude/skills dot_codex/skills -path '*/SKILL.md' -type f | sort)

exit "$status"
