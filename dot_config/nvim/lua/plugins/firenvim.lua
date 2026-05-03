-- lua/plugins/firenvim-disable.lua
if not vim.g.started_by_firenvim then
  return {}
end

return {
  { "gbprod/yanky.nvim", enabled = false },

  { "folke/noice.nvim", enabled = false },
  { "nvim-lualine/lualine.nvim", enabled = false },
  { "akinsho/bufferline.nvim", enabled = false },
  { "folke/todo-comments.nvim", enabled = false },
  { "folke/trouble.nvim", enabled = false },
  { "folke/which-key.nvim", enabled = false },

  { "lewis6991/gitsigns.nvim", enabled = false },

  { "neovim/nvim-lspconfig", enabled = false },
  { "williamboman/mason.nvim", enabled = false },
  { "williamboman/mason-lspconfig.nvim", enabled = false },
  { "mfussenegger/nvim-lint", enabled = false },

  { "nvim-treesitter/nvim-treesitter", enabled = false },
  { "nvim-treesitter/nvim-treesitter-textobjects", enabled = false },
  { "windwp/nvim-ts-autotag", enabled = false },
  { "folke/ts-comments.nvim", enabled = false },

  { "lervag/vimtex", enabled = false },
}
