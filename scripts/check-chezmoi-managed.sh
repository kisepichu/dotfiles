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
  ".claude/skills/pr/SKILL.md"
  ".claude/skills/pr-review/SKILL.md"
  ".claude/skills/pr-review/scripts/get-review-comments.py"
  ".claude/skills/pr-review/scripts/reply-review-comment.py"
  ".claude/skills/pr-review/scripts/resolve-review-threads.py"
  ".claude/skills/pr-review/scripts/validate-gh-api.py"
  ".claude/skills/pr-review/scripts/wait-copilot-review.py"
  ".claude/skills/review/SKILL.md"
  ".claude/skills/spec-setup/SKILL.md"
  ".claude/skills/spec-setup/templates/spec-do.md"
  ".claude/skills/spec-setup/templates/spec-review.md"
  ".claude/skills/spec-setup/templates/spec-update.md"
  ".codex/skills/commit"
  ".codex/skills/pr"
  ".codex/skills/pr-review"
  ".codex/skills/review"
  ".codex/skills/spec-setup"
  ".codex/skills/skill-improvement/SKILL.md"
  ".codex/skills/skill-improvement/agents/openai.yaml"
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
)

require_source=(
  "dot_config/karabiner/karabiner.json"
  "run_once_before_10-install-apt-packages.sh.tmpl"
  "run_once_before_12-install-homebrew-packages.sh.tmpl"
  "run_once_before_15-install-mise.sh.tmpl"
  "run_once_before_20-install-tmux-plugin-manager.sh"
  "run_onchange_after_40-mise-install.sh.tmpl"
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

for path in "${require_source[@]}"; do
  if [ ! -f "$path" ]; then
    echo "expected chezmoi source script missing: $path" >&2
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
