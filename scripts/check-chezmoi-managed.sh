#!/usr/bin/env bash
set -euo pipefail

if ! command -v chezmoi >/dev/null 2>&1; then
  echo "chezmoi is required for this check" >&2
  exit 1
fi

managed="$(chezmoi --source . managed)"
ignored="$(chezmoi --source . ignored)"

# These are chezmoi target paths, not repository source filenames.
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
  ".config/chezmoi/chezmoi.toml"
  ".config/fish/config.fish"
  ".config/fish/fish_plugins"
  ".config/fish/conf.d/nix.fish"
  ".config/fish/conf.d/rustup.fish"
  ".config/mise/config.toml"
  ".config/starship.toml"
  ".config/nvim/.neoconf.json"
  ".config/nvim/init.lua"
  ".config/nvim/lazy-lock.json"
  ".config/nvim/lazyvim.json"
  ".config/nvim/stylua.toml"
  ".tmux.conf"
  ".tmux/new-session"
  "10-install-apt-packages.sh"
  "15-install-mise.sh"
  "20-install-tmux-plugin-manager.sh"
  "40-mise-install.sh"
)

require_ignored=(
  "AGENTS.md"
  "docs"
  "tasks"
  "scripts"
)

forbidden_managed=(
  ".pre-commit-config.yaml"
  ".secretlintrc.json"
  "AGENTS.md"
  "docs/plan.md"
  "tasks/done/TASK-001-core-tools-import.md"
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
