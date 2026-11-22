# Windows Window Manager (GlazeWM) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Windows host the shared window-manager keymap from `docs/superpowers/specs/2026-11-21-window-manager-design.md` with GlazeWM, deployed from this repository and verified on the machine.

**Architecture:** The GlazeWM config and an AutoHotkey v2 window picker live in `dot_glzr/glazewm/`, ignored by chezmoi except on native Windows. From WSL, `run_onchange_after_36-install-windows-glazewm-config.sh.tmpl` copies them to `%USERPROFILE%\.glzr\glazewm\`, reloads GlazeWM, and prints the elevated `reg add` that frees `Win+L` when it is missing. The picker's JSON parsing, window collection and fuzzy filter sit in a GUI-free library that a hook test runs under the host's AutoHotkey.

**Tech Stack:** GlazeWM 3.10.1, AutoHotkey 2.0.31, Bash, chezmoi 2.69.1, prek 0.3.11

## Machine Facts

Recorded 2026-11-21 and 2026-11-22 from WSL on the Windows host.

| Item | Value |
|---|---|
| OS | Windows 11 Education 25H2, build 26200.9711, x64 |
| Keyboard | US 101 (`PCAT_101KEY`, `kbd101.dll`); input languages en-US and ja (Microsoft IME) |
| Displays | `\\.\DISPLAY2` 2560×1440 at (0,0), primary; `\\.\DISPLAY3` 1080×1920 portrait at (-1080,-278). GlazeWM sorts monitors left to right (`sort_monitors.rs`): portrait = index 0, main = index 1 |
| GlazeWM | 3.10.1, `C:\Program Files\glzr.io\GlazeWM\`, CLI `cli\glazewm.exe`; installed with `winget install --id glzr-io.glazewm --exact --override "/quiet /norestart Custom_InstallZebar=0"` (per-machine, one UAC prompt, no Zebar) |
| AutoHotkey | 2.0.31, `C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` (`winget install --id AutoHotkey.AutoHotkey --exact --scope user` updated the existing machine install) |
| WezTerm | 20230712-072601-f4abf8fd, process `wezterm-gui`, class `org.wezfurlong.wezterm`, `C:\Program Files\WezTerm\wezterm-gui.exe` |
| Browser (slot 2) | Brave, process `brave`, class `Chrome_WidgetWin_1`, `C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe`. The pinned PWA "Discord (2)" also runs as `brave` |
| Games (slot 1) | VRChat (process `VRChat`, class `UnityWndClass`, GlazeWM starts it floating), Overwatch (`Overwatch`), Street Fighter 6 (`StreetFighter6`); the last two are the executables in their Steam install directories |
| PowerToys | 0.99.0 (Preview). Command Palette 0.10.11163.0 on `Win+Alt+Space`. Keyboard Manager maps RCtrl+H/J/K/L to arrows (no `Win` keys). FancyZones was enabled |
| Other WMs | `komorebi.lnk` (`komorebic-no-console.exe start`) in the Startup folder; komorebi not running |
| `Win+L` | `DisableLockWorkstation = 1` set from an elevated terminal on 2026-11-21 |

## Rollout 4 Results (Win key)

Checked with a throwaway GlazeWM config (`lwin+1..4`, `lwin+h/l`, `lwin+space` → Notepad):

- Scenario 9: tapping `Win+2` and releasing both keys at once switches workspace every time and never leaves Start open. Mashing the keys can flash Start for a moment; it closes by itself. No AutoHotkey mask key was added at this point (reversed later; see Findings).
- Scenario 8: with `DisableLockWorkstation = 1`, `Win+L` reaches GlazeWM (`focus --direction right`) and does not lock.
- `Win+Space`: GlazeWM's binding takes it; the input language does not change. The user switches languages with `Win+Ctrl+Space` instead, which GlazeWM passes through because a binding with extra modifiers does not match (`keybinding_listener.rs`).
- Shared decisions stay as they are: `Mod` = `Win`, picker on `Mod+Space`.

Picker check: Command Palette's "Switch windows" does not list windows on hidden workspaces (TotalMix and ALCOM on a hidden workspace were missing). GlazeWM cloaks them with `DWMWA_CLOAKED = 2`, and the Window Walker drops cloaked windows unless another virtual desktop cloaked them (`OpenWindows.cs`, `VirtualDesktopHelper.cs`). So Windows uses the spec's fallback with its own list UI. (`glazewm command focus --container-id <id>` was first thought to show a hidden window's workspace; that check only read GlazeWM's state. See Findings.)

Other checked behavior:

- `shell-exec` rejects a double-quoted program path in 3.10.1 (`command doesn't have an ending "`, `parse_command` looks for a third quote). Unquoted program paths with spaces work because GlazeWM grows the path one word at a time until it names a file. Arguments may be quoted.
- GlazeWM floats WezTerm: `window_decorations = "RESIZE"` leaves out `WS_THICKFRAME`, and `window_state_to_create` floats windows that cannot be resized.
- GlazeWM does not manage `WS_EX_TOOLWINDOW` windows (`check_is_manageable`), so a `+ToolWindow` AutoHotkey GUI needs no window rule.
- Window rules default to `on: [manage, title_change]` with `run_once: true`: each window is moved once, and `Mod+Shift+N` moves it freely afterwards.

## Findings During Implementation

- The Rollout 4 GlazeWM stopped answering IPC after the user turned the displays off and on (`display off.ps1`, `SC_MONITORPOWER`). The main display dropped off as a device, so GlazeWM moved workspaces 2–4 to the portrait display (`remove_monitor`); when the main display came back, `add_monitor` found no free workspace config in the 4-workspace throwaway config and logged `No workspace config available to activate workspace` with "Non fatal error" dialogs. The real config binds 1–9 to the main display, so `move_bounded_workspaces_to_new_monitor` returns them on wake; scenario 10 covers display off/on.
- `glazewm.exe` has `uiAccess="true"` in its manifest, so normal-integrity shells (WSL included) cannot `taskkill` it. Exit with the tray menu or `glazewm command wm-exit`; a hung instance needs an elevated `taskkill /F /IM glazewm.exe /IM glazewm-watcher.exe`.
- After the forced kill, `glazewm-watcher.exe` kept the IPC listener (127.0.0.1:6123) open, and the next start failed with `os error 10048`. That half-started instance had already cloaked windows on non-displayed workspaces and left them cloaked. GlazeWM ignores cloaked windows (`is_visible`), so they were uncloaked with a throwaway `IApplicationView::SetCloak(1, 0)` script; GlazeWM then managed them through `EVENT_OBJECT_UNCLOAKED`.
- The `glazewm` CLI waits for the WM without a deadline when GlazeWM is not running, which hung the first deploy. The install script now checks `tasklist.exe` first and bounds the reload with `timeout 10`.
- Picker latency: the Task 3 version took 516–797 ms to show its window (`glazewm query workspaces` through `cmd.exe` 560–875 ms, of which the CLI itself is about 220–280 ms; JSON parsing 30–50 ms; `Show` about 110 ms; `WinActivate` about 110 ms from the default 100 ms `SetWinDelay`). The shipped picker starts the CLI with `CreateProcess` + `CREATE_NO_WINDOW` and a pipe (5 s timeout), sets `SetWinDelay(-1)`, and shows the window before querying GlazeWM: window in 203–235 ms, list in 563–688 ms, and text typed before the list arrives still filters it.
- `focus --container-id` on a window in a hidden workspace moves GlazeWM's focus and marks the workspace displayed, but queues no redraw (`redraw_containers` only touches queued windows): the window stays cloaked, the screen does not change, and focus lands on an invisible window (scenario 4 failed this way). A later foreground event sometimes repaired it, which is why the first smoke tests passed. The picker now runs `focus --workspace N` first when the target's workspace is hidden (never for a shown one: `toggle_workspace_on_refocus` would switch away). It also refilters on Enter if the Change event for the last keystrokes has not run yet. Verified by the DWM cloak state, not by GlazeWM's state.
- While GlazeWM's state and the screen disagreed, WezTerm and Overwatch were moved to other workspaces. The likely path is `handle_window_moved_or_resized_end`, which drops a dragged tiling window onto the workspace under the cursor as GlazeWM sees it; `cursor_jump` had also moved the cursor to the portrait display after a focus change there. Not seen again after the picker fix.
- In later use, quick `Win+N` and `Win+Space` taps started opening Start (first under heavy load while a hidden Overwatch kept rendering, then without it), and Start took focus from the picker before it became active, leaving an always-on-top picker that Esc could not reach. Added `dot_glzr/glazewm/win-key-mask.ahk` (the spec's `~LWin::Send "{Blind}{vkE8}"`, started from `startup_commands`, exits when `glazewm.exe` is gone); a bare Win press no longer opens Start (the user accepted this; Ctrl+Esc does). The picker now closes within 250 ms whenever it is not the active window, instead of relying on `WM_ACTIVATE`.
- The install script's `tasklist | grep -q` check reported GlazeWM as not running every time: `grep -q` exits on the first match, `tasklist.exe` gets SIGPIPE, and `pipefail` fails the pipeline. Both greps in the script now read all input.
- The once-only backup to `config.yaml.pre-dotfiles` fired on the second config change of a machine that had no config before the first install, saving the previous dotfiles copy. The script now skips the backup when the installed config carries the `# Source: dot_glzr/glazewm/config.yaml` header.
- Gaps went from 4px to 2px (inner and outer) at the user's request during verification.

## Decisions for This Machine

- Picker: an AutoHotkey v2 GUI (user's choice over conhost + WSL fzf at about 1 s, and WezTerm + fzf at about 2.3 s).
- Displays: workspaces 1–9 bind to the main display (`bind_to_monitor: 1`); workspace 0 binds to the portrait display (`bind_to_monitor: 0`) and is reached with `Mod+0` / `Mod+Shift+0`, which exist only on Windows.
- Slot 1 games: VRChat, Overwatch, Street Fighter 6, one `window_process` line each so adding a game is one line.
- Slot 2: Brave, including its PWA windows.
- FancyZones disabled; the komorebi startup shortcut removed (komorebi itself stays installed).
- GlazeWM autostarts through its tray toggle "Run on system startup".

## Global Constraints

- GlazeWM v3.10 or later (installed: 3.10.1). AutoHotkey v2 (installed: 2.0.31).
- `Mod` is `lwin`. Keymap, app slots and picker key exactly as in the spec's Keymap and App slots tables; Windows adds only `Mod+0` / `Mod+Shift+0`.
- `general.toggle_workspace_on_refocus: true`.
- Games: `commands: ['move --workspace 1', 'set-fullscreen']`, never `ignore`.
- The GlazeWM config stays in the source tree, ignored by chezmoi, and a `run_onchange_after_*` script modeled on `run_onchange_after_35-install-windows-wezterm-config.sh.tmpl` copies it from WSL to `%USERPROFILE%\.glzr\glazewm\config.yaml`.
- The script cannot write `DisableLockWorkstation` (medium integrity; `HKCU\Software\Microsoft\Windows\CurrentVersion\Policies` grants the user only `ReadKey`). It checks the value with `reg.exe query` and prints the elevated `reg add` when it is missing. Both steps are idempotent.
- The user-facing note is Japanese, like `docs/wezterm.md`: `docs/window-manager-windows.md`.
- `scripts/check-chezmoi-managed.sh`: OS-specific sources go in `require_source`; a path goes in `require_ignored` only if it is ignored on every machine (WSL, macOS, NixOS).
- Corrections that affect only Windows go into the spec in this PR (Rollout 5).
- Run `prek run --all-files` before committing. Verify all spec Verification scenarios on this machine before merging.
- Do not touch the macOS or NixOS parts, and do not modify the main checkout at `/home/kise/repos/dotfiles` (it has an untracked session file).
- Manual steps on Windows (UAC, elevated terminal, key presses, settings dialogs) are given to the user one at a time.

---

## File Structure

| Path | Responsibility |
|---|---|
| `dot_glzr/glazewm/config.yaml` (create) | GlazeWM config: startup apps, gaps, border, workspaces and monitor binding, window rules, keymap |
| `dot_glzr/glazewm/window-picker-lib.ahk` (create) | GUI-free picker helpers: JSON parser, `query workspaces` flattening, fuzzy filter |
| `dot_glzr/glazewm/window-picker.ahk` (create) | Picker GUI started by `Mod+Space`; runs the GlazeWM CLI |
| `scripts/test-glazewm-window-picker.ahk` (create) | Headless assertions for the helpers |
| `scripts/test-glazewm-window-picker.sh` (create) | Runs the `.ahk` test under the host's AutoHotkey; skips where there is none |
| `run_onchange_after_36-install-windows-glazewm-config.sh.tmpl` (create) | WSL: copy `dot_glzr/glazewm/*` to the host, reload GlazeWM, check prerequisites |
| `.chezmoiignore` (modify) | Ignore `/.glzr/` unless `.chezmoi.os` is `windows` |
| `scripts/check-chezmoi-managed.sh` (modify) | `require_source` for the new sources, `require_ignored` for `.glzr` |
| `.pre-commit-config.yaml` (modify) | Hook for the picker test |
| `docs/window-manager-windows.md` (create) | Japanese user note |
| `docs/current-state.md` (modify) | List the GlazeWM config and run script |
| `docs/superpowers/specs/2026-11-21-window-manager-design.md` (modify) | Windows-only corrections from Rollout 4 |

---

### Task 1: Prepare the Windows host

**Files:** none in the repository.

**Interfaces:**
- Consumes: nothing.
- Produces: a host where only GlazeWM tiles windows and GlazeWM starts at login.

- [ ] **Step 1: Remove the komorebi startup shortcut**

```bash
startup="$(wslpath "$(wslvar APPDATA </dev/null)")/Microsoft/Windows/Start Menu/Programs/Startup"
rm -- "$startup/komorebi.lnk"
test ! -e "$startup/komorebi.lnk" && echo removed
```

Expected: `removed`.

- [ ] **Step 2: User disables FancyZones**

Ask the user: PowerToys Settings → FancyZones → turn off "Enable FancyZones". Then check:

```bash
powershell.exe -NoProfile -Command '(Get-Content "$env:LOCALAPPDATA\Microsoft\PowerToys\settings.json" -Raw | ConvertFrom-Json).enabled.FancyZones' </dev/null
```

Expected: `False`.

- [ ] **Step 3: User enables GlazeWM autostart**

Ask the user: right-click the GlazeWM tray icon → check "Run on system startup". Then check:

```bash
reg.exe query 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run' /v GlazeWM </dev/null
```

Expected: a `GlazeWM` value pointing at `C:\Program Files\glzr.io\GlazeWM\glazewm.exe`.

---

### Task 2: Picker helpers (JSON, window list, fuzzy filter)

**Files:**
- Create: `dot_glzr/glazewm/window-picker-lib.ahk`
- Create: `scripts/test-glazewm-window-picker.ahk`
- Create: `scripts/test-glazewm-window-picker.sh`
- Modify: `.pre-commit-config.yaml` (append a hook)

**Interfaces:**
- Consumes: `glazewm query workspaces` JSON (GlazeWM 3.10.1): `data.workspaces[]` with `name` and `children`; children are `type: "window"` (with `id`, `title`, `processName`) or containers with their own `children`.
- Produces:
  - `PickerParseJson(text)` → `Map` / `Array` / `String` / number; JSON `true`/`false` → `1`/`0`, `null` → `""`; throws `Error` on malformed input.
  - `PickerCollectWindows(response)` → `Array` of `Map("id", …, "workspace", …, "process", …, "title", …)` in tree order.
  - `PickerFilterWindows(windows, query)` → `Array` of the same maps: every whitespace-separated term must be a case-insensitive subsequence of `workspace " " process " " title`; tightest match first, ties in input order; blank query returns all windows.

- [ ] **Step 1: Write the failing test**

Create `scripts/test-glazewm-window-picker.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
#NoTrayIcon
; Exercises the GlazeWM window picker's helpers headless. Run it through
; scripts/test-glazewm-window-picker.sh, which fails when this exits non-zero.
#Include %A_ScriptDir%\..\dot_glzr\glazewm\window-picker-lib.ahk

failures := 0

Check(name, actual, expected) {
    global failures
    if (actual == expected) {
        FileAppend("ok - " name "`n", "*", "UTF-8")
        return
    }
    failures += 1
    FileAppend("not ok - " name ": expected [" expected "], got [" actual "]`n", "*", "UTF-8")
}

Ids(windows) {
    ids := ""
    for window in windows
        ids .= (ids = "" ? "" : ",") window["id"]
    return ids
}

; Shaped like `glazewm query workspaces` (GlazeWM 3.10.1): windows can sit in
; split containers, and titles carry escapes and non-ASCII text.
sample := "
(
{"clientMessage":"query workspaces","data":{"workspaces":[
{"type":"workspace","id":"w0","name":"0","hasFocus":false,"isDisplayed":true,"children":[
{"type":"window","id":"a1","title":"#general | server - Discord","processName":"Discord","tilingSize":0.5,"x":-1080,"state":{"type":"tiling"},"prevState":null}]},
{"type":"workspace","id":"w2","name":"2","hasFocus":false,"isDisplayed":false,"children":[
{"type":"split","id":"s1","tilingDirection":"vertical","children":[
{"type":"window","id":"b1","title":"Daily calendar","processName":"notes"},
{"type":"window","id":"b2","title":"ALCOM","processName":"ALCOM"}]},
{"type":"window","id":"b3","title":"Say \"hi\" \\ caf\u00e9","processName":"brave"}]},
{"type":"workspace","id":"w3","name":"3","hasFocus":true,"isDisplayed":true,"children":[
{"type":"window","id":"c1","title":"[1/4] tm ~","processName":"wezterm-gui"},
{"type":"window","id":"c2","title":"OBS 32.1.2 - Scenes: 無題","processName":"obs64"}]},
{"type":"workspace","id":"w1","name":"1","hasFocus":false,"isDisplayed":false,"children":[
{"type":"window","id":"d1","title":"VRChat","processName":"VRChat","state":{"type":"fullscreen","maximized":false}}]}
]},"error":null,"success":true}
)"

parsed := PickerParseJson('{"n":-1080,"f":0.5,"t":true,"z":null,"e":[],"a":[1,{"k":"v"}]}')
Check("parses negative integers", parsed["n"], -1080)
Check("parses decimals", parsed["f"], 0.5)
Check("parses true", parsed["t"], true)
Check("parses null as an empty string", parsed["z"], "")
Check("parses empty arrays", parsed["e"].Length, 0)
Check("parses objects nested in arrays", parsed["a"][2]["k"], "v")

threw := false
try PickerParseJson('{"a":')
catch
    threw := true
Check("rejects truncated JSON", threw, true)

windows := PickerCollectWindows(PickerParseJson(sample))
Check("collects windows in tree order, split children included", Ids(windows), "a1,b1,b2,b3,c1,c2,d1")
Check("tags a split child with its workspace", windows[3]["workspace"], "2")
Check("decodes title escapes", windows[4]["title"], 'Say "hi" \ café')
Check("keeps non-ASCII titles", windows[6]["title"], "OBS 32.1.2 - Scenes: 無題")

Check("blank query keeps every window in order", Ids(PickerFilterWindows(windows, "  ")), "a1,b1,b2,b3,c1,c2,d1")
Check("matches case-insensitively, tightest match first", Ids(PickerFilterWindows(windows, "vrc")), "d1,a1")
Check("ranks a contiguous match above scattered ones", Ids(PickerFilterWindows(windows, "alc")), "b2,b1,a1")
Check("requires every term, workspace name included", Ids(PickerFilterWindows(windows, "3 wez")), "c1")
Check("returns nothing when no window matches", Ids(PickerFilterWindows(windows, "zzz")), "")

ExitApp(failures ? 1 : 0)
```

Create `scripts/test-glazewm-window-picker.sh` (then `chmod +x`):

```bash
#!/usr/bin/env bash
# Runs the GlazeWM window picker's helper tests (JSON parsing, window list,
# fuzzy filter) under the Windows host's AutoHotkey v2. AutoHotkey exists only
# on the Windows host, so other machines skip.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if ! grep -qi microsoft /proc/version 2>/dev/null || ! command -v reg.exe >/dev/null 2>&1; then
  echo "skip - not WSL; the window picker runs on the Windows host"
  exit 0
fi

# The installer records its directory under HKCU (per-user) or HKLM.
install_dir=""
for key in 'HKCU\Software\AutoHotkey' 'HKLM\Software\AutoHotkey'; do
  install_dir=$(reg.exe query "$key" /v InstallDir </dev/null 2>/dev/null |
    sed -n 's/^ *InstallDir *REG_SZ *//p' | tr -d '\r' || true)
  [ -n "$install_dir" ] && break
done
ahk="${install_dir:+$(wslpath "$install_dir")/v2/AutoHotkey64.exe}"
if [ -z "$ahk" ] || [ ! -f "$ahk" ]; then
  echo "skip - AutoHotkey v2 is not installed on the Windows host"
  exit 0
fi

# AutoHotkey64.exe is a GUI program; piping keeps its stdout attached.
"$ahk" /ErrorStdOut "$(wslpath -w "$repo_root/scripts/test-glazewm-window-picker.ahk")" </dev/null | cat
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `scripts/test-glazewm-window-picker.sh; echo "rc=$?"`
Expected: AutoHotkey reports the missing include (`#Include file ... window-picker-lib.ahk cannot be opened`) and `rc=2` (or another non-zero code).

- [ ] **Step 3: Write the implementation**

Create `dot_glzr/glazewm/window-picker-lib.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
; Helpers for window-picker.ahk: a JSON parser, flattening of
; `glazewm query workspaces`, and the fuzzy filter. No GUI or process calls,
; so scripts/test-glazewm-window-picker.ahk can run them headless.

; Parses JSON text. Objects become Map, arrays Array, null "" (empty string),
; true/false 1/0. Throws Error on malformed input.
PickerParseJson(text) {
    pos := 1
    value := PickerJsonValue(text, &pos)
    PickerJsonSkipSpace(text, &pos)
    if (pos <= StrLen(text))
        throw Error("Unexpected text after the JSON value at " pos)
    return value
}

PickerJsonSkipSpace(text, &pos) {
    if RegExMatch(text, "\G[ \t\r\n]+", &m, pos)
        pos += m.Len
}

PickerJsonValue(text, &pos) {
    static literals := Map("true", true, "false", false, "null", "")
    PickerJsonSkipSpace(text, &pos)
    ch := SubStr(text, pos, 1)
    if (ch = "{")
        return PickerJsonObject(text, &pos)
    if (ch = "[")
        return PickerJsonArray(text, &pos)
    if (ch = '"')
        return PickerJsonString(text, &pos)
    if RegExMatch(text, "\G-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", &m, pos) {
        pos += m.Len
        return m[0] + 0
    }
    for literal, value in literals {
        if (SubStr(text, pos, StrLen(literal)) == literal) {
            pos += StrLen(literal)
            return value
        }
    }
    throw Error("Unexpected JSON at " pos)
}

PickerJsonObject(text, &pos) {
    obj := Map()
    pos += 1
    PickerJsonSkipSpace(text, &pos)
    if (SubStr(text, pos, 1) = "}") {
        pos += 1
        return obj
    }
    loop {
        PickerJsonSkipSpace(text, &pos)
        if (SubStr(text, pos, 1) != '"')
            throw Error("Expected an object key at " pos)
        key := PickerJsonString(text, &pos)
        PickerJsonSkipSpace(text, &pos)
        if (SubStr(text, pos, 1) != ":")
            throw Error("Expected ':' at " pos)
        pos += 1
        obj[key] := PickerJsonValue(text, &pos)
        PickerJsonSkipSpace(text, &pos)
        separator := SubStr(text, pos, 1)
        pos += 1
        if (separator = "}")
            return obj
        if (separator != ",")
            throw Error("Expected ',' or '}' at " (pos - 1))
    }
}

PickerJsonArray(text, &pos) {
    arr := []
    pos += 1
    PickerJsonSkipSpace(text, &pos)
    if (SubStr(text, pos, 1) = "]") {
        pos += 1
        return arr
    }
    loop {
        arr.Push(PickerJsonValue(text, &pos))
        PickerJsonSkipSpace(text, &pos)
        separator := SubStr(text, pos, 1)
        pos += 1
        if (separator = "]")
            return arr
        if (separator != ",")
            throw Error("Expected ',' or ']' at " (pos - 1))
    }
}

; pos is at the opening quote; returns the decoded string.
PickerJsonString(text, &pos) {
    out := ""
    pos += 1
    loop {
        RegExMatch(text, '\G[^"\\]*', &m, pos)
        out .= m[0]
        pos += m.Len
        ch := SubStr(text, pos, 1)
        if (ch = '"') {
            pos += 1
            return out
        }
        if (ch != "\")
            throw Error("Unterminated JSON string")
        escaped := SubStr(text, pos + 1, 1)
        switch escaped, true {
            case '"', "\", "/": out .= escaped
            case "b": out .= Chr(8)
            case "f": out .= Chr(12)
            case "n": out .= "`n"
            case "r": out .= "`r"
            case "t": out .= "`t"
            case "u":
                hex := SubStr(text, pos + 2, 4)
                if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                    throw Error("Bad \u escape at " pos)
                ; Surrogate pairs arrive as two escapes; AutoHotkey strings
                ; are UTF-16, so appending both halves yields the character.
                out .= Chr(Integer("0x" hex))
                pos += 4
            default:
                throw Error("Bad escape at " pos)
        }
        pos += 2
    }
}

; Flattens `glazewm query workspaces` output into one Map per window with id,
; workspace, process and title, in GlazeWM's tree order.
PickerCollectWindows(response) {
    windows := []
    for workspace in response["data"]["workspaces"]
        PickerCollectChildren(workspace["children"], workspace["name"], windows)
    return windows
}

PickerCollectChildren(children, workspaceName, windows) {
    for child in children {
        if (child["type"] == "window")
            windows.Push(Map(
                "id", child["id"],
                "workspace", workspaceName,
                "process", child["processName"],
                "title", child["title"]))
        else if child.Has("children")
            PickerCollectChildren(child["children"], workspaceName, windows)
    }
}

; Keeps the windows whose "workspace process title" text contains every
; whitespace-separated query term as a case-insensitive subsequence. Tightest
; matches come first; ties keep input order. A blank query keeps everything.
PickerFilterWindows(windows, query) {
    terms := []
    for term in StrSplit(query, [" ", "`t"])
        if (term != "")
            terms.Push(term)
    if !terms.Length
        return windows.Clone()

    scored := []
    for window in windows {
        haystack := window["workspace"] " " window["process"] " " window["title"]
        total := 0
        for term in terms {
            score := PickerSubsequenceScore(haystack, term)
            if (score < 0) {
                total := -1
                break
            }
            total += score
        }
        if (total >= 0)
            scored.Push([total, window])
    }

    ; Stable insertion sort by score; the list is a few dozen windows.
    loop scored.Length - 1 {
        entry := scored[A_Index + 1]
        j := A_Index
        while (j >= 1 && scored[j][1] > entry[1]) {
            scored[j + 1] := scored[j]
            j -= 1
        }
        scored[j + 1] := entry
    }

    result := []
    for entry in scored
        result.Push(entry[2])
    return result
}

; Score of the tightest case-insensitive subsequence match of term in haystack:
; skipped characters inside the match times 1000, plus the match start, so a
; contiguous match beats a scattered one and an earlier match wins ties.
; Returns -1 when term is not a subsequence.
PickerSubsequenceScore(haystack, term) {
    best := -1
    termLength := StrLen(term)
    start := 0
    while (start := InStr(haystack, SubStr(term, 1, 1), false, start + 1)) {
        pos := start
        loop termLength - 1 {
            pos := InStr(haystack, SubStr(term, A_Index + 1, 1), false, pos + 1)
            if !pos
                break
        }
        ; A later start cannot complete a match this one could not.
        if !pos
            break
        score := (pos - start + 1 - termLength) * 1000 + start
        if (best < 0 || score < best)
            best := score
    }
    return best
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `scripts/test-glazewm-window-picker.sh; echo "rc=$?"`
Expected: sixteen `ok - …` lines, no `not ok`, `rc=0`.

- [ ] **Step 5: Add the hook**

Append to the `hooks:` list in `.pre-commit-config.yaml`:

```yaml
      - id: glazewm-window-picker
        name: GlazeWM window picker helpers (Windows host AutoHotkey)
        entry: scripts/test-glazewm-window-picker.sh
        language: system
        files: ^(dot_glzr/glazewm/window-picker-lib\.ahk|scripts/test-glazewm-window-picker\.(sh|ahk))$
        pass_filenames: false
```

Run: `prek run glazewm-window-picker --all-files`
Expected: `GlazeWM window picker helpers (Windows host AutoHotkey)....Passed`.

---

### Task 3: Picker GUI

**Files:**
- Create: `dot_glzr/glazewm/window-picker.ahk`

**Interfaces:**
- Consumes: `PickerParseJson`, `PickerCollectWindows`, `PickerFilterWindows` from Task 2; `%ProgramFiles%\glzr.io\GlazeWM\cli\glazewm.exe`.
- Produces: a script that Task 4 binds to `lwin+space` as `shell-exec %ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe "%USERPROFILE%\.glzr\glazewm\window-picker.ahk"`. Window title `GlazeWM window picker`.

- [ ] **Step 1: Write the GUI**

Create `dot_glzr/glazewm/window-picker.ahk` as below. The shipped picker differs after the Findings: it shows the window before querying, runs the CLI through `CreateProcess`, shows a hidden workspace with `focus --workspace` before `focus --container-id`, refilters on Enter, and closes on a 250 ms focus check.

```autohotkey
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon
#Include %A_ScriptDir%\window-picker-lib.ahk

; GlazeWM window picker (Mod+Space). GlazeWM starts it from a shell-exec
; keybinding. It lists every managed window, including those on hidden
; workspaces that PowerToys Command Palette's "Switch windows" leaves out
; (GlazeWM cloaks them), and focuses the chosen one with
; `glazewm command focus --container-id`, which also shows its workspace.
; Type to filter, Up/Down to move, Enter to focus, Esc or clicking elsewhere
; to close. It is a tool window, so GlazeWM does not tile it.

glazewm := A_ProgramFiles "\glzr.io\GlazeWM\cli\glazewm.exe"

try allWindows := PickerCollectWindows(PickerParseJson(RunGlazeWM("query workspaces")))
catch as err {
    MsgBox("Could not list GlazeWM windows: " err.Message, "GlazeWM window picker", "Iconx")
    ExitApp(1)
}
shown := []
choosing := false

picker := Gui("+AlwaysOnTop +ToolWindow", "GlazeWM window picker")
pickerHwnd := picker.Hwnd
picker.SetFont("s11", "Segoe UI")
search := picker.AddEdit("w900")
list := picker.AddListView("w900 r16 -Multi NoSortHdr", ["WS", "App", "Title"])
search.OnEvent("Change", (*) => Refresh())
list.OnEvent("DoubleClick", (*) => Choose())
picker.OnEvent("Escape", (*) => ExitApp())
picker.OnEvent("Close", (*) => ExitApp())
OnMessage(0x0100, OnKeyDown)          ; WM_KEYDOWN
OnMessage(0x0006, CloseOnDeactivate)  ; WM_ACTIVATE

Refresh()
picker.Show()
WinActivate(picker)
search.Focus()

Refresh() {
    global shown
    shown := PickerFilterWindows(allWindows, search.Value)
    list.Opt("-Redraw")
    list.Delete()
    for window in shown
        list.Add(, window["workspace"], window["process"], window["title"])
    if shown.Length
        list.Modify(1, "Select Focus Vis")
    loop 3
        list.ModifyCol(A_Index, "AutoHdr")
    list.Opt("+Redraw")
}

; Enter focuses the selection from the search box or the list; Up/Down in the
; search box move the selection. Other keys keep their default handling.
OnKeyDown(wParam, lParam, msg, hwnd) {
    if (wParam = 0x0D && (hwnd = search.Hwnd || hwnd = list.Hwnd)) {  ; VK_RETURN
        Choose()
        return 0
    }
    if (hwnd != search.Hwnd || (wParam != 0x26 && wParam != 0x28))   ; VK_UP, VK_DOWN
        return
    if shown.Length {
        row := Max(1, Min(shown.Length, list.GetNext() + (wParam = 0x26 ? -1 : 1)))
        list.Modify(0, "-Select")
        list.Modify(row, "Select Focus Vis")
    }
    return 0
}

Choose() {
    global choosing
    row := list.GetNext()
    if !row
        return
    choosing := true
    picker.Hide()
    try RunGlazeWM("command focus --container-id " shown[row]["id"])
    ExitApp()
}

CloseOnDeactivate(wParam, lParam, msg, hwnd) {
    if (!choosing && hwnd = pickerHwnd && !(wParam & 0xFFFF))  ; WA_INACTIVE
        ExitApp()
}

; Runs the GlazeWM CLI without a console window and returns its stdout.
RunGlazeWM(args) {
    out := A_Temp "\glazewm-window-picker-" DllCall("GetCurrentProcessId") ".json"
    exitCode := RunWait(A_ComSpec ' /c ""' glazewm '" ' args ' > "' out '""', , "Hide")
    text := FileExist(out) ? FileRead(out, "UTF-8") : ""
    try FileDelete(out)
    if exitCode
        throw Error("glazewm " args " exited with " exitCode)
    return text
}
```

- [ ] **Step 2: Smoke-test against the running GlazeWM**

Tell the user a picker window will open and close by itself. Pick a window on a hidden workspace (`glazewm query workspaces`, a workspace with `isDisplayed: false`, e.g. ALCOM), then drive the repository's picker with a throwaway script saved as `%TEMP%\picker-driver.ahk`:

```autohotkey
#Requires AutoHotkey v2.0
#NoTrayIcon
; Throwaway driver: opens the repository's picker, filters, presses Enter.
started := A_TickCount
Run('"' A_AhkPath '" "' A_Args[1] '"')
if !WinWait("GlazeWM window picker", , 5) {
    FileAppend("picker did not appear`n", "*")
    ExitApp(1)
}
FileAppend("picker shown after " (A_TickCount - started) " ms`n", "*")
WinActivate
WinWaitActive("GlazeWM window picker", , 2)
SendText(A_Args[2])
Sleep(300)
Send("{Enter}")
FileAppend("closed=" (WinWaitClose("GlazeWM window picker", , 3) ? 1 : 0) "`n", "*")
```

```bash
ahk='/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey64.exe'
temp_dir=$(wslpath "$(wslvar TEMP </dev/null)")
"$ahk" /ErrorStdOut "$(wslpath -w "$temp_dir/picker-driver.ahk")" \
  "$(wslpath -w dot_glzr/glazewm/window-picker.ahk)" alcom </dev/null | cat
'/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe' query focused </dev/null | jq -r '.data.focused.processName'
rm -- "$temp_dir/picker-driver.ahk"
```

Expected: `picker shown after <N> ms` (well under 1000), `closed=1`, then `ALCOM`, with the main display now showing ALCOM's workspace. Return the user to the terminal with `glazewm command focus --container-id <WezTerm id>`.

---

### Task 4: GlazeWM config and deployment

**Files:**
- Create: `dot_glzr/glazewm/config.yaml`
- Create: `run_onchange_after_36-install-windows-glazewm-config.sh.tmpl`
- Modify: `.chezmoiignore`
- Modify: `scripts/check-chezmoi-managed.sh:53-81`

**Interfaces:**
- Consumes: `dot_glzr/glazewm/window-picker.ahk` and `window-picker-lib.ahk` from Tasks 2–3.
- Produces: `%USERPROFILE%\.glzr\glazewm\{config.yaml,window-picker.ahk,window-picker-lib.ahk}` on the host, loaded by GlazeWM.

- [ ] **Step 1: Write the config**

Create `dot_glzr/glazewm/config.yaml`:

```yaml
# GlazeWM config for the Windows host.
#
# Source: dot_glzr/glazewm/config.yaml in the dotfiles repository. From WSL,
# `chezmoi apply` runs run_onchange_after_36-install-windows-glazewm-config.sh,
# which copies this file and the window picker to %USERPROFILE%\.glzr\glazewm\
# and reloads GlazeWM. Edit the repository copy, not the installed one.
#
# Keymap and app slots: docs/superpowers/specs/2026-11-21-window-manager-design.md.
# Windows notes (setup, displays, adding a game): docs/window-manager-windows.md.
#
# shell-exec: GlazeWM 3.10.1 rejects a program path in double quotes (it looks
# for a third quote), so program paths stay unquoted; GlazeWM finds the file by
# growing the path one word at a time. Arguments may be quoted.

general:
  # Fill slots 2 and 3 at login. Restarting GlazeWM opens another window of each.
  startup_commands:
    - 'shell-exec %ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe'
    - 'shell-exec %ProgramFiles%\WezTerm\wezterm-gui.exe'
  # Mod+N on the workspace already shown returns to the previous one.
  toggle_workspace_on_refocus: true

gaps:
  scale_with_dpi: true
  inner_gap: '4px'
  outer_gap:
    top: '4px'
    right: '4px'
    bottom: '4px'
    left: '4px'

window_effects:
  focused_window:
    border:
      enabled: true
      color: '#89b4fa'
  other_windows:
    border:
      enabled: false
      color: '#a1a1a1'

# GlazeWM numbers displays from the left: the portrait display is 0 and the
# main one is 1. Slots 1-9 stay on the main display and workspace 0 on the
# portrait one. A binding to a missing display is ignored, so with one display
# every workspace opens there.
workspaces:
  - name: '1'
    bind_to_monitor: 1
  - name: '2'
    bind_to_monitor: 1
  - name: '3'
    bind_to_monitor: 1
  - name: '4'
    bind_to_monitor: 1
  - name: '5'
    bind_to_monitor: 1
  - name: '6'
    bind_to_monitor: 1
  - name: '7'
    bind_to_monitor: 1
  - name: '8'
    bind_to_monitor: 1
  - name: '9'
    bind_to_monitor: 1
  - name: '0'
    bind_to_monitor: 0

# Rules run once per window, when GlazeWM starts managing it or its title
# changes; Mod+Shift+N moves the window freely afterwards.
window_rules:
  # Slot 1: games, managed but untiled. Never `ignore` them: that takes the
  # window out of the workspace tree, so Mod+1 would show an empty workspace.
  # To add a game, add a line with its executable name without `.exe`.
  - commands: ['move --workspace 1', 'set-fullscreen']
    match:
      - window_process: { equals: 'VRChat' }
      - window_process: { equals: 'Overwatch' }
      - window_process: { equals: 'StreetFighter6' }

  # Slot 2: the browser. Brave PWAs (for example Discord) run as brave.exe too.
  - commands: ['move --workspace 2']
    match:
      - window_process: { equals: 'brave' }

  # Slot 3: WezTerm. `window_decorations = "RESIZE"` leaves out WS_THICKFRAME,
  # so GlazeWM would float it as non-resizable; tile it instead.
  - commands: ['set-tiling', 'move --workspace 3']
    match:
      - window_process: { equals: 'wezterm-gui' }

  # From GlazeWM's sample config, for apps on this machine: browser
  # picture-in-picture, Command Palette, Peek, and Lively wallpaper.
  - commands: ['ignore']
    match:
      - window_title: { regex: '[Pp]icture.in.[Pp]icture' }
        window_class: { regex: 'Chrome_WidgetWin_1' }
      - window_title: { equals: 'Command Palette' }
        window_class: { equals: 'WinUIDesktopWin32WindowClass' }
      - window_process: { equals: 'PowerToys' }
        window_title: { regex: '.*? - Peek' }
      - window_process: { equals: 'Lively' }
        window_class: { regex: 'HwndWrapper' }

keybindings:
  # Mod+N: go to workspace N; pressing it again returns.
  - commands: ['focus --workspace 1']
    bindings: ['lwin+1']
  - commands: ['focus --workspace 2']
    bindings: ['lwin+2']
  - commands: ['focus --workspace 3']
    bindings: ['lwin+3']
  - commands: ['focus --workspace 4']
    bindings: ['lwin+4']
  - commands: ['focus --workspace 5']
    bindings: ['lwin+5']
  - commands: ['focus --workspace 6']
    bindings: ['lwin+6']
  - commands: ['focus --workspace 7']
    bindings: ['lwin+7']
  - commands: ['focus --workspace 8']
    bindings: ['lwin+8']
  - commands: ['focus --workspace 9']
    bindings: ['lwin+9']
  - commands: ['focus --workspace 0']
    bindings: ['lwin+0']

  # Mod+Shift+N: send the window to workspace N and follow it.
  - commands: ['move --workspace 1', 'focus --workspace 1']
    bindings: ['lwin+shift+1']
  - commands: ['move --workspace 2', 'focus --workspace 2']
    bindings: ['lwin+shift+2']
  - commands: ['move --workspace 3', 'focus --workspace 3']
    bindings: ['lwin+shift+3']
  - commands: ['move --workspace 4', 'focus --workspace 4']
    bindings: ['lwin+shift+4']
  - commands: ['move --workspace 5', 'focus --workspace 5']
    bindings: ['lwin+shift+5']
  - commands: ['move --workspace 6', 'focus --workspace 6']
    bindings: ['lwin+shift+6']
  - commands: ['move --workspace 7', 'focus --workspace 7']
    bindings: ['lwin+shift+7']
  - commands: ['move --workspace 8', 'focus --workspace 8']
    bindings: ['lwin+shift+8']
  - commands: ['move --workspace 9', 'focus --workspace 9']
    bindings: ['lwin+shift+9']
  - commands: ['move --workspace 0', 'focus --workspace 0']
    bindings: ['lwin+shift+0']

  # Mod+h/j/k/l: focus; Mod+Shift+h/j/k/l: move.
  - commands: ['focus --direction left']
    bindings: ['lwin+h']
  - commands: ['focus --direction down']
    bindings: ['lwin+j']
  - commands: ['focus --direction up']
    bindings: ['lwin+k']
  - commands: ['focus --direction right']
    bindings: ['lwin+l']
  - commands: ['move --direction left']
    bindings: ['lwin+shift+h']
  - commands: ['move --direction down']
    bindings: ['lwin+shift+j']
  - commands: ['move --direction up']
    bindings: ['lwin+shift+k']
  - commands: ['move --direction right']
    bindings: ['lwin+shift+l']

  - commands: ['toggle-fullscreen']
    bindings: ['lwin+f']
  - commands: ['toggle-floating']
    bindings: ['lwin+shift+space']
  - commands: ['resize --width -5%']
    bindings: ['lwin+oem_minus']
  - commands: ['resize --width +5%']
    bindings: ['lwin+oem_plus']

  # Mod+Space: window picker (dot_glzr/glazewm/window-picker.ahk).
  - commands: ['shell-exec %ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe "%USERPROFILE%\.glzr\glazewm\window-picker.ahk"']
    bindings: ['lwin+space']
```

- [ ] **Step 2: Ignore `.glzr` outside native Windows**

In `.chezmoiignore`, append after the darwin block:

```
{{- if ne .chezmoi.os "windows" }}
/.glzr/
{{- end }}
```

- [ ] **Step 3: Write the failing managed-paths check**

In `scripts/check-chezmoi-managed.sh`, add to `require_source` (after `"dot_config/karabiner/karabiner.json"`):

```bash
  "dot_glzr/glazewm/config.yaml"
  "dot_glzr/glazewm/window-picker.ahk"
  "dot_glzr/glazewm/window-picker-lib.ahk"
```

and after `"run_onchange_after_35-install-windows-wezterm-config.sh.tmpl"`:

```bash
  "run_onchange_after_36-install-windows-glazewm-config.sh.tmpl"
```

and to `require_ignored` (after `"docs"`):

```bash
  ".glzr"
```

Run: `scripts/check-chezmoi-managed.sh; echo "rc=$?"`
Expected: `expected chezmoi source script missing: run_onchange_after_36-install-windows-glazewm-config.sh.tmpl`, `rc=1`.

- [ ] **Step 4: Write the install script**

Create `run_onchange_after_36-install-windows-glazewm-config.sh.tmpl`:

```bash
{{- if eq .chezmoi.os "linux" -}}
#!/usr/bin/env bash
# WSL: GlazeWM runs on the Windows host and reads
# %USERPROFILE%\.glzr\glazewm\config.yaml, outside chezmoi's home, so copy the
# config and the Mod+Space window picker there and reload GlazeWM. Symlinks
# into WSL are not usable from Windows. Re-runs whenever one of them changes.
# Also reports missing one-time host setup; see docs/window-manager-windows.md.
# config.yaml hash: {{ include "dot_glzr/glazewm/config.yaml" | sha256sum }}
# window-picker.ahk hash: {{ include "dot_glzr/glazewm/window-picker.ahk" | sha256sum }}
# window-picker-lib.ahk hash: {{ include "dot_glzr/glazewm/window-picker-lib.ahk" | sha256sum }}
set -euo pipefail

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  exit 0
fi

if ! command -v wslvar >/dev/null 2>&1 || ! command -v wslpath >/dev/null 2>&1; then
  echo "warning: wslvar/wslpath (wslu) not found; skipping Windows GlazeWM config" >&2
  exit 0
fi

# wslvar runs powershell.exe, which drains stdin unless it is redirected.
windows_profile=$(wslvar USERPROFILE </dev/null 2>/dev/null || true)
program_files=$(wslvar ProgramFiles </dev/null 2>/dev/null || true)
if [ -z "$windows_profile" ] || [ -z "$program_files" ]; then
  echo "warning: could not resolve %USERPROFILE% or %ProgramFiles%; skipping Windows GlazeWM config" >&2
  exit 0
fi
target_dir="$(wslpath "$windows_profile")/.glzr/glazewm"
program_files=$(wslpath "$program_files")
source_dir={{ joinPath .chezmoi.sourceDir "dot_glzr/glazewm" | quote }}

mkdir -p "$target_dir"
# Keep a hand-maintained config from before this script took over, once.
if [ -f "$target_dir/config.yaml" ] && [ ! -e "$target_dir/config.yaml.pre-dotfiles" ] &&
  ! cmp -s "$source_dir/config.yaml" "$target_dir/config.yaml"; then
  cp "$target_dir/config.yaml" "$target_dir/config.yaml.pre-dotfiles"
  echo "info: backed up existing $target_dir/config.yaml to config.yaml.pre-dotfiles"
fi
for file in config.yaml window-picker.ahk window-picker-lib.ahk; do
  cp "$source_dir/$file" "$target_dir/$file"
done
echo "info: installed GlazeWM config to $target_dir"

glazewm="$program_files/glzr.io/GlazeWM/cli/glazewm.exe"
if [ ! -f "$glazewm" ]; then
  echo "warning: GlazeWM is not installed. Install it (one UAC prompt, without Zebar) with:" >&2
  echo "  winget install --id glzr-io.glazewm --exact --override \"/quiet /norestart Custom_InstallZebar=0\"" >&2
elif ! tasklist.exe /FI "IMAGENAME eq glazewm.exe" /NH </dev/null 2>/dev/null | grep -qi '^glazewm\.exe'; then
  echo "info: GlazeWM is not running; it reads the config when it starts"
# The CLI waits for the WM without a deadline, so bound it in case GlazeWM hangs.
elif reload=$(timeout 10 "$glazewm" command wm-reload-config </dev/null 2>/dev/null); then
  case $reload in
    *'"success":true'*) echo "info: reloaded GlazeWM" ;;
    *) echo "warning: GlazeWM did not accept the config: $reload" >&2 ;;
  esac
else
  echo "warning: GlazeWM did not answer the reload request; use Reload config in its tray menu" >&2
fi

if [ ! -f "$program_files/AutoHotkey/v2/AutoHotkey64.exe" ]; then
  echo "warning: AutoHotkey v2 is missing, so the Win+Space window picker will not open. Install it with:" >&2
  echo "  winget install --id AutoHotkey.AutoHotkey --exact" >&2
fi

# Win+L locks the session before GlazeWM sees it unless workstation locking is
# off. Policies grants this user only ReadKey, so only an elevated shell can
# write it.
policy_key='HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System'
if ! reg.exe query "$policy_key" /v DisableLockWorkstation </dev/null 2>/dev/null | grep -q '0x1'; then
  echo "warning: Win+L still locks the session. Run this once from an elevated terminal:" >&2
  echo "  reg add \"$policy_key\" /v DisableLockWorkstation /t REG_DWORD /d 1 /f" >&2
fi
{{ end -}}
```

- [ ] **Step 5: Run the managed-paths check to verify it passes**

Run: `scripts/check-chezmoi-managed.sh; echo "rc=$?"` and `chezmoi --source . ignored | grep -x .glzr`
Expected: `rc=0`, then `.glzr`.

- [ ] **Step 6: Deploy from the worktree and restart GlazeWM**

Remove the Rollout 4 throwaway config so the script does not back it up, then render and run only the new script (a full `chezmoi apply` from the worktree would also apply the rest of the tree):

```bash
glazewm_dir="$(wslpath "$(wslvar USERPROFILE </dev/null)")/.glzr/glazewm"
rm -- "$glazewm_dir/config.yaml"
chezmoi --source . execute-template <run_onchange_after_36-install-windows-glazewm-config.sh.tmpl | bash
ls "$glazewm_dir"
```

Expected: `info: installed GlazeWM config to …/.glzr/glazewm` and `info: reloaded GlazeWM`, no `warning:` line, and `ls` shows `config.yaml window-picker-lib.ahk window-picker.ahk` without a `config.yaml.pre-dotfiles`.

Tell the user GlazeWM restarts and opens one more Brave and WezTerm window (the startup commands). Restart so workspaces bind to their displays from scratch:

```bash
g='/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe'
"$g" command wm-exit </dev/null
cmd.exe /c start "" "C:\Program Files\glzr.io\GlazeWM\glazewm.exe" </dev/null
sleep 5
"$g" query monitors </dev/null | jq -c '.data.monitors[] | {x, width, ws: [.children[] | .name]}'
```

Expected: the portrait display (`x: -1080`) lists workspace `0`; the main display lists `1` plus the slot workspaces its windows landed on (`2` for Brave, `3` for WezTerm).

---

### Task 5: Docs and spec corrections

**Files:**
- Create: `docs/window-manager-windows.md`
- Modify: `docs/current-state.md:20,127`
- Modify: `docs/superpowers/specs/2026-11-21-window-manager-design.md` (Non-goals multi-monitor line, `Win` Start-menu and `Win+Space` bullets, Window picker table and paragraph, Repository layout Windows bullet)

**Interfaces:**
- Consumes: the behavior from Tasks 1–4.
- Produces: user documentation; no code.

- [ ] **Step 1: Write the user note**

Create `docs/window-manager-windows.md` as below. The shipped note also carries the Findings: a paragraph on display off/on under ワークスペースとディスプレイ, and a 終了と再起動 section (uiAccess, `wm-exit`, the elevated `taskkill` of GlazeWM and `glazewm-watcher`, and windows left cloaked after a forced kill).

````markdown
# ウィンドウマネージャ (Windows / GlazeWM)

Windows ホストでは [GlazeWM](https://github.com/glzr-io/glazewm) で
`docs/superpowers/specs/2026-11-21-window-manager-design.md` のキー配置を使う。
`Mod` は `Win`。

## 配置

設定は `dot_glzr/glazewm/` にある。chezmoi は Windows ネイティブ以外ではこの
ディレクトリを無視する (`.chezmoiignore`)。WSL で `chezmoi apply` すると、
`run_onchange_after_36-install-windows-glazewm-config.sh.tmpl` が次の 3 ファイルを
`%USERPROFILE%\.glzr\glazewm\` にコピーし、動いている GlazeWM に設定を再読み込み
させる。3 ファイルのどれかが変わったときだけ再実行される。

- `config.yaml`: GlazeWM の設定
- `window-picker.ahk`: `Win+Space` のウィンドウピッカー (AutoHotkey v2)
- `window-picker-lib.ahk`: ピッカーの JSON 解析と絞り込み。テストは
  `scripts/test-glazewm-window-picker.sh` (prek のフックとして実行される)

Windows 側のコピーを直接編集しても、次のコピーで上書きされる。変更は repo 側で
行う。ワークスペースとディスプレイの割り当ては再読み込みだけでは組み直されない
ので、`workspaces` を変えたときは GlazeWM を再起動する (トレイアイコンの Exit の
あと、スタートメニューから GlazeWM を起動する)。再起動すると `startup_commands`
で Brave と WezTerm の窓がもう 1 つずつ開く。

## 初回セットアップ

一度だけ行う。スクリプトは、手順 1〜3 が済んでいないと警告とコマンドを表示する。

1. GlazeWM を入れる。Zebar は入れない。UAC の確認が 1 回出る。

   ```
   winget install --id glzr-io.glazewm --exact --override "/quiet /norestart Custom_InstallZebar=0"
   ```

2. AutoHotkey v2 を入れる。

   ```
   winget install --id AutoHotkey.AutoHotkey --exact
   ```

3. `Win+L` を GlazeWM に渡すため、画面ロックを無効にする。管理者のターミナルで
   実行する。WSL から起動したプロセスは中整合性レベルで動き、`Policies` キーには
   読み取り権限しかないので、スクリプトからは書けない。

   ```
   reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f
   ```

   `Win+L` だけでなく Ctrl+Alt+Del 画面の「ロック」も使えなくなる。
4. WSL で `chezmoi apply` する。
5. GlazeWM のトレイアイコンを右クリックし、「Run on system startup」にチェックを
   入れる。
6. ほかのタイル型ウィンドウマネージャと窓の自動配置を止める。PowerToys の
   FancyZones は無効にする。komorebi などがスタートアップに登録されていれば外す。

## キー

| キー | 動作 |
|---|---|
| `Win+1`〜`9` | ワークスペース N へ移動。表示中の番号をもう一度押すと直前のワークスペースに戻る |
| `Win+0` | 縦置きディスプレイのワークスペース 0 へ移動 (Windows だけ) |
| `Win+Shift+1`〜`9`, `Win+Shift+0` | 窓をワークスペース N へ送り、一緒に移動する |
| `Win+H/J/K/L` | 左/下/上/右の窓へフォーカス |
| `Win+Shift+H/J/K/L` | 窓を左/下/上/右へ動かす |
| `Win+F` | 全画面の切り替え |
| `Win+Shift+Space` | フローティングの切り替え |
| `Win+-` / `Win+=` | 幅を 5% 狭く / 広く |
| `Win+Space` | ウィンドウピッカー |

GlazeWM が使う `Win+…` は、同じキーの Windows 標準の動作 (タスクバーの
`Win+数字`、拡大鏡の `Win+-`/`Win+=`、音声入力の `Win+H` など) より優先される。

入力言語 (ENG / JPN) の切り替えは `Win+Space` から **`Win+Ctrl+Space`** に移す。
GlazeWM はバインドにない修飾キー (ここでは Ctrl) が一緒に押されているとキーを
素通しするので、`Win+Ctrl+Space` は Windows に届く。左 `Alt+Shift` でも切り替え
られる。

`Win` と数字を素早く押して離しても Start メニューは開いたままにならない
(Windows 11 25H2 + GlazeWM 3.10.1 で確認)。連打すると一瞬だけ開くことがあるが、
すぐ閉じる。

## ワークスペースとディスプレイ

GlazeWM はディスプレイに左から 0, 1, … と番号を付ける。この PC では左の縦置きが
0、メインが 1 になる。

- ワークスペース 1〜9 はメインに固定する (`bind_to_monitor: 1`)。
- ワークスペース 0 は縦置きに固定する (`bind_to_monitor: 0`)。`Win+0` で移動し、
  `Win+Shift+0` で窓を送る。
- ディスプレイが 1 枚のときは割り当てが無視され、すべてそのディスプレイに開く。
  ディスプレイの並びを変えたら番号を見直す。

## アプリの固定 (slot)

| slot | アプリ | ルール (`window_rules`) |
|---|---|---|
| 1 | ゲーム (VRChat, Overwatch, Street Fighter 6) | `move --workspace 1`, `set-fullscreen` |
| 2 | Brave | `move --workspace 2` |
| 3 | WezTerm | `set-tiling`, `move --workspace 3` |
| 4〜9 | 空き。そのとき開いた窓を置く | なし |

- ルールは窓ごとに一度だけ動く。あとは `Win+Shift+N` で自由に動かせる。
- Brave の PWA (Discord のショートカットなど) も `brave.exe` なので slot 2 に入る。
- WezTerm は `window_decorations = "RESIZE"` のせいで GlazeWM から「サイズを変え
  られない窓」に見え、そのままだとフローティングになる。`set-tiling` でタイル
  表示に戻している。
- ゲームはボーダーレスウィンドウで動かし、GlazeWM の管理下で全画面にする。
  `ignore` にするとワークスペースの木から外れ、`Win+1` が空のワークスペースを
  開くことになる。

### ゲームを足す

1. ゲームを起動し、WSL で実行ファイル名を調べる。

   ```bash
   '/mnt/c/Program Files/glzr.io/GlazeWM/cli/glazewm.exe' query windows | jq -r '.data.windows[] | "\(.processName)\t\(.title)"'
   ```

   タスクマネージャーの「詳細」タブに出る名前から `.exe` を除いたものでもよい。
2. `dot_glzr/glazewm/config.yaml` の slot 1 のルールに 1 行足す。

   ```yaml
         - window_process: { equals: 'NewGame' }
   ```

3. `chezmoi apply` する。すでに開いている窓にはルールが効かないので、ゲームを
   起動し直す。

## ウィンドウピッカー (`Win+Space`)

すべてのワークスペースの窓を一覧にして、選んだ窓とそのワークスペースを表示する。

- 入力すると絞り込む。空白で区切った語がすべて「ワークスペース番号 アプリ名
  タイトル」に順番どおり含まれる窓が残る (飛び飛びでもよい)。連続して一致する
  窓ほど上に出る。
- `↑` / `↓` で選び、`Enter` かダブルクリックで移動する。`Esc` を押すか、ほかの
  窓をクリックすると閉じる。
- ブラウザのタブは窓ではないので、ブラウザのタブ検索を使う。

PowerToys Command Palette の「Switch windows」は使えない。GlazeWM は隠した
ワークスペースの窓を cloak する (`DWMWA_CLOAKED = 2`)。Command Palette の Window
Walker は、別の仮想デスクトップにある窓を除き、cloak された窓を一覧から外す
(`OpenWindows.cs`)。そのため、`glazewm query workspaces` の結果を AutoHotkey の
GUI に並べ、選んだ窓に `glazewm command focus --container-id <id>` を実行している。
このコマンドは、隠れたワークスペースの窓でもそのワークスペースごと表示する。

## GlazeWM 3.10.1 の注意点

- `shell-exec` のプログラムのパスを `"` で囲むと失敗する
  (`command doesn't have an ending "`)。パスは囲まずに書く。スペースを含んでいても、
  GlazeWM が単語を 1 つずつ足しながら実在するファイルを探す。引数は囲んでよい。
- tmux の `C-f M-1`〜`M-5` (レイアウト切り替え) は、WezTerm が `Alt+数字` を
  タブ切り替えに使うので届かない。`C-f Space` を使う。
````

- [ ] **Step 2: Update `docs/current-state.md`**

Change line 3 to `Last updated: 2026-11-22`. After line 20 (`- Managed WezTerm config: …`) add:

```markdown
- Managed GlazeWM config and `Win+Space` AutoHotkey window picker for the Windows host, copied to `%USERPROFILE%\.glzr\glazewm\` from WSL (`docs/window-manager-windows.md`)
```

After line 127 (`- run_onchange_after_35-install-windows-wezterm-config.sh.tmpl …`) add:

```markdown
- `run_onchange_after_36-install-windows-glazewm-config.sh.tmpl` (WSL, copies the GlazeWM config and window picker to the Windows host, reloads GlazeWM, and reports missing host setup)
```

- [ ] **Step 3: Correct the spec for Windows**

In `docs/superpowers/specs/2026-11-21-window-manager-design.md`:

Replace the Non-goals line

```markdown
- Multi-monitor rules. Revisit once the single-display setup works.
```

with

```markdown
- Multi-monitor rules. Revisit once the single-display setup works. The
  Windows host has a second, portrait display: its slots 1–9 stay on the main
  display and the portrait display gets workspace 0 (`Mod+0`), on Windows only
  (`docs/window-manager-windows.md`).
```

In the Start-menu bullet, replace

```markdown
  Start. Check this first on Windows. If it reproduces, the Windows setup adds
  AutoHotkey and that script.
```

with

```markdown
  Start. Checked on Windows 11 25H2 with GlazeWM 3.10.1: a fast `Win+2` tap
  switches workspace and leaves Start closed (mashing can flash Start for a
  moment), so the Windows setup adds no mask key.
```

Replace the `Win+Space` bullet

```markdown
- Windows: `Win+Space` switches input languages. If that is in use, bind the
  picker to another key.
```

with

```markdown
- Windows: `Win+Space` switches input languages. GlazeWM's `lwin+space`
  binding takes it over (checked: the input language no longer changes), so
  input switching moves to `Win+Ctrl+Space`. GlazeWM passes that through,
  because a binding does not match while extra modifiers are held.
```

In the Window picker table, replace the Windows row

```markdown
| Windows | PowerToys Command Palette "Switch windows", or Raycast "Switch Windows" | `glazewm query windows`, pick one, `glazewm command focus --container-id <id>` |
```

with

```markdown
| Windows | AutoHotkey list of `glazewm query workspaces`; Enter runs `glazewm command focus --container-id <id>` (`dot_glzr/glazewm/window-picker.ahk`) | — |
```

and replace the paragraph after the table

```markdown
On Windows and macOS the window manager hides windows on other workspaces:
GlazeWM cloaks them, and AeroSpace moves them to a screen corner. It is
unverified whether the launcher pickers list those windows and switch
workspace on selection. Test that first and use the fallback if they do not.
```

with

```markdown
On Windows and macOS the window manager hides windows on other workspaces:
GlazeWM cloaks them, and AeroSpace moves them to a screen corner. On Windows,
PowerToys Command Palette's "Switch windows" does not list cloaked windows
unless another virtual desktop cloaked them (`OpenWindows.cs`), so Windows
lists `glazewm query workspaces` itself. It is unverified whether macOS
launchers list windows AeroSpace moved to a corner and switch workspace on
selection. Test that first and use the fallback if they do not.
```

In Repository layout, replace

```markdown
- Windows: keep the GlazeWM config in the source tree, ignored by chezmoi, and
```

with

```markdown
- Windows: keep the GlazeWM config and the window picker in
  `dot_glzr/glazewm/`, ignored by chezmoi unless the OS is `windows`, and
```

- [ ] **Step 4: Check formatting**

Run: `prek run --all-files`
Expected: every hook `Passed` or `Skipped`.

---

### Task 6: Verify on the machine

**Files:** none.

**Interfaces:**
- Consumes: the deployed config (Task 4) and picker (Task 3).
- Produces: a pass/fail record for spec Verification scenarios 1–10 plus `Mod+0`, `Win+Ctrl+Space` and startup apps.

Give the user one scenario at a time and wait for the result. Fix failures in the repository, redeploy with the Task 4 Step 6 `execute-template` command, and rerun the scenario.

- [ ] **Step 1: Scenario 1** — `Win+3` shows WezTerm, `Win+2` shows Brave, `Win+2` again returns to WezTerm.
- [ ] **Step 2: Scenario 2** — from Brave, `Win+Shift+3` puts it next to WezTerm with focus on Brave; `Win+Shift+H` swaps the two; `Win+L` focuses WezTerm; `Win+H` back to Brave, then `Win+Shift+2` sends it back to 2.
- [ ] **Step 3: Scenario 3** — the user starts a slot 1 game: it lands on workspace 1, fullscreen and untiled on the main display; `Win+2` / `Win+1` switch while it runs.
- [ ] **Step 4: Scenario 4** — `Win+Space`, type part of the title of a window on another workspace, Enter: that window and its workspace show.
- [ ] **Step 5: Scenario 5** — `Win+5`, open an app (for example Notepad): it lands on 5; `Win+3` returns to WezTerm.
- [ ] **Step 6: Scenario 6** — in WezTerm, `Win+F` toggles fullscreen; inside it `C-f z` and `C-f Space` work.
- [ ] **Step 7: Scenario 7** — WezTerm `Alt+1..9` tabs and tmux `C-f C-h/j/k/l` still work.
- [ ] **Step 8: Scenarios 8 and 9** — `Win+L` moves focus and does not lock; a fast `Win+2` tap leaves Start closed.
- [ ] **Step 9: Windows extras** — `Win+0` focuses the portrait display and `Win+Shift+0` sends a window there; `Win+Ctrl+Space` switches ENG/JPN.
- [ ] **Step 10: Scenario 10** — after sleep and wake, `Win+2` / `Win+3` still respond.

#### Results (2026-11-22, Windows host)

| Scenario | Result |
|---|---|
| 1 `Mod+3` / `Mod+2` / `Mod+2` again | Pass |
| 2 `Mod+Shift+3`, `Mod+Shift+h`, `Mod+l`, `Mod+Shift+2` | Pass (Brave was first returned from fullscreen with `Mod+f`) |
| 3 Game on slot 1 | Pass: Overwatch landed on workspace 1, fullscreen 2560×1440 on the main display; `Mod+2` / `Mod+1` switched while it ran |
| 4 Picker to a hidden workspace | Failed, then passed after the `focus --workspace` fix (Findings); text typed before the list loads still filters |
| 5 `Mod+7` (5 was occupied), open Notepad, `Mod+3` | Pass |
| 6 `Mod+f` with `C-f z` and `C-f Space` | Pass |
| 7 WezTerm `Alt+1..9`, tmux `C-f C-h/j/k/l`, Brave shortcuts | Pass |
| 8 `Win+L` | Pass: focus moves, no lock |
| 9 Quick `Win+2` tap | Pass with `win-key-mask.ahk` (it had started opening Start; Findings) |
| Windows extras: `Mod+0`, `Mod+Shift+0`, `Win+Ctrl+Space` | Pass |
| 10 Display off/on (`display off.ps1`, twice) | Pass: workspaces, displays and windows identical to the snapshot before; no errors |
| 10 Sleep and wake | Pass after one recovery: on wake, Ctrl was stuck in some program's own key state (`GetAsyncKeyState` showed it released); sending Ctrl/Shift/Alt key-ups fixed it, then `Mod+2/3/0/Space` worked and the layout was unchanged. The user is unsure whether this predates GlazeWM; documented in `docs/window-manager-windows.md` |

---

### Task 7: Commit, PR, merge

**Files:** everything above.

- [ ] **Step 1: Run the hook suite and the chezmoi check**

Run: `prek run --all-files` and `chezmoi --source . diff --exclude scripts`
Expected: hooks pass; the diff shows only the new `run_onchange_after_36-…` script (plus any drift unrelated to this branch, which stays untouched).

- [ ] **Step 2: Commit** with the `commit` skill.
- [ ] **Step 3: Open the PR** against `main` with the verification record from Task 6, wait for checks and reviews, address them, and merge.
- [ ] **Step 4: After merge**, on this machine: pull `main` in `/home/kise/repos/dotfiles`, run `prek run --all-files` and `chezmoi diff` (Rollout 7), then remove the worktree.
