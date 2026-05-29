#!/usr/bin/env bash
set -euo pipefail

config_file="$HOME/.ssh/config"
helper_path="~/.local/bin/cloudflared-access-ssh-proxy"
helper_file="$HOME/.local/bin/cloudflared-access-ssh-proxy"

if [ ! -x "$helper_file" ]; then
  echo "warning: cloudflared-access-ssh-proxy is not executable; skipping SSH config migration" >&2
  exit 0
fi

if [ -L "$config_file" ]; then
  config_path="$(readlink -f "$config_file" || true)"
  if [ -z "$config_path" ] || [ ! -f "$config_path" ]; then
    echo "warning: SSH config symlink target is unavailable; skipping SSH config migration" >&2
    exit 0
  fi
elif [ -f "$config_file" ]; then
  config_path="$config_file"
else
  exit 0
fi

if [ ! -r "$config_path" ]; then
  echo "warning: SSH config is not readable; skipping SSH config migration" >&2
  exit 0
fi

tmp_file=""
if ! tmp_file="$(mktemp "$(dirname "$config_path")/.config.tmp.XXXXXXXXXX")"; then
  echo "warning: failed to create temporary SSH config; skipping SSH config migration" >&2
  exit 0
fi
changed=0

cleanup() {
  rm -f "$tmp_file"
}

trap cleanup EXIT INT TERM HUP

config_mode="$(stat -f %Lp "$config_path" 2>/dev/null || stat -c %a "$config_path" 2>/dev/null || true)"
if [ -n "$config_mode" ] && ! chmod "$config_mode" "$tmp_file"; then
  echo "warning: failed to copy SSH config permissions; continuing with temporary file defaults" >&2
fi

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ ^([[:space:]]*)ProxyCommand[[:space:]]+(/usr/bin/|/usr/local/bin/|/opt/homebrew/bin/)?cloudflared[[:space:]]+access[[:space:]]+(ssh|tcp)[[:space:]]+--hostname[[:space:]]+%h[[:space:]]*$ ]]; then
    printf '%sProxyCommand %s %%h\n' "${BASH_REMATCH[1]}" "$helper_path" >>"$tmp_file"
    changed=1
  else
    printf '%s\n' "$line" >>"$tmp_file"
  fi
done <"$config_path"

if [ "$changed" -eq 1 ]; then
  if mv "$tmp_file" "$config_path"; then
    trap - EXIT INT TERM HUP
  else
    echo "warning: failed to update SSH config; skipping SSH config migration" >&2
  fi
fi
