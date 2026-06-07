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
#   NIX_INSTALLER_NIX_BUILD_GROUP_ID=N
#       override nixbld group ID (macOS; auto-detected if unset)
#   NIX_INSTALLER_NIX_BUILD_USER_ID_BASE=N
#       override build-user UID base (macOS; auto-detected if unset)

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

# macOS: clean up leftover state from a previous failed install.
# The Determinate installer reverts on failure but may leave /etc/nix behind.
if [ "$os" = "Darwin" ] && [ -d /etc/nix ] && [ ! -d /nix/var/nix ] \
   && ! diskutil info "Nix Store" >/dev/null 2>&1; then
  echo "info: removing leftover /etc/nix from a previous failed install" >&2
  sudo rm -rf /etc/nix
fi

# macOS: ensure the /nix mount point and APFS volume exist BEFORE the installer
# runs. On managed Macs, security software (e.g., Digital Guardian) may register
# a DiskArbitration dissenter that blocks the installer's volume creation. Pre-
# creating the volume with diskutil works around this.
if [ "$os" = "Darwin" ]; then
  if [ ! -e /nix ]; then
    if ! grep -q '^nix\b' /etc/synthetic.conf 2>/dev/null; then
      echo "info: adding 'nix' entry to /etc/synthetic.conf" >&2
      printf 'nix\n' | sudo tee -a /etc/synthetic.conf >/dev/null
    fi
    sudo /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t 2>/dev/null || true
    if [ ! -e /nix ]; then
      echo "error: /nix mount point does not exist and could not be created dynamically" >&2
      echo "hint: synthetic.conf entry was added; reboot your Mac, then re-run this script" >&2
      exit 1
    fi
  fi

  if diskutil info "Nix Store" >/dev/null 2>&1; then
    if ! mount | grep -q ' on /nix '; then
      echo "info: 'Nix Store' volume exists but is not mounted at /nix; mounting" >&2
      sudo diskutil mount -mountPoint /nix "Nix Store"
    fi
  else
    root_disk="$(diskutil info / 2>/dev/null | sed -n 's/.*Part of Whole: *//p' | tr -d '[:space:]')"
    if [ -z "$root_disk" ]; then
      echo "error: could not determine root APFS container for volume creation" >&2
      exit 1
    fi
    echo "info: pre-creating 'Nix Store' APFS volume on $root_disk" >&2
    if ! sudo diskutil apfs addVolume "$root_disk" "APFS" "Nix Store" -mountpoint /nix; then
      echo "error: failed to create 'Nix Store' APFS volume" >&2
      echo "hint: security software (e.g., Digital Guardian) may be blocking disk operations" >&2
      echo "hint: try: (1) reboot and re-run, (2) contact IT to allow APFS volume creation" >&2
      exit 1
    fi
  fi
fi

# macOS: resolve GID/UID for Nix build users.
# On managed Macs (MDM / enterprise directory), the installer's default IDs may
# collide with existing directory-service entries, causing eDSRecordAlreadyExists.
# Auto-detect free IDs and pass them to the installer via its env-var interface.
if [ "$os" = "Darwin" ]; then
  nix_build_user_count=32

  find_free_gid() {
    local start="$1"
    local used
    used="$(dscl . -list /Groups PrimaryGroupID 2>/dev/null | awk '{print $NF}')"
    local gid="$start"
    while echo "$used" | grep -qw "$gid"; do
      gid=$((gid + 1))
    done
    echo "$gid"
  }

  find_free_uid_base() {
    local start="$1"
    local used
    used="$(dscl . -list /Users UniqueID 2>/dev/null | awk '{print $NF}')"
    local base="$start"
    while true; do
      local conflict=0
      local i=0
      while [ "$i" -lt "$nix_build_user_count" ]; do
        if echo "$used" | grep -qw "$((base + i))"; then
          conflict=1
          base=$((base + i + 1))
          break
        fi
        i=$((i + 1))
      done
      if [ "$conflict" -eq 0 ]; then
        echo "$base"
        return
      fi
    done
  }

  if [ -z "${NIX_INSTALLER_NIX_BUILD_GROUP_ID:-}" ]; then
    free_gid="$(find_free_gid 350)"
    export NIX_INSTALLER_NIX_BUILD_GROUP_ID="$free_gid"
    echo "info: using GID $free_gid for nixbld group (auto-detected free ID)" >&2
  fi

  if [ -z "${NIX_INSTALLER_NIX_BUILD_USER_ID_BASE:-}" ]; then
    free_uid_base="$(find_free_uid_base 350)"
    export NIX_INSTALLER_NIX_BUILD_USER_ID_BASE="$free_uid_base"
    echo "info: using UID base $free_uid_base for nixbld users (auto-detected free range)" >&2
  fi
fi

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

# macOS: work around Digital Guardian's extended attributes causing ACL errors.
# DG sets xattrs (com.dgagent.*) on files that can trigger Nix ACL errors.
# `ignored-acls` is supported by Lix but not upstream/Determinate Nix, so we
# write it to nix.custom.conf (Determinate's user-override file) and only when
# the running Nix version actually recognises the setting.
if [ "$os" = "Darwin" ] && pgrep -qf dgdaemon >/dev/null 2>&1; then
  nix_custom="/etc/nix/nix.custom.conf"
  dg_acls="com.dgagent.entity com.dgagent.filedet com.dgagent.policyid com.dgagent.ruleid com.dgagent.tagname com.dgagent.xattrsize"
  if /nix/var/nix/profiles/default/bin/nix show-config --json 2>/dev/null | grep -q '"ignored-acls"'; then
    if ! grep -q 'ignored-acls' "$nix_custom" 2>/dev/null; then
      echo "info: Digital Guardian detected; adding ignored-acls to $nix_custom" >&2
      printf 'ignored-acls = %s\n' "$dg_acls" | sudo tee -a "$nix_custom" >/dev/null
    fi
  else
    echo "info: Digital Guardian detected but this Nix version does not support ignored-acls" >&2
    echo "hint: if you see ACL errors during nix build, consider switching to Lix or stripping xattrs manually" >&2
  fi
fi

echo "info: nix installed; open a new shell so the nix profile is sourced" >&2
echo "hint: conf.d/nix.fish sources nix-daemon.fish automatically" >&2
