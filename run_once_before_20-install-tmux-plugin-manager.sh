#!/usr/bin/env bash
set -euo pipefail

tpm_dir="$HOME/.tmux/plugins/tpm"

if [ -d "$tpm_dir/.git" ]; then
  exit 0
fi

if [ -e "$tpm_dir" ]; then
  echo "warning: $tpm_dir exists but is not a git repository; skipping TPM install" >&2
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "warning: git is not installed; skipping TPM install" >&2
  exit 0
fi

mkdir -p "$(dirname "$tpm_dir")"
git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
