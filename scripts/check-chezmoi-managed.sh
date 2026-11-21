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
  ".claude/settings.json"
  ".claude/skills/commit/SKILL.md"
  ".claude/skills/pr-review/SKILL.md"
  ".claude/skills/pr-review/references/claude-review-setup.md"
  ".claude/skills/pr-review/scripts/get-review-comments.py"
  ".claude/skills/pr-review/scripts/reply-review-comment.py"
  ".claude/skills/pr-review/scripts/resolve-review-threads.py"
  ".claude/skills/pr-review/scripts/wait-copilot-review.py"
  ".claude/skills/pr-review/scripts/wait-claude-review.py"
  ".claude/skills/pr-review/templates/claude-review.yml"
  ".codex/skills/commit"
  ".codex/skills/pr-review"
  ".config/chezmoi/chezmoi.toml"
  ".config/fish/config.fish"
  ".config/fish/fish_plugins"
  ".config/fish/conf.d/nix.fish"
  ".config/fish/conf.d/rustup.fish"
  ".config/fish/functions/dcnvim.fish"
  ".config/fish/functions/dcup.fish"
  ".config/fish/functions/loadenv.fish"
  ".config/fish/functions/y.fish"
  ".config/git/ignore"
  ".config/iamb/config.toml"
  ".config/mise/config.toml"
  ".config/mxt/config.toml"
  ".config/starship.toml"
  ".config/yazi/yazi.toml"
  ".config/nvim/.neoconf.json"
  ".config/nvim/init.lua"
  ".config/nvim/lazy-lock.json"
  ".config/nvim/lazyvim.json"
  ".config/nvim/stylua.toml"
  ".omp/agent/skills/commit"
  ".omp/agent/skills/pr-review"
  ".local/bin/cloudflared-access-ssh-proxy"
  ".local/bin/omp-panes"
  ".tmux.conf"
  ".tmux/new-session"
)

require_source=(
  "Brewfile"
  "dot_config/karabiner/karabiner.json"
  "dot_gitconfig"
  "mise.toml"
  "scripts/bootstrap-nixos.sh"
  "scripts/bootstrap-wsl-ubuntu.sh"
  "scripts/install-devcontainer-neovim.sh"
  "run_once_before_10-install-apt-packages.sh.tmpl"
  "run_onchange_before_12-install-homebrew-packages.sh.tmpl"
  "run_once_before_15-install-mise.sh.tmpl"
  "run_once_before_20-install-tmux-plugin-manager.sh"
  "run_onchange_after_25-install-tmux-plugins.sh.tmpl"
  "run_onchange_after_27-install-fish-plugins.sh.tmpl"
  "run_after_28-link-docker-cli-plugins.sh.tmpl"
  "run_onchange_after_30-fix-cloudflared-ssh-proxy.sh"
  "run_onchange_after_35-install-windows-wezterm-config.sh.tmpl"
  "run_onchange_after_40-mise-install.sh.tmpl"
  "run_after_50-install-agent-clis.sh"
)

require_ignored=(
  "AGENTS.md"
  "Brewfile"
  "docs"
  "mise.toml"
  "tasks"
  "scripts"
)

forbidden_managed=(
  ".pre-commit-config.yaml"
  ".secretlintrc.json"
  "AGENTS.md"
  "docs/plan.md"
  "mise.toml"
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
