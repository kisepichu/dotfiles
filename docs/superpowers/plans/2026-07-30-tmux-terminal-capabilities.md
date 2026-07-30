# tmux Terminal Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve Neovim truecolor and forward OSC 52 clipboard writes when tmux appears anywhere between Neovim and WezTerm.

**Architecture:** Keep terminal behavior in the shared chezmoi tmux configuration. Describe direct WezTerm clients and nested tmux clients with their required RGB/clipboard capabilities, and use tmux's native clipboard relay instead of adding platform-specific clipboard commands or custom Neovim escape wrapping. Exercise the loaded configuration through an isolated tmux server and pseudo-terminal.

**Tech Stack:** tmux 3.6a+, Bash, util-linux/BSD `script`, chezmoi, prek

## Global Constraints

- Keep `default-terminal` as `screen-256color`.
- Do not enable general terminal passthrough.
- Do not modify or stage the dirty `/home/kise/repos/dotfiles` checkout.
- Apply only `.tmux.conf` on `glaceon`; do not apply the entire `origin/develop` source tree.
- Preserve existing tmux sessions and key bindings.

---

### Task 1: Relay truecolor and OSC 52 through tmux

**Files:**
- Create: `scripts/test-tmux-terminal.sh`
- Modify: `.pre-commit-config.yaml`
- Modify: `dot_tmux.conf:3-5`

**Interfaces:**
- Consumes: tmux configuration through `tmux -L <socket> -f dot_tmux.conf`.
- Produces: direct `xterm-256color` and nested `screen-256color` clients with the `RGB` feature and an OSC 52 sequence relayed from a pane to each outer pseudo-terminal.

- [ ] **Step 1: Write the failing integration test**

Create `scripts/test-tmux-terminal.sh`:

```bash
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
```

Add a local hook to `.pre-commit-config.yaml`:

```yaml
      - id: tmux-terminal-capabilities
        name: tmux terminal capabilities
        entry: scripts/test-tmux-terminal.sh
        language: system
        files: ^(dot_tmux\.conf|scripts/test-tmux-terminal\.sh)$
        pass_filenames: false
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
chmod +x scripts/test-tmux-terminal.sh
scripts/test-tmux-terminal.sh
```

Expected: FAIL with `expected set-clipboard=on, got external`.

- [ ] **Step 3: Add the minimal tmux configuration**

After the existing `default-terminal` and `terminal-overrides` lines in
`dot_tmux.conf`, add:

```tmux
set -as terminal-features ',xterm-256color:RGB,screen-256color:RGB:clipboard'
set-option -s set-clipboard on
```

- [ ] **Step 4: Run focused and repository verification**

Run:

```bash
scripts/test-tmux-terminal.sh
tmux -L tmux-config-check -f dot_tmux.conf \
  new-session -d -s config-check 'sleep 30'
tmux -L tmux-config-check source-file -n dot_tmux.conf
tmux -L tmux-config-check kill-server
prek run --all-files
```

Expected: the focused test prints
`ok - tmux preserves RGB and relays OSC 52`; tmux reports no configuration
error; every hook passes.

- [ ] **Step 5: Commit the tested behavior**

```bash
git add .pre-commit-config.yaml dot_tmux.conf scripts/test-tmux-terminal.sh
git commit --no-gpg-sign -m "fix: preserve truecolor and OSC 52 through tmux"
```

### Task 2: Apply the managed tmux file on glaceon

**Files:**
- Read: `dot_tmux.conf`
- Runtime target: `glaceon:~/.tmux.conf`

**Interfaces:**
- Consumes: the exact committed source tree from Task 1.
- Produces: the active `glaceon` tmux server with `set-clipboard=on`, `xterm-256color:RGB`, and `screen-256color:RGB:clipboard`.

- [ ] **Step 1: Transfer the committed source without local-only files**

From the isolated worktree, obtain the implementation commit and create a
tracked archive:

```bash
revision=$(git rev-parse HEAD)
archive="/tmp/dotfiles-$revision.tar"
git archive --format=tar --output="$archive" "$revision"
```

Create a new explicit build directory on `glaceon` and extract the archive:

```bash
remote_dir="/home/kise/build/dotfiles-$revision"
ssh glaceon \
  "test ! -e '$remote_dir' &&
   install -d -m 700 '$remote_dir' &&
   tar -x -C '$remote_dir'" <"$archive"
```

- [ ] **Step 2: Apply only `.tmux.conf` and reload the server**

Run from the isolated worktree:

```bash
ssh glaceon \
  "mise exec chezmoi@2.69.1 -- chezmoi \
     --source '$remote_dir' --force apply ~/.tmux.conf &&
   tmux source-file ~/.tmux.conf"
```

Do not run a whole-tree `chezmoi apply`.

- [ ] **Step 3: Verify the active options without replacing sessions**

Run:

```bash
ssh glaceon '
  tmux show-options -s set-clipboard
  tmux show-options -s terminal-features
  tmux list-sessions
'
```

Expected:

```text
set-clipboard on
terminal-features[...] xterm-256color:RGB
terminal-features[...] screen-256color:RGB:clipboard
```

The existing named sessions remain listed. Reattach the SSH client if
`#{client_termfeatures}` was computed before the configuration reload.

- [ ] **Step 4: Confirm the two user-visible paths**

In Neovim, confirm normal `yy` reaches the desktop clipboard and truecolor is
correct for:

```text
WezTerm -> WSL -> SSH -> glaceon tmux -> Neovim
WezTerm -> WSL tmux -> SSH -> glaceon tmux -> Neovim
```

### Task 3: Review and deliver the branch

**Files:**
- Review: `origin/develop...HEAD`
- Update: PR metadata only

**Interfaces:**
- Consumes: the clean, verified branch and live `glaceon` evidence.
- Produces: a focused PR against `develop`.

- [ ] **Step 1: Run fresh verification**

Run:

```bash
git status --short --branch
git diff --check origin/develop...HEAD
scripts/test-tmux-terminal.sh
prek run --all-files
```

Expected: clean worktree, no whitespace errors, focused test passes, all hooks
pass.

- [ ] **Step 2: Run the local low-cost diff review loop**

Review only `origin/develop...HEAD` with local Codex Luna at low reasoning.
Address actionable findings one at a time, rerun the focused test and hook
suite, and repeat until the reviewer reports no findings.

- [ ] **Step 3: Push and open the PR**

```bash
git push -u origin fix/tmux-truecolor-osc52
gh pr create \
  --base develop \
  --head fix/tmux-truecolor-osc52 \
  --title "fix: preserve truecolor and OSC 52 through tmux"
```

The PR body must include the isolated tmux behavioral test, repository hooks,
local Codex review result, and live `glaceon` verification. The pre-existing
dirty `fix/misc-dotfiles-fixes` checkout remains untouched.
