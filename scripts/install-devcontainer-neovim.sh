#!/usr/bin/env bash
# Install Neovim and this repository's Neovim config inside a dev container.
#
# The Dev Container CLI clones this repository into the container and runs
# this script (see dot_config/fish/functions/dcup.fish):
#
#   devcontainer up --workspace-folder . \
#     --dotfiles-repository https://github.com/kisepichu/dotfiles.git \
#     --dotfiles-install-command scripts/install-devcontainer-neovim.sh
#
# Supports apt-based (Debian/Ubuntu) glibc images, as root or with sudo.
# Safe to run twice.
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bin_dir=/usr/local/bin
nvim_config="$HOME/.config/nvim"

if [ "$(id -u)" -eq 0 ]; then
  as_root=()
elif command -v sudo >/dev/null 2>&1; then
  as_root=(sudo)
else
  echo "error: run as root or install sudo" >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "error: only apt-based (Debian/Ubuntu) images are supported" >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64 | amd64)
    nvim_arch=x86_64
    tree_sitter_arch=x64
    deno_arch=x86_64
    ;;
  aarch64 | arm64)
    nvim_arch=arm64
    tree_sitter_arch=arm64
    deno_arch=aarch64
    ;;
  *)
    echo "error: unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

chezmoi_version=$(sed -n 's/^chezmoi[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$repo_dir/mise.toml" | head -n 1)
if [ -z "$chezmoi_version" ]; then
  echo "error: missing the chezmoi pin in $repo_dir/mise.toml" >&2
  exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

latest_release_asset() {
  printf 'https://github.com/%s/releases/latest/download/%s' "$1" "$2"
}

echo "==> apt packages"
"${as_root[@]}" apt-get update
# gcc/make: tree-sitter parsers and telescope-fzf-native. skkdic: skkeleton.
"${as_root[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl git unzip gcc make libc6-dev ripgrep fd-find skkdic
# Debian/Ubuntu name the fd binary fdfind.
if ! command -v fd >/dev/null 2>&1; then
  "${as_root[@]}" ln -sf "$(command -v fdfind)" "$bin_dir/fd"
fi

echo "==> Neovim"
# Distribution packages lag behind what LazyVim requires.
curl -fsSL "$(latest_release_asset neovim/neovim "nvim-linux-${nvim_arch}.tar.gz")" -o "$tmp_dir/nvim.tar.gz"
"${as_root[@]}" rm -rf "/opt/nvim-linux-${nvim_arch}"
"${as_root[@]}" tar -xzf "$tmp_dir/nvim.tar.gz" -C /opt
"${as_root[@]}" ln -sf "/opt/nvim-linux-${nvim_arch}/bin/nvim" "$bin_dir/nvim"

echo "==> tree-sitter CLI"
# nvim-treesitter (main branch) builds parsers with it.
curl -fsSL "$(latest_release_asset tree-sitter/tree-sitter "tree-sitter-linux-${tree_sitter_arch}.gz")" | gunzip >"$tmp_dir/tree-sitter"
"${as_root[@]}" install -m 0755 "$tmp_dir/tree-sitter" "$bin_dir/tree-sitter"

echo "==> Deno"
# denops (skkeleton, ddc) runs on Deno.
curl -fsSL "$(latest_release_asset denoland/deno "deno-${deno_arch}-unknown-linux-gnu.zip")" -o "$tmp_dir/deno.zip"
unzip -o -q "$tmp_dir/deno.zip" -d "$tmp_dir"
"${as_root[@]}" install -m 0755 "$tmp_dir/deno" "$bin_dir/deno"

echo "==> chezmoi ${chezmoi_version}"
curl -fsSL https://get.chezmoi.io -o "$tmp_dir/install-chezmoi.sh"
"${as_root[@]}" sh "$tmp_dir/install-chezmoi.sh" -b "$bin_dir" -t "v${chezmoi_version}"

apply_nvim_config() {
  # Apply only the Neovim config; never run the source's run_ scripts here.
  chezmoi --source "$repo_dir" --destination "$HOME" apply --force --exclude=scripts "$@"
}

echo "==> Neovim config"
# Applying only this subtree does not create ~/.config, which images that move
# XDG_CONFIG_HOME elsewhere do not have.
mkdir -p "$(dirname "$nvim_config")"
apply_nvim_config "$nvim_config"

# Some images move XDG_CONFIG_HOME away from ~/.config, where chezmoi puts the
# config, so point Neovim's config path at it.
xdg_nvim_config="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
if [ "$xdg_nvim_config" != "$nvim_config" ]; then
  if [ -L "$xdg_nvim_config" ] || [ ! -e "$xdg_nvim_config" ]; then
    mkdir -p "$(dirname "$xdg_nvim_config")"
    ln -sfn "$nvim_config" "$xdg_nvim_config"
  else
    echo "warning: $xdg_nvim_config already exists; Neovim will not load $nvim_config" >&2
  fi
fi

echo "==> Neovim plugins"
# A first start installs every plugin at its latest commit and rewrites
# lazy-lock.json with those commits, so restoring in the same run is a no-op.
# Put the lockfile back and restore in a second run to land on the locked commits.
nvim --headless +qa
apply_nvim_config "$nvim_config/lazy-lock.json"
nvim --headless "+Lazy! restore" +qa

echo "Neovim is ready in the dev container."
