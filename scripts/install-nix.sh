#!/usr/bin/env bash
set -euo pipefail

# Install Nix using the Determinate Nix Installer.
#
# Nix is intentionally NOT part of the core dotfiles bootstrap (see
# docs/tooling-strategy.md). Run this script explicitly when a reproducible
# `nix develop` shell or optional Nix-managed tooling is wanted.
#
# Supports macOS and WSL Ubuntu. The Determinate installer auto-detects the
# platform; this wrapper adds WSL/systemd handling and an idempotent skip.
#
# Environment:
#   NIX_INSTALL_NO_CONFIRM=1   pass --no-confirm to the installer (non-interactive)
#   NIX_INSTALL_DETERMINATE=1  install Determinate Nix instead of upstream Nix

installer_url="https://install.determinate.systems/nix"

if command -v nix >/dev/null 2>&1 || [ -e /nix/var/nix/profiles/default ]; then
  echo "info: nix already appears to be installed; nothing to do" >&2
  echo "hint: to remove a Determinate install, run '/nix/nix-installer uninstall'" >&2
  exit 0
fi

missing_commands=()
for required_command in curl mktemp sh; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    missing_commands+=("$required_command")
  fi
done
if [ "${#missing_commands[@]}" -gt 0 ]; then
  echo "error: missing required command(s) for nix install: ${missing_commands[*]}" >&2
  exit 1
fi

# Build the installer arguments. `install` alone auto-detects the platform,
# but we pass an explicit planner so WSL without systemd is handled correctly.
install_args=(install)

os="$(uname -s)"
case "$os" in
  Darwin)
    install_args+=(macos)
    ;;
  Linux)
    install_args+=(linux)
    is_wsl=0
    if grep -qi microsoft /proc/version 2>/dev/null; then
      is_wsl=1
    fi
    # The Determinate installer manages the nix-daemon via systemd. When systemd
    # is not PID 1 (common on WSL without `systemd=true`), use --init none so the
    # install does not fail trying to start a systemd service.
    if [ "$(cat /proc/1/comm 2>/dev/null)" != "systemd" ]; then
      if [ "$is_wsl" -eq 1 ]; then
        echo "info: systemd is not PID 1 on WSL; installing with --init none" >&2
        echo "hint: enable 'systemd=true' in /etc/wsl.conf for a systemd-managed nix-daemon" >&2
      else
        echo "info: systemd is not PID 1; installing with --init none" >&2
      fi
      install_args+=(--init none)
    fi
    ;;
  *)
    echo "error: unsupported OS for this script: $os" >&2
    exit 1
    ;;
esac

if [ "${NIX_INSTALL_DETERMINATE:-}" = "1" ]; then
  install_args+=(--determinate)
fi

if [ "${NIX_INSTALL_NO_CONFIRM:-}" = "1" ]; then
  install_args+=(--no-confirm)
fi

installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT
curl --proto '=https' --tlsv1.2 -fsSL "$installer_url" -o "$installer"

echo "info: running Determinate Nix Installer: sh <installer> ${install_args[*]}" >&2
sh "$installer" "${install_args[@]}"

echo "info: nix installed; open a new shell so the nix profile is sourced" >&2
echo "hint: conf.d/nix.fish sources ~/.nix-profile/etc/profile.d/nix.fish automatically" >&2
