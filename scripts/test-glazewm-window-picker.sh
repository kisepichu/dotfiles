#!/usr/bin/env bash
# Runs the GlazeWM window picker's helper tests (JSON parsing, window list,
# fuzzy filter) under the Windows host's AutoHotkey v2. AutoHotkey exists only
# on the Windows host, so other machines skip.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if ! grep -qi microsoft /proc/version 2>/dev/null || ! command -v reg.exe >/dev/null 2>&1; then
  echo "skip - not WSL; the window picker runs on the Windows host"
  exit 0
fi

# The installer records its directory under HKCU (per-user) or HKLM.
install_dir=""
for key in 'HKCU\Software\AutoHotkey' 'HKLM\Software\AutoHotkey'; do
  install_dir=$(reg.exe query "$key" /v InstallDir </dev/null 2>/dev/null |
    sed -n 's/^ *InstallDir *REG_SZ *//p' | tr -d '\r' || true)
  [ -n "$install_dir" ] && break
done
ahk="${install_dir:+$(wslpath "$install_dir")/v2/AutoHotkey64.exe}"
if [ -z "$ahk" ] || [ ! -f "$ahk" ]; then
  echo "skip - AutoHotkey v2 is not installed on the Windows host"
  exit 0
fi

# AutoHotkey64.exe is a GUI program; piping keeps its stdout attached.
"$ahk" /ErrorStdOut "$(wslpath -w "$repo_root/scripts/test-glazewm-window-picker.ahk")" </dev/null | cat
