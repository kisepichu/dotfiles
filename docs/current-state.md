# Current State

Last updated: 2026-05-04

## Summary

This repository is a public chezmoi source tree for a new Windows PC with WSL Ubuntu.

Implemented and committed:

- Agent workflows for Claude Code and Codex
- `prek`/`pre-commit` hooks with `secretlint`
- Tooling strategy and Nix adoption policy
- Inventory of old/current dotfiles
- Managed `fish` config
- Managed `tmux` config
- Managed LazyVim-based `nvim` config
- Managed `mise` config
- WSL Ubuntu bootstrap scripts

Recent implementation commits before this handoff update:

- `943e676 Add WSL bootstrap scripts`
- `d4e7464 Import Neovim configuration`
- `e84224e Import fish configuration`
- `f6dc442 Import tmux configuration`
- `569e8ca Inventory core dotfiles`
- `7ee046d Document local tooling strategy`
- `41ff496 Set up chezmoi agent workflows`

## Important State

The source tree is ahead of the current home directory.

`tasks/done/TASK-001-core-tools-import.md` is complete. The next task should start from Phase 3 verification and Windows/WSL documentation.

`chezmoi --source . apply` has not been run on this machine after importing `fish`, `tmux`, `nvim`, and `mise`.

Expected `chezmoi --source . status` differences:

- `~/.claude/skills/commit/SKILL.md` if the local installed skill has not been reapplied after source updates
- run scripts: `10-install-apt-packages.sh`, `15-install-mise.sh`, `20-install-tmux-plugin-manager.sh`, `40-mise-install.sh`
- `~/.config/fish/*`
- `~/.config/mise/config.toml`
- `~/.config/nvim/*`
- `~/.tmux.conf`

This is not a repo inconsistency. It means the source has been prepared but not applied to the current machine.

Applying on the current machine will:

- replace the old `~/.tmux.conf` symlink to `../dotfiles` with a managed file
- update `~/.config/fish/config.fish` so it no longer sources `~/.bashrc`
- set `BROWSER=wslview` on WSL when `wslview` exists
- update `~/.config/mise/config.toml`
- run chezmoi run scripts, including apt package install and `mise install`

Do not run `chezmoi --source . apply` casually if you do not want apt/mise changes on the current machine.

## Managed By Chezmoi

Agent workflow:

- `~/.claude/commands/spec-do.md`
- `~/.claude/commands/spec-review.md`
- `~/.claude/commands/spec-update.md`
- `~/.claude/skills/commit/SKILL.md`
- `~/.claude/skills/pr-review/SKILL.md`
- `~/.claude/skills/spec-workflow/SKILL.md`
- `~/.codex/skills/commit`
- `~/.codex/skills/pr-review`
- `~/.codex/skills/spec-workflow`

Core tools:

- `~/.config/fish/config.fish`
- `~/.config/fish/fish_plugins`
- `~/.config/fish/conf.d/nix.fish`
- `~/.config/fish/conf.d/rustup.fish`
- `~/.tmux.conf`
- `~/.tmux/new-session`
- `~/.config/nvim/init.lua`
- `~/.config/nvim/lazy-lock.json`
- `~/.config/nvim/lazyvim.json`
- `~/.config/nvim/stylua.toml`
- `~/.config/nvim/.neoconf.json`
- `~/.config/nvim/lua/config/*.lua`
- `~/.config/nvim/lua/plugins/*.lua`
- `~/.config/mise/config.toml`

Run scripts:

- `run_once_before_10-install-apt-packages.sh.tmpl`
- `run_once_before_15-install-mise.sh.tmpl`
- `run_once_before_20-install-tmux-plugin-manager.sh`
- `run_onchange_after_40-mise-install.sh.tmpl`

## Repo-Only Files

These are intentionally excluded by `.chezmoiignore`:

- `AGENTS.md`
- `docs/`
- `tasks/`
- `scripts/`
- `.pre-commit-config.yaml`
- `.secretlintrc.json`

## Validation Already Done

Previously passed:

- `prek run --all-files`
- `fish -n dot_config/fish/config.fish`
- `fish_indent --check dot_config/fish/config.fish`
- `tmux -f dot_tmux.conf start-server ; source-file -n dot_tmux.conf`
- `env XDG_CONFIG_HOME="$PWD/dot_config" XDG_STATE_HOME=/tmp/chezmoi-dotfiles-nvim-state XDG_CACHE_HOME=/tmp/chezmoi-dotfiles-nvim-cache nvim --headless '+lua require("config.lazy")' '+quitall'`
- rendered shell syntax checks for chezmoi scripts with `chezmoi --source . execute-template ... | bash -n`

## Next Steps

1. Decide whether to apply on the current machine or test only on fresh WSL first.
2. If applying locally, run `chezmoi --source . diff` and inspect carefully.
3. Run `chezmoi --source . apply` only when apt/mise side effects are acceptable.
4. After apply, verify:
   - `fish -n ~/.config/fish/config.fish`
   - `tmux source-file ~/.tmux.conf`
   - `nvim --headless '+lua require("config.lazy")' '+quitall'`
   - `mise ls --current`
5. Write `docs/windows-wsl.md` for Windows-side setup.
6. Confirm the remote GitHub repo URL and document `chezmoi init --apply` flow.
7. Consider adding `gitleaks` in addition to `secretlint`.
