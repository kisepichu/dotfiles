#!/usr/bin/env bash
set -euo pipefail

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "warning: this script is intended for Ubuntu on WSL" >&2
fi

missing_commands=()
for required_command in curl grep head ln mkdir mktemp sed sh; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    missing_commands+=("$required_command")
  fi
done

if [ "${#missing_commands[@]}" -gt 0 ]; then
  echo "error: missing required command(s): ${missing_commands[*]}" >&2
  echo "hint: install Ubuntu base utilities, for example: sudo apt update && sudo apt install -y curl coreutils grep sed" >&2
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected_repo_dir="$HOME/repos/chezmoi-dotfiles"
chezmoi_cmd=(mise exec chezmoi@2.69.1 -- chezmoi)
mise_version="$(
  sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$repo_dir/.chezmoidata.toml" | head -n 1
)"
: "${mise_version:=v2026.4.28}"

if [ "$repo_dir" != "$expected_repo_dir" ]; then
  if [ ! -e "$expected_repo_dir" ] || [ -L "$expected_repo_dir" ]; then
    mkdir -p "$(dirname "$expected_repo_dir")"
    ln -sfn "$repo_dir" "$expected_repo_dir"
  elif [ ! -d "$expected_repo_dir" ]; then
    echo "error: chezmoi default source path exists but is not a directory: $expected_repo_dir" >&2
    exit 1
  elif [ "$(cd "$expected_repo_dir" && pwd -P)" != "$(cd "$repo_dir" && pwd -P)" ]; then
    echo "warning: chezmoi default source is $expected_repo_dir, but bootstrap is running from $repo_dir" >&2
  fi
fi

install_mise() {
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT
  curl -fsSL https://mise.run -o "$installer"
  MISE_VERSION="$mise_version" sh "$installer"
}

if ! command -v mise >/dev/null 2>&1; then
  install_mise
  export PATH="$HOME/.local/bin:$PATH"
fi

mise install --yes chezmoi@2.69.1
"${chezmoi_cmd[@]}" --source "$repo_dir" apply
