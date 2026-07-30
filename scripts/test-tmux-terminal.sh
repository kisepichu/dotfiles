#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config="$repo_root/dot_tmux.conf"
test_tmp=$(mktemp -d)
socket="tmux-terminal-test-$$"

cleanup() {
  tmux -L "$socket" kill-server 2>/dev/null || true
  rm -rf "$test_tmp"
}
trap cleanup EXIT

tmux -L "$socket" -f "$config" new-session -d -s config-check 'sleep 30'

clipboard_mode=$(tmux -L "$socket" show-options -sv set-clipboard)
if [[ $clipboard_mode != on ]]; then
  printf 'expected set-clipboard=on, got %s\n' "$clipboard_mode" >&2
  exit 1
fi

terminal_features=$(tmux -L "$socket" show-options -sv terminal-features)
if [[ $terminal_features != *xterm-256color:RGB* ]]; then
  printf 'xterm-256color must be declared RGB-capable\n' >&2
  exit 1
fi

feature_file="$test_tmp/features"
terminal_log="$test_tmp/terminal.log"
marker='Z2xhY2Vvbi10bXV4LW9zYzUy'

tmux -L "$socket" set-hook -g client-attached \
  'run-shell "tmux wait-for -S terminal-client-attached"'
tmux -L "$socket" new-session -d -s behavior-check \
  "tmux wait-for terminal-client-attached; tmux display-message -p '#{client_termfeatures}' > '$feature_file'; printf '\\033]52;c;$marker\\033\\\\'; sleep 1"

if script --version 2>&1 | grep -Fq 'util-linux'; then
  TERM=xterm-256color script -q -e \
    -c "tmux -L $socket attach-session -t behavior-check" \
    "$terminal_log" </dev/null >/dev/null
elif [[ $(uname -s) == Darwin ]]; then
  TERM=xterm-256color script -q "$terminal_log" \
    tmux -L "$socket" attach-session -t behavior-check \
    </dev/null >/dev/null
else
  printf 'unsupported script implementation on %s\n' "$(uname -s)" >&2
  exit 1
fi

if ! grep -Fqw RGB "$feature_file"; then
  printf 'attached xterm-256color client did not receive RGB feature\n' >&2
  exit 1
fi

if ! LC_ALL=C grep -aFq $'\033]52;c;'"$marker" "$terminal_log"; then
  printf 'tmux did not relay application OSC 52 to the outer terminal\n' >&2
  exit 1
fi

printf 'ok - tmux preserves RGB and relays OSC 52\n'
