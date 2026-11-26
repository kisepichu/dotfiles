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

echo "NixOS bootstrap completed."

# NixOS installs these system-wide; this repository only configures them. A
# missing one means the host's NixOS configuration does not list it yet (for
# desktop hosts: modules/desktop.nix in the private infra-private repository).
os_commands=(curl fish gcc git tmux)
if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
  # wl-copy backs Neovim's clipboard (LazyVim sets clipboard=unnamedplus);
  # cloudflared backs ~/.local/bin/cloudflared-access-ssh-proxy.
  os_commands+=(cloudflared wezterm wl-copy)
fi
missing_os_commands=()
for os_command in "${os_commands[@]}"; do
  if ! command -v "$os_command" >/dev/null 2>&1; then
    missing_os_commands+=("$os_command")
  fi
done
if [ "${#missing_os_commands[@]}" -gt 0 ]; then
  echo "warning: not provided by the NixOS configuration: ${missing_os_commands[*]}" >&2
  echo "hint: add them to the host's environment.systemPackages, rebuild the system, then rerun this script" >&2
fi

login_shell="$(getent passwd "${USER:-$(id -un)}" 2>/dev/null | cut -d: -f7 || true)"
if [ -n "$login_shell" ] && [ "${login_shell##*/}" != fish ]; then
  echo "hint: login shell is $login_shell; set 'programs.fish.enable = true;' and 'users.users.<name>.shell = pkgs.fish;' in the NixOS configuration" >&2
fi

echo "Next: open a new fish shell, then log in once per machine: codex login, claude login, cursor-agent login, omp (/login)."
