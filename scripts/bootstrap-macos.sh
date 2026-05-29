#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "error: this script is intended for macOS" >&2
  exit 1
fi

missing_commands=()
for required_command in curl dscl grep head id ln mkdir mktemp pkgutil sed sh uname; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    missing_commands+=("$required_command")
  fi
done

if [ "${#missing_commands[@]}" -gt 0 ]; then
  echo "error: missing required command(s): ${missing_commands[*]}" >&2
  exit 1
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
expected_repo_dir="$HOME/repos/dotfiles"
mise_version="$(
  sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$repo_dir/.chezmoidata.toml" | head -n 1
)"
: "${mise_version:=v2026.4.28}"

setup_homebrew_path() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  for brew_path in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$brew_path" ]; then
      eval "$("$brew_path" shellenv)"
      return 0
    fi
  done
}

if ! pkgutil --pkg-info=com.apple.pkg.CLTools_Executables >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run 'xcode-select --install', finish the installer, then rerun this script." >&2
  exit 1
fi

setup_homebrew_path

if ! command -v brew >/dev/null 2>&1; then
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT
  curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"
  NONINTERACTIVE=1 /bin/bash "$installer"
  setup_homebrew_path
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "error: Homebrew installation did not put brew on PATH" >&2
  exit 1
fi

brew_formulae=(
  ca-certificates
  curl
  fd
  fish
  git
  jq
  pkg-config
  ripgrep
  tmux
  unzip
  xz
)

for formula in "${brew_formulae[@]}"; do
  brew list --formula "$formula" >/dev/null 2>&1 || brew install "$formula"
done

brew_casks=(
  karabiner-elements
  wezterm
)

for cask in "${brew_casks[@]}"; do
  brew list --cask "$cask" >/dev/null 2>&1 || brew install --cask "$cask"
done

fish_path="$(command -v fish || true)"
if [ -n "$fish_path" ] && ! grep -Fxq "$fish_path" /etc/shells; then
  echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
fi

current_shell="$(dscl . -read "/Users/${USER:-$(id -un)}" UserShell 2>/dev/null | sed 's/^UserShell: //' || true)"
if [ -n "$fish_path" ] && [ "$current_shell" != "$fish_path" ]; then
  if [ -t 0 ]; then
    chsh -s "$fish_path" || echo "warning: failed to change default shell to fish" >&2
  else
    echo "warning: default shell is not fish; run 'chsh -s $fish_path' manually" >&2
  fi
fi

if [ "$repo_dir" != "$expected_repo_dir" ]; then
  if [ ! -e "$expected_repo_dir" ] || [ -L "$expected_repo_dir" ]; then
    mkdir -p "$(dirname "$expected_repo_dir")"
    ln -sfn "$repo_dir" "$expected_repo_dir"
  elif [ ! -d "$expected_repo_dir" ]; then
    echo "error: chezmoi default source path exists but is not a directory: $expected_repo_dir" >&2
    exit 1
  elif [ "$(cd "$expected_repo_dir" && pwd -P)" != "$(cd "$repo_dir" && pwd -P)" ]; then
    echo "warning: chezmoi default source is $expected_repo_dir, but bootstrap is running from $repo_dir" >&2
  fi
fi

if ! command -v mise >/dev/null 2>&1; then
  installer="$(mktemp)"
  trap 'rm -f "$installer"' EXIT
  curl -fsSL https://mise.run -o "$installer"
  MISE_VERSION="$mise_version" sh "$installer"
  export PATH="$HOME/.local/bin:$PATH"
fi

mise install --quiet --yes chezmoi@2.69.1
"$repo_dir/scripts/configure-macos-defaults.sh"
mise exec --quiet chezmoi@2.69.1 -- chezmoi --source "$repo_dir" apply

echo "macOS bootstrap completed. Open Karabiner-Elements once and grant its macOS permissions."
