#!/usr/bin/env bash
set -euo pipefail

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "warning: this script is intended for Ubuntu on WSL" >&2
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chezmoi_cmd=(chezmoi)

if ! command -v chezmoi >/dev/null 2>&1; then
  if command -v mise >/dev/null 2>&1; then
    mise install chezmoi@2.69.1
  else
    curl -fsSL https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"
    mise install chezmoi@2.69.1
  fi

  chezmoi_cmd=(mise exec chezmoi -- chezmoi)
fi

"${chezmoi_cmd[@]}" --source "$repo_dir" apply
