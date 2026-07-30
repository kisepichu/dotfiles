#!/usr/bin/env bash
set -euo pipefail

mise_config="dot_config/mise/config.toml"

if ! grep -Fxq '"npm:pnpm" = "latest"' "$mise_config"; then
  echo 'mise must install pnpm explicitly through the npm backend' >&2
  exit 1
fi

if grep -Eq '^[[:space:]]*pnpm[[:space:]]*=' "$mise_config"; then
  echo 'bare pnpm tool entry may select the incompatible aqua backend' >&2
  exit 1
fi
