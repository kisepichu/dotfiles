# Current State

Last updated: 2026-09-12

## Summary

This repository is a public chezmoi source tree for a new Windows PC with WSL Ubuntu, with separate macOS and NixOS bootstrap paths. The NixOS path consumes system-provided `git`, `curl`, and `mise`, then applies the shared chezmoi source. Applying the source installs the agent CLIs at user level on every platform: Codex through `mise`, omp and Claude Code through their upstream installers.

Implemented and committed:

- Agent workflows for Claude Code and Codex
- `prek`/`pre-commit` hooks with `secretlint`
- Tooling strategy and Nix adoption policy
- Inventory of old/current dotfiles
- Managed `fish` config
- Managed `tmux` config (truecolor + OSC 52 clipboard pass-through, including nested tmux)
- Managed LazyVim-based `nvim` config
- Managed `mise` config
- Managed `starship` prompt config and `zoxide` activation
- Managed WezTerm config on macOS (`darwin` only via `.chezmoiignore`)
- WSL Ubuntu / macOS / NixOS bootstrap scripts
- Repo-root `mise.toml` so bootstrap activates `chezmoi` without mise's inactive-tool warning
- Optional WSL Ubuntu Docker Engine install script
- Windows-friendly Karabiner-Elements profile (including fn+Shift+Space → F13 for WezTerm QuickSelect)

Recent landed work (since 2026-07-26):

- NixOS bootstrap hardening (repeatable apply, avoid Node source builds)
- tmux terminal capability fixes and regression tests
- WezTerm QuickSelect routed around macOS input-source interception via Karabiner F13
- Bootstrap scripts install/exec `chezmoi` from repo `mise.toml` (no `chezmoi@VERSION`)
- TASK-007..013 and TASK-015 moved under `tasks/done/`; open follow-ups remain in `tasks/` (TASK-014 e2e, TASK-016 Mac verification)
- Session design/plans under `docs/superpowers/{specs,plans}/` are kept as history
- Agent CLIs unified across platforms: Codex via the `mise` tool list, omp and Claude Code via `run_once_after_50-install-agent-clis.sh` (first install only; both self-update)

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
- `~/.config/chezmoi/chezmoi.toml` with `~/repos/dotfiles` as the default source

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
- `run_once_after_50-install-agent-clis.sh`

Optional scripts:

- `scripts/install-docker-engine-wsl.sh` installs Docker Engine inside WSL Ubuntu from Docker's official apt repository.
- `scripts/bootstrap-macos.sh` installs Homebrew packages, Karabiner-Elements, WezTerm, mise, applies this chezmoi source (via repo `mise.toml` + `--force`), and runs conservative macOS defaults.
- `scripts/bootstrap-nixos.sh` applies this chezmoi source on NixOS using system-provided mise and installs the declared mise tools; the agent CLIs come from the shared chezmoi run scripts, and no login is performed.
- `scripts/bootstrap-wsl-ubuntu.sh` installs mise if needed, applies this chezmoi source from repo `mise.toml`, and prints fish/`chsh` hints when possible.
- `scripts/configure-macos-defaults.sh` applies macOS defaults for key repeat, Finder, Dock, trackpad tap-to-click, and Mission Control Ctrl+Arrow hotkeys that steal tmux pane swaps.

macOS:

- `~/.config/karabiner/karabiner.json`
- `~/.config/wezterm/wezterm.lua`

## Decisions

- The README bootstrap flow is the supported fresh WSL setup path. `chezmoi init --apply` is not being pursued as an additional shortcut because the bootstrap script already installs the required user-local tools and applies this source tree.
- Docker Engine remains optional and outside the core bootstrap. Use `scripts/install-docker-engine-wsl.sh` when container-based project work is needed.

## Repo-Only Files

These are intentionally excluded by `.chezmoiignore`:

- `AGENTS.md`
- `README.md`
- `mise.toml` (repo bootstrap pin; user tools live in `~/.config/mise/config.toml`)
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
- `env XDG_CONFIG_HOME="$PWD/dot_config" XDG_STATE_HOME=/tmp/dotfiles-nvim-state XDG_CACHE_HOME=/tmp/dotfiles-nvim-cache nvim --headless '+lua require("config.lazy")' '+quitall'`
- rendered shell syntax checks for chezmoi scripts with `chezmoi --source . execute-template ... | bash -n`
- `scripts/install-docker-engine-wsl.sh` on a test WSL distro after enabling systemd
- rerun of `scripts/install-docker-engine-wsl.sh` on the test WSL distro with `ADD_USER_TO_DOCKER_GROUP=1` after Docker was already installed
- `docker run --rm hello-world` and `docker compose version` as the normal user on the test WSL distro

Verified on `glaceon` (NixOS 25.11) on 2026-07-26:

- `scripts/bootstrap-nixos.sh` completed successfully and completed again on rerun.
- `nvim --headless` loaded the managed LazyVim configuration.
- `tmux` loaded the managed configuration in an isolated server.
- `codex --version` and `claude --version` both completed successfully.

Not yet done:

- Full end-to-end verification for Claude PR-review Actions path (TASK-014).
- Remaining Mac hardware checks for TASK-016 (pane swap / auto-zoom / QuickSelect after Karabiner F13 change).
- Decide whether to keep `tasks/` long-term or standardize on superpowers plans/specs (see issue #31).

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
5. Consider adding `gitleaks` in addition to `secretlint`.
6. Continue Phase 4 template/private config cleanup.
7. Resolve issue #31 (task workflow vs superpowers).
