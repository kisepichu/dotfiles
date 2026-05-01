#!/usr/bin/env bash
set -euo pipefail

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi is required for this check" >&2
  exit 1
fi

managed="$(chezmoi --source . managed)"
ignored="$(chezmoi --source . ignored)"

require_managed=(
  ".claude/commands/spec-do.md"
  ".claude/commands/spec-review.md"
  ".claude/commands/spec-update.md"
  ".claude/skills/commit/SKILL.md"
  ".claude/skills/pr-review/SKILL.md"
  ".claude/skills/spec-workflow/SKILL.md"
  ".codex/skills/commit"
  ".codex/skills/pr-review"
  ".codex/skills/spec-workflow"
)

require_ignored=(
  "AGENTS.md"
  "docs"
  "scripts"
)

forbidden_managed=(
  ".pre-commit-config.yaml"
  ".secretlintrc.json"
  "AGENTS.md"
  "docs/plan.md"
  "scripts/check-chezmoi-managed.sh"
)

for path in "${require_managed[@]}"; do
  if ! grep -Fxq "$path" <<<"$managed"; then
    echo "expected chezmoi managed path missing: $path" >&2
    exit 1
  fi
done

for path in "${require_ignored[@]}"; do
  if ! grep -Fxq "$path" <<<"$ignored"; then
    echo "expected chezmoi ignored path missing: $path" >&2
    exit 1
  fi
done

for path in "${forbidden_managed[@]}"; do
  if grep -Fxq "$path" <<<"$managed"; then
    echo "repo-only path is unexpectedly chezmoi managed: $path" >&2
    exit 1
  fi
done
