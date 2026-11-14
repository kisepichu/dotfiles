-- Shared WezTerm configuration.
--
-- Deployment:
--   * macOS: chezmoi places this at ~/.config/wezterm/wezterm.lua.
--   * Windows: WSL's WezTerm runs on the Windows host, outside chezmoi's home.
--     run_onchange_after_35-install-windows-wezterm-config.sh copies this file
--     to %USERPROFILE%\.wezterm.lua when `chezmoi apply` runs in WSL and this
--     file changed. See docs/wezterm.md for details.
--
-- The config branches on wezterm.target_triple so a single source works on
-- both macOS and Windows.

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
end

if is_windows then
	-- Launch into WSL by default on Windows. Use the first WSL domain (WezTerm
	-- keeps `wsl -l -v` order, which lists the default distro first) instead of
	-- hard-coding a distro name that differs per machine.
	local wsl_domains = wezterm.default_wsl_domains()
	if #wsl_domains > 0 then
		config.default_domain = wsl_domains[1].name
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

return config
