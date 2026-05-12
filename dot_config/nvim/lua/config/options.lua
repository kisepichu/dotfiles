-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
if ok then
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
