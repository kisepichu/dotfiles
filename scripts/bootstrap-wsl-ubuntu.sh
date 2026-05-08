#!/usr/bin/env bash
set -euo pipefail

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "warning: this script is intended for Ubuntu on WSL" >&2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chezmoi_cmd=(chezmoi)
mise_version="v2026.4.28"

install_mise() {
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT
  curl -fsSL https://mise.run -o "$installer"
  MISE_VERSION="$mise_version" sh "$installer"
}

if ! command -v chezmoi >/dev/null 2>&1; then
  if command -v mise >/dev/null 2>&1; then
    mise install chezmoi@2.69.1
  else
    install_mise
    export PATH="$HOME/.local/bin:$PATH"
    mise install chezmoi@2.69.1
  fi

  chezmoi_cmd=(mise exec chezmoi@2.69.1 -- chezmoi)
fi

"${chezmoi_cmd[@]}" --source "$repo_dir" apply
