#!/usr/bin/env bash
set -euo pipefail

if [ ! -e /etc/NIXOS ]; then
  echo "error: this script is intended for NixOS" >&2
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v mise >/dev/null
mise install --yes chezmoi@2.69.1
mise exec chezmoi@2.69.1 -- chezmoi --source "$repo_dir" apply
mise exec node -- npm install --global --prefix "$HOME/.local" \
  @openai/codex@latest @anthropic-ai/claude-code@latest
