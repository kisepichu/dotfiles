#!/usr/bin/env bash
set -euo pipefail

mise_config="dot_config/mise/config.toml"
repo_mise_toml="mise.toml"

if ! grep -Fxq '"npm:pnpm" = "latest"' "$mise_config"; then
  echo 'mise must install pnpm explicitly through the npm backend' >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*pnpm[[:space:]]*=' "$mise_config"; then
  echo 'bare pnpm tool entry may select the incompatible aqua backend' >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*codex[[:space:]]*=' "$mise_config"; then
  echo 'mise must install codex (aqua backend) so every machine gets the Codex CLI' >&2
  exit 1
fi

if [ ! -f "$repo_mise_toml" ]; then
  echo 'repo mise.toml is required so bootstrap can activate chezmoi without mise use' >&2
  exit 1
fi

if ! grep -Eq '^[[:space:]]*chezmoi[[:space:]]*=[[:space:]]*"2\.69\.1"' "$repo_mise_toml"; then
  echo 'repo mise.toml must pin chezmoi = "2.69.1" for bootstrap' >&2
  exit 1
fi

for bootstrap in scripts/bootstrap-wsl-ubuntu.sh scripts/bootstrap-nixos.sh scripts/bootstrap-macos.sh; do
  if grep -Eq 'mise[[:space:]]+(install|exec).*chezmoi@' "$bootstrap"; then
    echo "$bootstrap must install/exec chezmoi from mise.toml (no CLI @version)" >&2
    exit 1
  fi
  if ! grep -Eq 'mise[[:space:]]+install.*[[:space:]]chezmoi([[:space:]]|$)' "$bootstrap"; then
    echo "$bootstrap must run: mise install ... chezmoi" >&2
    exit 1
  fi
done
