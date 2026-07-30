#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config="$repo_root/dot_tmux.conf"
test_tmp=$(mktemp -d)
socket="tmux-terminal-test-$$"
outer_socket="$socket-outer"
inner_socket="$socket-inner"

cleanup() {
  for test_socket in "$socket" "$outer_socket" "$inner_socket"; do
    tmux -L "$test_socket" kill-server 2>/dev/null || true
  done
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

record_session() {
  local client_term=$1
  local target_socket=$2
  local target_session=$3
  local terminal_log=$4

  if script --version 2>&1 | grep -Fq 'util-linux'; then
    TERM="$client_term" script -q -e \
      -c "tmux -L $target_socket attach-session -t $target_session" \
      "$terminal_log" </dev/null >/dev/null
  elif [[ $(uname -s) == Darwin ]]; then
    TERM="$client_term" script -q "$terminal_log" \
      tmux -L "$target_socket" attach-session -t "$target_session" \
      </dev/null >/dev/null
  else
    printf 'unsupported script implementation on %s\n' "$(uname -s)" >&2
    exit 1
  fi
}

check_client() {
  local client_term=$1
  local label=$2
  local feature_file="$test_tmp/features-$label"
  local terminal_log="$test_tmp/terminal-$label.log"
  local marker='Z2xhY2Vvbi10bXV4LW9zYzUy'
  local wait_channel="terminal-client-attached-$label"

  tmux -L "$socket" set-hook -g client-attached \
    "run-shell \"tmux wait-for -S $wait_channel\""
  tmux -L "$socket" new-session -d -s "behavior-$label" \
    "tmux wait-for $wait_channel; tmux display-message -p '#{client_termfeatures}' > '$feature_file'; printf '\\033]52;c;$marker\\033\\\\'; sleep 1"

  record_session "$client_term" "$socket" "behavior-$label" "$terminal_log"

  if ! grep -Fqw RGB "$feature_file"; then
    printf 'attached %s client did not receive RGB feature\n' "$client_term" >&2
    exit 1
  fi

  if ! LC_ALL=C grep -aFq $'\033]52;c;'"$marker" "$terminal_log"; then
    printf 'tmux did not relay application OSC 52 through %s\n' "$client_term" >&2
    exit 1
  fi
}

check_nested() {
  local feature_file="$test_tmp/features-nested"
  local terminal_log="$test_tmp/terminal-nested.log"
  local marker='Z2xhY2Vvbi10bXV4LW9zYzUy'

  tmux -L "$inner_socket" -f "$config" new-session -d -s inner-behavior \
    "tmux -L $inner_socket wait-for inner-client-attached; tmux -L $inner_socket display-message -p '#{client_termfeatures}' > '$feature_file'; printf '\\033]52;c;$marker\\033\\\\'; sleep 1"
  tmux -L "$inner_socket" set-hook -g client-attached \
    "run-shell \"tmux -L $inner_socket wait-for -S inner-client-attached\""

  tmux -L "$outer_socket" -f "$config" new-session -d -s outer-behavior \
    "tmux -L $outer_socket wait-for outer-client-attached; TERM=screen-256color tmux -L $inner_socket attach-session -t inner-behavior"
  tmux -L "$outer_socket" set-hook -g client-attached \
    "run-shell \"tmux -L $outer_socket wait-for -S outer-client-attached\""

  record_session xterm-256color "$outer_socket" outer-behavior "$terminal_log"

  if ! grep -Fqw RGB "$feature_file"; then
    printf 'inner tmux did not classify the outer tmux client as RGB\n' >&2
    exit 1
  fi

  if ! LC_ALL=C grep -aFq $'\033]52;c;'"$marker" "$terminal_log"; then
    printf 'OSC 52 did not traverse both tmux servers\n' >&2
    exit 1
  fi
}

check_client xterm-256color direct
check_nested

printf 'ok - tmux preserves RGB and relays OSC 52\n'
