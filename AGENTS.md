# dotfiles

This repository is the public, chezmoi-managed source for personal dotfiles and agent workflows.

## Goals

- Keep public-safe dotfiles, setup scripts, and agent workflow assets in one repository.
- Keep secrets and machine-local values outside the public repository.
- Support Windows + WSL Ubuntu first, then other environments.

## Working Rules

- Treat this as a chezmoi source tree: `dot_foo` maps to `~/.foo`, `symlink_foo` creates a symlink, and repository-only docs must be listed in `.chezmoiignore`.
- Do not commit secrets, private URLs, credentials, host-specific paths, or machine-local identity values.
- Prefer small, idempotent setup scripts. A script must be safe to run twice.
- When adding cross-project workflows, put Claude Code slash commands under `dot_claude/commands/` and Codex-compatible workflows under `dot_claude/skills/`, then expose them to Codex and omp with per-skill symlinks in `dot_codex/skills/` and `dot_omp/private_agent/skills/`. When retiring a managed skill or command, list its targets in `.chezmoiremove` so existing machines drop it.
- For command-like workflows in Codex, use skills and natural-language triggers; Codex does not use Claude Code slash commands directly.
- Branch from `main` and open PRs against `main`; there is no `develop` branch. Verify a platform-specific change (WSL, NixOS, macOS) on that platform before merging.
- Before committing, run `prek run --all-files` if `prek` is available. If not, run `pre-commit run --all-files`. Do not commit from this repository without this hook suite passing.
