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
expected_repo_dir="$HOME/repos/dotfiles"
# Install/exec chezmoi from repo mise.toml (no CLI @version) so mise does not
# treat it as an inactive ad-hoc install.
chezmoi_cmd=(mise exec -- chezmoi)
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

if [ ! -f "$repo_dir/mise.toml" ]; then
  echo "error: missing $repo_dir/mise.toml (needed to activate bootstrap chezmoi)" >&2
  exit 1
fi

(
  cd "$repo_dir"
  mise install --yes chezmoi
  "${chezmoi_cmd[@]}" --source "$repo_dir" --force apply
)

echo "WSL Ubuntu bootstrap completed."

fish_path="$(command -v fish || true)"
if [ -n "$fish_path" ]; then
  current_shell=""
  if command -v getent >/dev/null 2>&1 && command -v cut >/dev/null 2>&1; then
    current_user="${USER:-$(id -un)}"
    current_shell="$(getent passwd "$current_user" 2>/dev/null | cut -d: -f7 || true)"
  fi
  if [ -z "$current_shell" ]; then
    current_shell="${SHELL:-}"
  fi
  if [ -z "$current_shell" ]; then
    echo "hint: fish is available at $fish_path; if needed, run: chsh -s $fish_path" >&2
    echo "hint: then open a new terminal so mise-managed tools are on PATH" >&2
  elif [ "$current_shell" != "$fish_path" ]; then
    echo "hint: default shell is $current_shell; run: chsh -s $fish_path" >&2
    echo "hint: then open a new terminal so mise-managed tools are on PATH" >&2
  else
    echo "Open a new fish shell (or restart the terminal) if mise tools are not on PATH yet."
  fi
else
  echo "hint: fish was not found on PATH after apply; re-run this script or install fish, then chsh" >&2
fi
