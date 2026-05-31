-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local should_use_osc52 = vim.env.NVIM_USE_OSC52 == "1" or vim.env.SSH_TTY ~= nil or vim.env.SSH_CONNECTION ~= nil
local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
if should_use_osc52 and ok then
  local function paste_from_unnamed()
    return { vim.split(vim.fn.getreg('"'), "\n"), vim.fn.getregtype('"') }
  end

  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    paste = {
      ["+"] = paste_from_unnamed,
      ["*"] = paste_from_unnamed,
    },
  }

  vim.opt.clipboard = "unnamedplus"
end

-- auto-session restores buffers without re-running filetype detection for the
-- buffer that was active at save time, leaving its `filetype` empty (so LSP /
-- rustaceanvim never attaches until the file is reopened). `filetype` is a
-- buffer-local option, so include `localoptions` in sessionoptions to persist
-- and restore it. See rmagatti/auto-session recommended config.
vim.opt.sessionoptions:append("localoptions")
