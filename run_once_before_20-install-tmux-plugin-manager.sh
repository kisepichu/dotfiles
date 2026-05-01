#!/usr/bin/env bash
set -euo pipefail

tpm_dir="$HOME/.tmux/plugins/tpm"

if [ -d "$tpm_dir/.git" ]; then
  exit 0
fi

mkdir -p "$(dirname "$tpm_dir")"
git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
