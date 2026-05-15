# Current State

Last updated: 2026-05-15

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
- Managed `starship` prompt config and `zoxide` activation
- WSL Ubuntu bootstrap scripts
- Optional WSL Ubuntu Docker Engine install script

Recent implementation commits before this handoff update include:

- WSL bootstrap hardening for fresh Ubuntu and repo path handling
- Managed `~/.config/chezmoi/chezmoi.toml` with `~/repos/chezmoi-dotfiles` as the default source
- `mise` install rerun trigger when `dot_config/mise/config.toml` changes
- Fish startup ordering so `mise` activation happens before `starship`/`zoxide` initialization
- Public safety scan fixes from PR review

## Important State

The source tree is ahead of the current home directory.

`tasks/done/TASK-001-core-tools-import.md` is complete. Phase 3 bootstrap verification has passed on a fresh WSL Ubuntu instance.

The bootstrap/apply path has been updated after fresh WSL testing found two issues:

- standalone `chezmoi apply` used the upstream default `~/.local/share/chezmoi` source before this repo installed a managed chezmoi config
- `starship` and `zoxide` could remain missing if they were added to `dot_config/mise/config.toml` after the previous `run_onchange` script had already run

Both were fixed before the fresh WSL confirmation.

`chezmoi --source . apply` may not have been run on the primary work machine after importing `fish`, `tmux`, `nvim`, and `mise`.

Expected `chezmoi --source . status` differences:

- `~/.claude/skills/commit/SKILL.md` if the local installed skill has not been reapplied after source updates
- run script sources: `run_once_before_10-install-apt-packages.sh.tmpl`, `run_once_before_15-install-mise.sh.tmpl`, `run_once_before_20-install-tmux-plugin-manager.sh`, `run_onchange_after_40-mise-install.sh.tmpl`
- `~/.config/fish/*`
- `~/.config/mise/config.toml`
- `~/.config/nvim/*`
- `~/.config/starship.toml`
- `~/.tmux.conf`

This is not a repo inconsistency. It means the source has been prepared but not applied to the current machine.

Applying on the current machine will:

- replace the old `~/.tmux.conf` symlink to `../dotfiles` with a managed file
- update `~/.config/fish/config.fish` so it no longer sources `~/.bashrc`
- set `BROWSER=wslview` on WSL when `wslview` exists
- update `~/.config/mise/config.toml`
- install user-level `starship` and `zoxide` through `mise install`
- install `~/.config/starship.toml` and enable the `z` command through fish `zoxide init`
- run chezmoi run scripts, including apt package install and `mise install`

Do not run `chezmoi --source . apply` casually if you do not want apt/mise changes on the current machine.

## Managed By Chezmoi

Agent workflow:

- `~/.claude/commands/spec-do.md`
- `~/.claude/commands/spec-review.md`
- `~/.claude/commands/spec-update.md`
- `~/.claude/skills/commit/SKILL.md`
- `~/.claude/skills/pr-review/SKILL.md`
- `~/.claude/skills/pr/SKILL.md`
- `~/.claude/skills/review/SKILL.md`
- `~/.claude/skills/spec-setup/SKILL.md`
- `~/.claude/skills/spec-setup/templates/spec-do.md`
- `~/.claude/skills/spec-setup/templates/spec-review.md`
- `~/.claude/skills/spec-setup/templates/spec-update.md`
- `~/.codex/skills/commit`
- `~/.codex/skills/pr`
- `~/.codex/skills/pr-review`
- `~/.codex/skills/review`
- `~/.codex/skills/spec-setup`
- `~/.codex/skills/skill-improvement`
- `~/.config/chezmoi/chezmoi.toml` with `~/repos/chezmoi-dotfiles` as the default source

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
- `~/.config/starship.toml`

Run scripts:

- `run_once_before_10-install-apt-packages.sh.tmpl`
- `run_once_before_15-install-mise.sh.tmpl`
- `run_once_before_20-install-tmux-plugin-manager.sh`
- `run_onchange_after_40-mise-install.sh.tmpl`

Optional scripts:

- `scripts/install-docker-engine-wsl.sh` installs Docker Engine inside WSL Ubuntu from Docker's official apt repository.

## Repo-Only Files

These are intentionally excluded by `.chezmoiignore`:

- `AGENTS.md`
- `README.md`
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
- `mise exec chezmoi -- chezmoi --version`
- `tmux -f dot_tmux.conf start-server ; source-file -n dot_tmux.conf`
- `env XDG_CONFIG_HOME="$PWD/dot_config" XDG_STATE_HOME=/tmp/chezmoi-dotfiles-nvim-state XDG_CACHE_HOME=/tmp/chezmoi-dotfiles-nvim-cache nvim --headless '+lua require("config.lazy")' '+quitall'`
- rendered shell syntax checks for chezmoi scripts with `chezmoi --source . execute-template ... | bash -n`
- `scripts/install-docker-engine-wsl.sh` on the `chezmoi-dotfiles-test` WSL distro after enabling systemd
- `docker run --rm hello-world` and `docker compose version` as the normal user on `chezmoi-dotfiles-test`

## Next Steps

1. If applying locally, run `chezmoi --source . diff` and inspect carefully.
2. Run `chezmoi --source . apply` only when apt/mise side effects are acceptable.
3. For Docker work, run `scripts/install-docker-engine-wsl.sh` inside WSL Ubuntu and restart WSL before using `docker` without `sudo`.
4. After apply, verify:
   - `fish -n ~/.config/fish/config.fish`
   - `fish -lic 'type starship; type zoxide; type z'`
   - `starship print-config >/dev/null`
   - `tmux source-file ~/.tmux.conf`
   - `nvim --headless '+lua require("config.lazy")' '+quitall'`
   - `mise ls starship zoxide`
5. Confirm the remote GitHub repo URL and document `chezmoi init --apply` flow.
6. Decide whether Docker Engine should remain optional or be included in a future bootstrap phase.
7. Consider adding `gitleaks` in addition to `secretlint`.
