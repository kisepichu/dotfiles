#!/usr/bin/env bash
set -euo pipefail

# First install only. omp and Claude Code ship self-updating binaries
# (`omp update`, Claude Code's own version manager), so pinning or reinstalling
# them here would fight their updaters: skip whenever the command already
# exists. Codex has no upstream install script and is declared in
# ~/.config/mise/config.toml instead.
#
# Failures stay non-fatal so a network problem cannot abort `chezmoi apply`.

export PATH="$HOME/.local/bin:$PATH"

if ! command -v curl >/dev/null 2>&1; then
  echo "warning: curl is not installed; skipping agent CLI install" >&2
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

install_agent_cli() {
  local name=$1
  local url=$2
  local interpreter=$3
  local installer="$tmp_dir/$name-install.sh"

  if command -v "$name" >/dev/null 2>&1; then
    return 0
  fi

  if ! curl -fsSL "$url" -o "$installer"; then
    echo "warning: failed to download the $name installer from $url" >&2
    return 0
  fi

  if ! "$interpreter" "$installer"; then
    echo "warning: $name installer failed; rerun 'chezmoi apply' after fixing the cause" >&2
    return 0
  fi
}

install_agent_cli omp https://omp.sh/install sh
install_agent_cli claude https://claude.ai/install.sh bash
