# Cross-platform window manager design

## Context

Three machines need the same window-management keys:

- Windows, the main environment. WezTerm runs on the Windows host and opens
  WSL.
- macOS, with Karabiner-Elements running the "Windows-friendly" profile
  (`dot_config/karabiner/karabiner.json`).
- A NixOS laptop that is not set up yet. Its host configuration will live in
  the private NixOS repository.

The fastest workflow today is the Windows taskbar: pinned apps reached with
`Win+1` (current game), `Win+2` (browser) and `Win+3` (WezTerm). macOS has no
equivalent. tmux runs everywhere with prefix `C-f` and `C-f C-h/j/k/l` pane
moves, and the terminal normally fills the screen.

## Goals

- One keymap on all three machines, on one modifier at the same physical
  position.
- `Mod+1..9` reaches a fixed app in one chord.
- `Mod+h/j/k/l` moves focus between windows, mirroring tmux pane moves.
- A fuzzy window picker reaches every other window.
- Each machine's configuration lives in this repository and is verified on
  that machine before merge.

## Non-goals

- Identical layout behavior on every OS. niri (scrolling columns) and the
  i3-style managers differ once a workspace holds two or more windows; see
  [Layout differences](#layout-differences).
- Prefix (modal) bindings. niri has no binding modes
  ([niri#846](https://github.com/niri-wm/niri/issues/846)), so a shared
  design uses chords.
- Launching an app when its workspace is empty. The taskbar does this;
  workspaces do not. Autostart covers the pinned apps.
- Keeping `Win+L` as the lock shortcut on Windows.
- Multi-monitor rules. Revisit once the single-display setup works. The
  Windows host has a second, portrait display: its slots 1–9 stay on the main
  display and the portrait display gets workspace 0 (`Mod+0`), on Windows only
  (`docs/window-manager-windows.md`).

## Design

### Window manager per OS

| OS | Window manager | Layout model | Reason |
|---|---|---|---|
| Windows | GlazeWM (v3.10 or later) | i3-style tree | Mature; YAML config; window rules |
| macOS | AeroSpace | i3-style tree | Mature; no SIP changes; emulated workspaces |
| NixOS laptop | niri | Scrollable columns | Suits a narrow laptop screen; `programs.niri.enable` |

GlazeWM added macOS support in
[v3.10.0](https://github.com/glzr-io/glazewm/releases/tag/v3.10.0)
(2026-03), which would let Windows and macOS share one YAML file. It is not
used on macOS yet because open issues include keybindings that stop working
after sleep and wake. Revisit when those close.

Fallbacks:

- If the layout differences are annoying when switching machines, run sway on
  the laptop instead of niri. NixOS can install both sessions and pick one at
  login.
- If the laptop becomes the main machine and niri wins, move the others to
  scrolling layouts: komorebi's Scrolling layout on Windows, OmniWM or Nehir on
  macOS (both need macOS 26 on Apple silicon).

### Modifier

`Mod` is the key two to the left of Space: `Win` on Windows, left `Option` on
macOS, `Super` on NixOS.

Karabiner swaps `fn` and left `Control`, so the Mac bottom row reads Control,
fn, Option, Command, Space, while a PC laptop reads Control, Fn, Win, Alt,
Space. Option sits where Win does, so `Win+2` and `Option+2` are the same
finger motion. `dot_config/wezterm/wezterm.lua` already treats Command and
Alt as the same position for tab keys.

Alt and Command are taken:

- On Windows, `Alt+T`, `Alt+W` and `Alt+1..9` are WezTerm tab keys.
- On macOS, `Command+1..9` are tab keys, and Karabiner rewrites
  `Ctrl+C/V/X/Z/A/S/F/Y` to `Command+…` in GUI apps. A window manager listening
  on Command would capture that output, for example `Command+F`.

Consequences:

- macOS: WezTerm sends left Option as Meta
  (`send_composed_key_when_left_alt_is_pressed = false`). Option chords bound
  by AeroSpace no longer reach tmux, Neovim or fish. The repository binds no
  Meta+h/j/k/l or Meta+digit keys. fish loses its default `Alt+H`, `Alt+L`
  and `Alt+F`. LazyVim's `Alt+J` and `Alt+K` line moves come back on
  `Command+J` and `Command+K`, which WezTerm sends as `Alt+J` and `Alt+K`:
  Command sits where Alt does on a PC keyboard, so the finger motion matches
  Windows. Karabiner emits Option only with arrows and Backspace, which stay
  unbound.
- Windows and macOS: tmux's default `C-f M-1..5` layout keys become
  unreachable, because WezTerm takes `Alt+digit` on Windows and AeroSpace takes
  `Option+digit` on macOS. Use `C-f Space` (next-layout) or bind explicit
  keys.
- Windows: hooks cannot intercept `Win+L` (GlazeWM README;
  [kanata known issues](https://github.com/jtroo/kanata/blob/main/docs/platform-known-issues.adoc)).
  Set the DWORD `DisableLockWorkstation = 1` under
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System`. This
  disables workstation locking entirely, which is accepted. The user has only
  read access to the `Policies` key, so writing it needs an elevated shell; see
  [Repository layout](#repository-layout). GlazeWM `lwin` bindings override
  the other `Win+…` shortcuts they reuse.
- Windows: releasing `Win` quickly after a GlazeWM `lwin` chord can open the
  Start menu ([glazewm#1215](https://github.com/glzr-io/glazewm/issues/1215),
  open at the time of writing; the older
  [glazewm#589](https://github.com/glzr-io/glazewm/issues/589) reports the same
  through v3.8.1). The workaround reported there is an AutoHotkey script that
  sends a mask key when `LWin` goes down, for example
  `~LWin::Send "{Blind}{vkE8}"`. That also stops a bare `Win` press from opening
  Start. On Windows 11 25H2 with GlazeWM 3.10.1 the first check passed, but
  in later use quick `Win+N` and `Win+Space` taps opened Start, and Start took
  focus from the window picker. The Windows setup therefore runs that mask
  (`dot_glzr/glazewm/win-key-mask.ahk`), started by GlazeWM.
- Windows: `Win+Space` switches input languages. GlazeWM's `lwin+space`
  binding takes it over (checked: the input language no longer changes), so
  input switching moves to `Win+Ctrl+Space`. GlazeWM passes that through,
  because a binding does not match while extra modifiers are held.
- niri: its defaults use `Mod+Shift+H/J/K/L` for monitor focus and
  `Mod+Ctrl+H/J/K/L` for moving columns. Rebind both to match the keymap.

### Keymap

| Action | Key | GlazeWM | AeroSpace | niri |
|---|---|---|---|---|
| Go to workspace N; pressing again returns | `Mod+1..9` | `focus --workspace N` with `general.toggle_workspace_on_refocus: true` | `workspace --auto-back-and-forth N` | `focus-workspace` with `input { workspace-auto-back-and-forth }` |
| Send window to N and follow it | `Mod+Shift+1..9` | `move --workspace N`, then `focus --workspace N` | `move-node-to-workspace --focus-follows-window N` | `move-column-to-workspace` |
| Focus left/down/up/right | `Mod+h/j/k/l` | `focus --direction left` (and so on) | `focus left` (and so on) | `focus-column-left`, `focus-window-down`, `focus-window-up`, `focus-column-right` |
| Move left/down/up/right | `Mod+Shift+h/j/k/l` | `move --direction left` (and so on) | `move left` (and so on) | `move-column-left`, `move-window-down`, `move-window-up`, `move-column-right` |
| Toggle fullscreen | `Mod+f` | `toggle-fullscreen` | `fullscreen` | `maximize-column` |
| Toggle floating | `Mod+Shift+Space` | `toggle-floating` | `layout floating tiling` | `toggle-window-floating` |
| Narrower / wider | `Mod+-` / `Mod+=` | `resize --width -5%` / `resize --width +5%` | `resize smart -50` / `resize smart +50` | `set-column-width "-10%"` / `set-column-width "+10%"` |
| Window picker | `Mod+Space` | [Window picker](#window-picker) | [Window picker](#window-picker) | [Window picker](#window-picker) |

niri keeps these defaults as extras: `Mod+R` cycles preset column widths,
`Mod+O` toggles the overview, and `Mod+[` / `Mod+]` move one window into or out
of the neighboring column.

The command names come from current upstream documentation. Check them against
the installed version during implementation.

### App slots

| Slot | App |
|---|---|
| 1 | Current game |
| 2 | Browser |
| 3 | WezTerm |
| 4–9 | Free, used ad hoc |

Window rules pin apps to slots. Process names and app IDs are machine facts
that each implementation plan records.

- GlazeWM: a `window_rules` entry with `commands: ['move --workspace N']`
  matching `window_process`. Games run in borderless windowed mode and get
  `commands: ['move --workspace 1', 'set-fullscreen']`, so they stay managed,
  untiled windows on workspace 1. Do not use `ignore` for them. `ignore`
  detaches the window from the workspace tree (`ignore_window.rs`), so
  `Mod+1` would focus an empty workspace, and the game would not be hidden on
  other workspaces. Use `ignore` only if a game misbehaves while managed. The
  game is then reached with `Alt+Tab`, not `Mod+1`.
- AeroSpace: an `on-window-detected` entry with
  `if = 'test %{app-bundle-id} = <id>'` and `run = 'move-node-to-workspace N'`
  (the `if.app-id` form is deprecated since 0.21.0).
- niri: declare a named workspace for every slot, 1–9, and pin apps with
  `open-on-workspace` window rules. Bind `Mod+N` to `focus-workspace "<name>"`
  and `Mod+Shift+N` to `move-column-to-workspace "<name>"`. A quoted argument
  selects by name, and a bare integer selects by index. An index means "the
  Nth workspace on the monitor right now", and it is clamped to the last
  (empty) workspace (`Monitor::switch_workspace`). Unnamed slots 4–9 would
  therefore shift as workspaces appear and disappear: `Mod+5` on a monitor
  with four workspaces lands on the fourth.

Autostart the browser and WezTerm so their slots are never empty: GlazeWM
`general.startup_commands`, AeroSpace `after-startup-command` or login items,
niri `spawn-at-startup`.

### Layout differences

One window per workspace behaves the same everywhere. Differences start at two
windows.

| Situation | i3-style (GlazeWM, AeroSpace) | niri |
|---|---|---|
| Add a window to a workspace | Existing windows shrink and the space splits | A column is added to the right; existing widths stay, so windows may scroll off-screen |
| `Mod+Shift+h` with two windows | The two swap | The two swap |
| Move next to a vertically stacked pair | The window joins the stack ([AeroSpace `move`, example 2](https://nikitabobko.github.io/AeroSpace/commands#move)) | Whole columns swap |
| Stack two windows vertically | Change the split direction | Move the window into the column (`Mod+[` / `Mod+]`) |

Working rules:

- i3-style: keep at most two windows per workspace and send extras to a free
  slot.
- niri: set `layout { default-column-width { proportion 1.0; } }` to match
  fullscreen use, and press `Mod+R` for halves when placing two windows side
  by side.

### Window picker

`Mod+Space` opens a fuzzy list of window titles. Enter focuses the selected
window and switches to its workspace. Fixed slots stay the fast path; the
picker covers everything else. Browser tabs are not windows, so use the
browser's own tab search for them.

| OS | Picker | Fallback |
|---|---|---|
| Windows | AutoHotkey list of `glazewm query workspaces`; Enter runs `glazewm command focus --workspace N` when the window's workspace is hidden, then `focus --container-id <id>` (`dot_glzr/glazewm/window-picker.ahk`) | — |
| macOS | Raycast "Switch Windows" | `aerospace list-windows --all` piped to `choose`, then `aerospace focus --window-id <id>` |
| NixOS | `niri msg --json windows` piped to `fuzzel --dmenu`, then `niri msg action focus-window --id <id>` | Overview (`Mod+O`) |

On Windows and macOS the window manager hides windows on other workspaces:
GlazeWM cloaks them, and AeroSpace moves them to a screen corner. On Windows,
PowerToys Command Palette's "Switch windows" does not list cloaked windows
unless another virtual desktop cloaked them (`OpenWindows.cs`), so Windows
lists `glazewm query workspaces` itself. On macOS, Raycast "Switch Windows"
lists windows AeroSpace moved to a corner, and selecting one switches to its
workspace (checked with AeroSpace 0.21.3 on macOS 26.7).

### Terminal at reduced width

- `Mod+f` fills the screen with the WezTerm window and keeps the layout for
  later; `C-f z` zooms one tmux pane inside it.
- `C-f Space` cycles tmux layouts; stacked panes read better at half width.
- Give the terminal the wider side (2/3), because browsers reflow better than
  terminals.
- WezTerm's default `Ctrl+-`, `Ctrl+=` and `Ctrl+0` change the font size.

### Repository layout

- macOS: `dot_config/aerospace/aerospace.toml` (AeroSpace reads
  `~/.config/aerospace/aerospace.toml`). Add `/.config/aerospace/` to the
  darwin-only block in `.chezmoiignore`.
- Windows: keep the GlazeWM config and the window picker in
  `dot_glzr/glazewm/`, ignored by chezmoi unless the OS is `windows`, and
  copy it from WSL to `%USERPROFILE%\.glzr\glazewm\config.yaml` with a
  `run_onchange_after_*` script modeled on
  `run_onchange_after_35-install-windows-wezterm-config.sh.tmpl`. Processes
  started from WSL run at medium integrity, and
  `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies` grants the user
  only `ReadKey`, so the script cannot set `DisableLockWorkstation`. Instead, it
  checks the value with `reg.exe query`. If the value is missing, it prints the
  `reg add` command to run once from an elevated terminal. The Windows note
  under `docs/` records the same step. Both steps are idempotent.
- NixOS: enable niri (`programs.niri.enable = true;`) and install fuzzel in the
  laptop's host configuration in the private NixOS repository. Keep
  `dot_config/niri/config.kdl` here and ignore it unless the target is NixOS.
  Check `.chezmoi.os` before `.chezmoi.osRelease.id`, because `osRelease` only
  exists on Linux. As with tmux, NixOS provides the binaries and dotfiles owns
  the interactive behavior.
- Each implementation adds its own user-facing note, in Japanese like
  `docs/wezterm.md`: `docs/window-manager-macos.md`,
  `docs/window-manager-windows.md` or `docs/window-manager-nixos.md`. Separate
  files keep parallel PRs from conflicting.
- `scripts/check-chezmoi-managed.sh` compares against `chezmoi managed` and
  `chezmoi ignored` on the OS it runs on. List OS-specific sources in
  `require_source`, as `dot_config/karabiner/karabiner.json` is. Add a path to
  `require_managed` or `require_ignored` only if that holds on every OS;
  otherwise the hook passes on the machine that added it and fails on the
  others.

### Rollout

1. Merge this spec to `main` as a docs-only PR.
2. On each machine, branch from `main` (`feat/wm-macos-aerospace`,
   `feat/wm-windows-glazewm`, `feat/wm-nixos-niri`) and write
   `docs/superpowers/plans/YYYY-MM-DD-wm-<os>.md` with that machine's facts:
   browser and game identifiers, keyboard layout and OS version. Then
   implement, run the [Verification](#verification) scenarios on that machine
   and open a PR.
3. macOS and Windows proceed in parallel. The laptop starts when it arrives:
   its PR cannot merge before then, and enabling niri is a separate PR in the
   private NixOS repository.
4. Windows checks the `Win` key first: Verification scenarios 8 and 9, and
   whether `Win+Space` is free, using a minimal GlazeWM config with a few
   `lwin` bindings. These are the assumptions most likely to change `Mod` or
   the picker key for every machine.
5. Shared decisions (`Mod`, the keymap, app slots, the picker key) change only
   through a small spec-only PR merged before the implementation PR, so the
   other machines pick the change up early. Corrections that affect one OS
   stay in that OS's PR.
6. `.chezmoiignore`, `scripts/check-chezmoi-managed.sh` and this spec are
   shared. Whichever PR merges second rebases on `main`, resolves the
   conflicts and reruns `prek run --all-files` on its machine.
7. The hook suite only checks the OS it runs on, so a change can pass on one
   machine and break another. After another machine's PR merges, pull `main`
   and run `prek run --all-files` and `chezmoi diff` on each machine. A broken
   `.chezmoiignore` template stops `chezmoi apply` everywhere.

## Verification

Run these scenarios on each machine before merging its PR:

1. `Mod+3` focuses WezTerm, `Mod+2` focuses the browser, and `Mod+2` again
   returns to WezTerm.
2. From the browser, `Mod+Shift+3` places it next to WezTerm with focus
   following. `Mod+Shift+h` swaps the two, `Mod+l` focuses WezTerm, and
   `Mod+Shift+2` sends the browser back.
3. `Mod+1` shows the game untiled; `Mod+2` and `Mod+1` switch while it runs.
4. `Mod+Space`, typing part of the title of a window on another workspace,
   then Enter focuses that window and its workspace.
5. `Mod+5`, then opening an app, places the app on slot 5; `Mod+3` returns to
   WezTerm.
6. `Mod+f` toggles fullscreen, and inside it `C-f z` and `C-f Space` still work.
7. Existing keys keep working: WezTerm tabs (`Alt+1..9` on Windows,
   `Command+1..9` on macOS), Karabiner's Ctrl shortcuts and word movement on
   macOS, and tmux `C-f C-h/j/k/l`.
8. Windows: `Win+L` reaches GlazeWM and does not lock the session.
9. Windows: tapping `Win+2` and releasing both keys at once switches
   workspace without opening the Start menu.
10. After sleep and wake, the bindings still respond.
