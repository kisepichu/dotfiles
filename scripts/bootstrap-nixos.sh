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

if ! command -v mise >/dev/null 2>&1; then
  echo "error: mise is required but was not found on PATH" >&2
  echo "hint: on NixOS, install/enable mise at the system level before running this script" >&2
  exit 1
fi
if [ ! -f "$repo_dir/mise.toml" ]; then
  echo "error: missing $repo_dir/mise.toml (needed to activate bootstrap chezmoi)" >&2
  exit 1
fi
(
  cd "$repo_dir"
  # Install/exec chezmoi from repo mise.toml (no CLI @version) to avoid mise's
  # "installed but not activated" warning on ad-hoc tool@version installs.
  mise install --yes chezmoi
  mise exec -- chezmoi --source "$repo_dir" --force apply
)
