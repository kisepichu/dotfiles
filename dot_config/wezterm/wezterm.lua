-- Shared WezTerm configuration.
--
-- Deployment:
--   * macOS and NixOS: chezmoi places this at ~/.config/wezterm/wezterm.lua.
--   * Windows: WSL's WezTerm runs on the Windows host, outside chezmoi's home.
--     run_onchange_after_35-install-windows-wezterm-config.sh copies this file
--     to %USERPROFILE%\.wezterm.lua when `chezmoi apply` runs in WSL and this
--     file changed. See docs/wezterm.md for details.
--
-- The config branches on wezterm.target_triple so a single source works on
-- macOS, Windows, and Linux.

local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder and wezterm.config_builder() or {}

local triple = wezterm.target_triple
local is_macos = triple:find("apple%-darwin") ~= nil
local is_windows = triple:find("windows") ~= nil

-- Appearance -----------------------------------------------------------------
config.color_scheme = "Catppuccin Mocha"
-- ComicShannsMono Nerd Font:
-- https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/ComicShannsMono.zip
config.font = wezterm.font_with_fallback({
	"ComicShannsMono Nerd Font",
	"JetBrainsMono Nerd Font",
	"HackGen Console NF",
	"Menlo",
	"Consolas",
})
config.font_size = is_macos and 13.0 or 12.0
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.window_decorations = "RESIZE"
config.window_padding = { left = 4, right = 4, top = 4, bottom = 4 }
config.adjust_window_size_when_changing_font_size = false
config.audible_bell = "Disabled"

-- Platform tweaks ------------------------------------------------------------
if is_macos then
	-- Treat the left Option key as a real Alt/Meta so tmux/nvim Meta bindings work.
	config.send_composed_key_when_left_alt_is_pressed = false
	-- Keep the macOS IME for plain / Shift-only typing, but stop it from
	-- swallowing Ctrl+Shift combos like Ctrl+Shift+Space (QuickSelect).
	config.macos_forward_to_ime_modifier_mask = "SHIFT"
	-- Use macOS native full screen for ToggleFullScreen (Option+Enter). WezTerm's
	-- own full screen sizes its notch band from NSScreen.mainScreen on every focus
	-- change without re-laying out, so with an external display the window there
	-- picked up the built-in notch after Cmd+Tab: a blank band on top and the last
	-- row pushed off screen. Native full screen leaves the notch to macOS.
	config.native_macos_fullscreen_mode = true
end

if is_windows then
	-- Launch into WSL by default on Windows. Use the first WSL domain (WezTerm
	-- keeps `wsl -l -v` order, which lists the default distro first) instead of
	-- hard-coding a distro name that differs per machine.
	local wsl_domains = wezterm.default_wsl_domains()
	if #wsl_domains > 0 then
		config.default_domain = wsl_domains[1].name
	end
	-- Once run_onchange_after_37-setup-windows-wezterm-ssh.sh has written
	-- `Host wsl` to %USERPROFILE%\.ssh\config, open WSL with WezTerm's own SSH
	-- client over localhost instead: the WSL domain runs wsl.exe under the
	-- bundled ConPTY, which predates 1.22 and drops image escape sequences
	-- (docs/wezterm.md).
	config.ssh_domains = wezterm.default_ssh_domains()
	for _, domain in ipairs(config.ssh_domains) do
		if domain.name == "SSH:wsl" and #wsl_domains > 0 then
			config.default_domain = domain.name
			-- Nothing on that path starts WSL, so start the default distro and
			-- wait until 127.0.0.1:22 answers on the Windows side (sshd, then
			-- localhostForwarding). The handler creates no panes, so WezTerm
			-- spawns the default program afterwards.
			local distro = wsl_domains[1].distribution
			wezterm.on("gui-startup", function()
				wezterm.run_child_process({ "wsl.exe", "-d", distro, "-e", "true" })
				wezterm.run_child_process({
					"powershell.exe",
					"-NoProfile",
					"-NonInteractive",
					"-Command",
					"$deadline = (Get-Date).AddSeconds(15); while ((Get-Date) -lt $deadline) { $c = New-Object Net.Sockets.TcpClient; try { $c.Connect('127.0.0.1', 22); exit 0 } catch { Start-Sleep -Milliseconds 200 } finally { $c.Dispose() } }; exit 1",
				})
			end)
		end
	end
end

-- QuickSelect ----------------------------------------------------------------
-- User patterns are tried before WezTerm's built-ins (paths, hashes, UUIDs,
-- IPs, ... stay enabled). The built-in URL pattern is `scheme://\S+`, which
-- swallows a closing `)` / trailing punctuation and runs into adjacent
-- Japanese text. This one keeps ASCII URL characters only, allows balanced
-- `(...)` inside the URL (Wikipedia-style), and never ends on `.,;:!?`.
-- Non-capturing groups only: QuickSelect copies the last matching capture.
local url_chars = [[A-Za-z0-9\-._~:/?#@!$&*+,;=%]]
local url_last_chars = [[A-Za-z0-9\-_~/#@$&*+=%]]
local url_parens = [[\([]] .. url_chars .. [[]*\)]]
config.quick_select_patterns = {
	"(?:(?:https?|ftp|file|ssh|git)://|git@)(?:["
		.. url_chars
		.. "]|"
		.. url_parens
		.. ")*(?:["
		.. url_last_chars
		.. "]|"
		.. url_parens
		.. ")",
}

-- Key bindings ---------------------------------------------------------------
-- Ctrl+Arrow is intentionally NOT bound here: WezTerm forwards the default CSI
-- sequences to the terminal so tmux (prefix C-f then C-Arrow) can swap panes.
-- On macOS this also requires disabling Mission Control's Ctrl+Left/Right space
-- switching; see scripts/configure-macos-defaults.sh.
--
-- QuickSelect is bound to F13 (not Ctrl+Shift+Space) because on macOS 26 the
-- HIToolbox input-source picker hard-consumes Ctrl+Shift+Space as "cycle
-- backwards" whenever the Ctrl+Space picker was recently active, and there is
-- no exposed setting to disable it. Karabiner translates the ergonomic
-- fn+Shift+Space chord to F13 on macOS; see docs/wezterm.md.
config.keys = {
	-- QuickSelect: quickly select/copy on-screen text (URLs, hashes, paths).
	{ key = "F13", action = act.QuickSelect },
}

if is_windows then
	-- Carried over from the previous hand-maintained Windows config.
	table.insert(config.keys, { key = "f", mods = "SHIFT|META", action = act.ToggleFullScreen })
end

if not is_macos then
	-- Tab keys on Alt, the key in Cmd's spot on a PC keyboard, matching macOS's
	-- Cmd+T / Cmd+W / Cmd+1..9 (9 is the last tab). Alt is also Meta here, so
	-- fish's Alt+T (transpose-words) and Alt+W (whatis) no longer reach the
	-- shell. Ctrl+Shift+T / W / 1..9 stay bound as WezTerm's defaults.
	table.insert(config.keys, { key = "t", mods = "ALT", action = act.SpawnTab("CurrentPaneDomain") })
	table.insert(config.keys, { key = "w", mods = "ALT", action = act.CloseCurrentTab({ confirm = true }) })
	for i = 1, 8 do
		table.insert(config.keys, { key = tostring(i), mods = "ALT", action = act.ActivateTab(i - 1) })
	end
	table.insert(config.keys, { key = "9", mods = "ALT", action = act.ActivateTab(-1) })
end

if is_macos then
	-- Cmd sits where Alt does on a PC keyboard (left of Space), and AeroSpace
	-- takes Option+j/k for window focus. Send Cmd+j/k as Alt+j/k so Neovim's
	-- line moves (LazyVim <A-j>/<A-k>) keep the finger motion of Alt+j/k on
	-- Windows. Cmd+K loses WezTerm's ClearScrollback; tmux keeps its history.
	table.insert(config.keys, { key = "j", mods = "SUPER", action = act.SendKey({ key = "j", mods = "ALT" }) })
	table.insert(config.keys, { key = "k", mods = "SUPER", action = act.SendKey({ key = "k", mods = "ALT" }) })
end

return config
