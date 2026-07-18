#!/usr/bin/env bash
set -euo pipefail

if [ ! -e /etc/NIXOS ]; then
  echo "error: this script is intended for NixOS" >&2
  exit 1
fi

if [ "${MISE_NODE_COMPILE+x}" != x ]; then
  MISE_NODE_COMPILE=0
fi
if [ "${MISE_NODE_CONCURRENCY+x}" != x ]; then
  MISE_NODE_CONCURRENCY=2
fi
export MISE_NODE_COMPILE MISE_NODE_CONCURRENCY

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

command -v mise >/dev/null
mise install --yes chezmoi@2.69.1
mise exec chezmoi@2.69.1 -- chezmoi --source "$repo_dir" --force apply
mise exec node -- npm install --global --prefix "$HOME/.local" \
  @openai/codex@latest @anthropic-ai/claude-code@latest
