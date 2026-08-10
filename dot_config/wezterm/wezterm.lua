-- Shared WezTerm configuration.
--
-- Deployment:
--   * macOS: chezmoi places this at ~/.config/wezterm/wezterm.lua.
--   * Windows: WSL's WezTerm runs on the Windows host, which chezmoi (running
--     inside WSL/macOS home) cannot reach. Copy or point a Windows-side
--     ~/.wezterm.lua / ~/.config/wezterm/wezterm.lua at this file.
--     See docs/wezterm.md for details.
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
config.font_size = is_macos and 13.0 or 11.0
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
	-- Launch into WSL by default on Windows.
	config.default_domain = "WSL:Ubuntu"
end

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

return config
