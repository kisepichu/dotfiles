# macOS Initial Setup

This is the first-pass macOS setup path for a Windows/WSL-first workflow. It keeps the existing WSL bootstrap separate and only uses macOS-specific scripts on Darwin.

## References

- Apple documents that Windows keyboards map Alt to Option and Ctrl or the Windows logo key to Command in macOS shortcuts: https://support.apple.com/en-gb/102650
- Karabiner-Elements requires manual macOS permissions for background services, Accessibility, Input Monitoring, and its driver extension: https://karabiner-elements.pqrs.org/docs/getting-started/installation/
- `rux616/karabiner-windows-mode` is a ready-made Karabiner rule project for Linux/Windows-friendly macOS behavior: https://github.com/rux616/karabiner-windows-mode
- XDA's Windows-to-Mac migration advice also points at Karabiner-Elements for making Windows shortcut muscle memory work on macOS: https://www.xda-developers.com/4-things-windows-users-can-do-to-make-using-a-mac-more-tolerable/

## First Run

1. Install Xcode Command Line Tools.

   ```bash
   xcode-select --install
   ```

2. Clone the repository.

   ```bash
   mkdir -p ~/repos
   git clone https://github.com/kisepichu/dotfiles.git ~/repos/dotfiles
   cd ~/repos/dotfiles
   ```

3. Run the macOS bootstrap.

   ```bash
   ./scripts/bootstrap-macos.sh
   ```

The script installs Homebrew when missing, installs base CLI packages, installs Karabiner-Elements and WezTerm, installs the pinned mise bootstrap version, applies this chezmoi source, and applies conservative macOS defaults.

## Keyboard Policy

The managed Karabiner profile is intentionally conservative.

- `fn` becomes `Control`, and physical left `Control` becomes `fn`, so the lower-left MacBook key keeps terminal and editor control chords available.
- `Caps Lock` becomes `Right Arrow` for local navigation muscle memory.
- `Home` and `End` move to the beginning and end of the current line, including shifted selection.
- `Ctrl+Left`, `Ctrl+Right`, `Ctrl+Backspace`, and `Ctrl+Delete` map to macOS word movement and word delete.
- Common `Ctrl` app shortcuts map to `Command` in GUI apps, but terminal-like apps and code editors are excluded so shell signals and integrated terminals keep normal control behavior.

The parts that should stay Mac-like:

- Do not globally swap `Control` and `Command` by default. It makes browser shortcuts feel closer to Windows, but breaks shell muscle memory such as `Ctrl+C`, `Ctrl+D`, `Ctrl+R`, and terminal readline bindings.
- Karabiner-Elements cannot be fully enabled non-interactively because macOS requires explicit user consent for permissions.
- Some applications need their own keymap. Editors such as VS Code and Cursor are excluded from the global `Ctrl` shortcut mapping to avoid breaking integrated terminals.

## Manual Steps After Bootstrap

1. Open Karabiner-Elements.
2. Follow its prompts in System Settings and allow:
   - background services
   - Accessibility
   - Input Monitoring
   - Driver Extension
3. Confirm the selected profile is `Windows-friendly`.
4. Log out and back in if key repeat, shell, or permission changes do not apply immediately.

## Validation

```bash
chezmoi --source ~/repos/dotfiles managed | grep -F .config/karabiner/karabiner.json
fish -n ~/.config/fish/config.fish
tmux -f ~/.tmux.conf start-server \; source-file -n ~/.tmux.conf
```

This macOS path is not a replacement for the WSL bootstrap. WSL remains supported through `scripts/bootstrap-wsl-ubuntu.sh`.
