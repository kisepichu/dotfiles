#!/usr/bin/env bash
# Copy-mode behaviour of dot_tmux.conf, driven through an attached client:
#   * `y` copies UTF-8 text, leaves copy mode, and reaches the outer terminal
#     as OSC 52 without piping to an external clipboard command (clip.exe on
#     WSL decodes UTF-8 as the ANSI code page and garbles non-ASCII text).
#   * vim-like text objects after `v` (viw, viW, vi", va(, ...).
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
config="$repo_root/dot_tmux.conf"
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/tmux-copy-mode-test.XXXXXX")
socket="tmux-copy-mode-test-$$"
terminal_log="$test_tmp/terminal.log"

cleanup() {
  tmux -L "$socket" kill-server 2>/dev/null || true
  wait 2>/dev/null || true
  rm -rf "$test_tmp"
}
trap cleanup EXIT

# tpm reads the plugin list from ~/.tmux.conf, not from `-f`, so give the test
# server a HOME whose .tmux.conf is this repository's config. Reuse installed
# plugins when present; resurrect/continuum then only see this empty HOME.
mkdir -p "$test_tmp/home/.tmux"
ln -s "$config" "$test_tmp/home/.tmux.conf"
if [[ -d $HOME/.tmux/plugins ]]; then
  ln -s "$HOME/.tmux/plugins" "$test_tmp/home/.tmux/plugins"
fi

# Fake clipboard commands that record any invocation. They shadow the real
# ones so plugins detecting them at load time would pick these up.
mkdir -p "$test_tmp/bin"
for fake in clip.exe pbcopy xclip xsel wl-copy; do
  printf '#!/bin/sh\ncat >/dev/null\necho %s >>"%s"\n' "$fake" "$test_tmp/external-copy.log" >"$test_tmp/bin/$fake"
  chmod +x "$test_tmp/bin/$fake"
done

line='foo bar-baz.qux say "hi there" call(a, b) [x y] {k v} <t a> done'
printf '%s\n' "$line" >"$test_tmp/content"

HOME="$test_tmp/home" PATH="$test_tmp/bin:$PATH" tmux -L "$socket" -f "$config" \
  new-session -d -s copy-check -x 120 -y 10 "cat '$test_tmp/content'; sleep 600"

# Flush the terminal log on every write (-f / -F) so OSC 52 can be checked
# while the client is still attached.
if script --version 2>&1 | grep -Fq 'util-linux'; then
  TERM=xterm-256color script -q -e -f -c "tmux -L $socket attach-session -t copy-check" \
    "$terminal_log" </dev/null >/dev/null &
elif [[ $(uname -s) == Darwin ]]; then
  TERM=xterm-256color script -q -F "$terminal_log" \
    tmux -L "$socket" attach-session -t copy-check </dev/null >/dev/null &
else
  printf 'unsupported script implementation on %s\n' "$(uname -s)" >&2
  exit 1
fi

client=
for _ in $(seq 50); do
  client=$(tmux -L "$socket" list-clients -F '#{client_name}' 2>/dev/null | sed -n 1p)
  [[ -n $client && $(tmux -L "$socket" capture-pane -p -t copy-check | sed -n 1p) == "$line" ]] && break
  sleep 0.1
done
if [[ -z $client ]]; then
  printf 'tmux client did not attach\n' >&2
  exit 1
fi

failures=0

# select_at <column> <keys...>: put the copy-mode cursor on <column> (0-based)
# of the first line, type <keys> then `y` as the attached client, and print the
# copied buffer.
select_at() {
  local column=$1
  shift
  tmux -L "$socket" delete-buffer 2>/dev/null || true
  tmux -L "$socket" copy-mode -t copy-check
  tmux -L "$socket" send -t copy-check -X top-line
  tmux -L "$socket" send -t copy-check -X start-of-line
  if ((column > 0)); then
    tmux -L "$socket" send -t copy-check -N "$column" -X cursor-right
  fi
  local key
  for key in "$@" y; do
    tmux -L "$socket" send-keys -c "$client" -K "$key"
  done
  sleep 0.2
  tmux -L "$socket" show-buffer 2>/dev/null || true
}

expect() {
  local name=$1 want=$2 got=$3
  if [[ $got != "$want" ]]; then
    printf 'FAIL %s: want [%s] got [%s]\n' "$name" "$want" "$got" >&2
    failures=$((failures + 1))
  fi
}

col() { # 0-based column of the first occurrence of $1 in $line, plus $2
  local prefix=${line%%"$1"*}
  echo $((${#prefix} + ${2:-0}))
}

expect viw 'bar' "$(select_at "$(col bar 1)" v i w)"
expect viW 'bar-baz.qux' "$(select_at "$(col baz 1)" v i W)"
expect 'vi"' 'hi there' "$(select_at "$(col there)" v i '"')"
expect 'va"' '"hi there"' "$(select_at "$(col there)" v a '"')"
expect 'vi(' 'a, b' "$(select_at "$(col 'a, b')" v i '(')"
expect 'va)' '(a, b)' "$(select_at "$(col 'a, b')" v a ')')"
expect 'vib' 'a, b' "$(select_at "$(col ' b)')" v i b)"
expect 'vi[' 'x y' "$(select_at "$(col 'y]')" v i '[')"
expect 'va{' '{k v}' "$(select_at "$(col 'v}')" v a '{')"
expect 'vi<' 't a' "$(select_at "$(col 't a')" v i '<')"

if [[ $(tmux -L "$socket" display -p -t copy-check '#{pane_in_mode}') != 0 ]]; then
  printf 'FAIL y must leave copy mode\n' >&2
  failures=$((failures + 1))
fi

# UTF-8 round trip through `y` up to the outer terminal's OSC 52.
utf8_text='文字化けの例見せる'
printf '%s\n' "$utf8_text" >"$test_tmp/content"
tmux -L "$socket" respawn-pane -k -t copy-check "cat '$test_tmp/content'; sleep 600"
for _ in $(seq 50); do
  [[ $(tmux -L "$socket" capture-pane -p -t copy-check | sed -n 1p) == "$utf8_text" ]] && break
  sleep 0.1
done
expect 'utf-8 y' "$utf8_text" "$(select_at 0 v i W)"

osc52_payload=$(printf '%s' "$utf8_text" | base64 | tr -d '\n')
# tmux sends ESC ] 52 ; <selection, possibly empty> ; <base64>.
if ! LC_ALL=C grep -aoE $'\033\\]52;[^;]*;[A-Za-z0-9+/=]*' "$terminal_log" | sed 's/.*;//' | grep -Fx "$osc52_payload" >/dev/null; then
  printf 'FAIL y did not send the UTF-8 selection to the terminal via OSC 52\n' >&2
  failures=$((failures + 1))
fi

if [[ -s $test_tmp/external-copy.log ]]; then
  printf 'FAIL copy mode piped to external clipboard command: %s\n' "$(sort -u "$test_tmp/external-copy.log" | tr '\n' ' ')" >&2
  failures=$((failures + 1))
fi

if ((failures > 0)); then
  exit 1
fi
printf 'ok - tmux copy mode yanks UTF-8 via OSC 52 and supports text objects\n'
