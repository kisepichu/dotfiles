# tmux truecolor and OSC 52 design

## Context

Neovim on `glaceon` behaves differently depending on whether tmux is in the
terminal path:

- `WezTerm -> WSL -> SSH -> Neovim` preserves truecolor and OSC 52 clipboard
  writes.
- Adding tmux on either side of SSH can prevent OSC 52 clipboard writes from
  reaching WezTerm.
- Direct SSH into the existing `glaceon` tmux reports no `RGB` client feature,
  so Neovim truecolor output is downgraded.

The existing Neovim configuration already selects
`vim.ui.clipboard.osc52` under SSH. A raw OSC 52 sequence sent without tmux
reaches the desktop clipboard. An isolated tmux 3.6a test shows that the
default `set-clipboard=external` suppresses an application-originated OSC 52
sequence, while `set-clipboard=on` forwards it.

## Goals

- Preserve Neovim truecolor over SSH when tmux is present.
- Forward Neovim OSC 52 clipboard writes through one or more tmux layers.
- Keep the shared behavior in the public chezmoi-managed tmux configuration.
- Preserve existing tmux sessions and key bindings.

## Non-goals

- Clipboard reads from the desktop into remote Neovim.
- Replacing `screen-256color` with a terminfo entry that may be unavailable on
  older macOS installations.
- Adding OS-specific clipboard commands or SSH reverse tunnels.

## Design

Keep `default-terminal` as `screen-256color` for compatibility. Extend tmux's
description of an outer `xterm-256color` client with the `RGB` feature so tmux
does not quantize 24-bit color output. Mark `screen-256color` clients with
`RGB` and `clipboard` so a tmux nested inside another tmux preserves both
truecolor and OSC 52.

Set the server `set-clipboard` option to `on`. This makes tmux accept a plain
OSC 52 write from applications in a pane and emit the corresponding clipboard
sequence to the outer terminal. Each tmux layer can therefore relay the same
operation without custom Neovim DCS wrapping.

`set-clipboard=on` also permits pane applications to create tmux paste buffers
when they issue OSC 52 writes. This is an intentional trade-off: processes
running as the same user can already write terminal output and inspect tmux
state, and native tmux handling is narrower and more reliable than enabling
general terminal passthrough.

The change belongs in `dot_tmux.conf`; NixOS continues to provide the tmux
binary, while dotfiles owns interactive terminal behavior.

## Verification

Add a shell integration test that starts an isolated tmux server with
`dot_tmux.conf` and attaches both `xterm-256color` and `screen-256color`
pseudo-terminals. It verifies:

1. the attached client is classified with the `RGB` feature;
2. an application-originated OSC 52 marker is present in the outer terminal
   byte stream;
3. the test server and temporary files are removed on exit.

Run the repository hook suite and tmux config syntax check. On `glaceon`, apply
only the managed `.tmux.conf`, reload it into the existing server, and confirm
the active server reports `RGB` and `set-clipboard=on`. Final visual and
clipboard confirmation uses:

- direct WSL SSH into `glaceon` tmux and Neovim;
- local WSL tmux followed by SSH into `glaceon`, with and without remote tmux.

## Delivery

Implement on `fix/tmux-truecolor-osc52`, based on `origin/develop`, and open a
separate PR against `develop`. Do not modify or stage the existing dirty
`fix/misc-dotfiles-fixes` checkout.
