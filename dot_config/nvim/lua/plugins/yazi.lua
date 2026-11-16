-- yazi as a floating file manager; neo-tree stays the sidebar (<leader>e).
-- Like LazyVim's <leader>fe / <leader>fE, lowercase starts near the buffer and
-- uppercase starts at the cwd. Images do not preview here: Neovim's terminal
-- has no graphics protocol, so use `y` in the shell for that.
return {
  {
    "mikavilpas/yazi.nvim",
    version = "*",
    cmd = "Yazi",
    keys = {
      { "<leader>fy", mode = { "n", "v" }, "<cmd>Yazi<cr>", desc = "Yazi (current file)" },
      { "<leader>fY", "<cmd>Yazi cwd<cr>", desc = "Yazi (cwd)" },
    },
    opts = {},
  },
}
