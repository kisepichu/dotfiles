if vim.g.started_by_firenvim then
  return {
    {
      "catppuccin/nvim",
      name = "catppuccin",
      priority = 1000,
      lazy = false,
      config = function()
        require("catppuccin").setup({
          flavour = "macchiato",
        })
        vim.cmd.colorscheme("catppuccin")
      end,
    },
    "skanehira/jumpcursor.vim",
    {
      "kylechui/nvim-surround",
      version = "^3.0.0", -- Use for stability; omit to use `main` branch for the latest features
      config = function()
        require("nvim-surround").setup({
          -- Configuration here, or leave empty to use defaults
        })
      end,
    },
    "vim-denops/denops.vim",
    "Shougo/ddc.vim",
    {
      "vim-skk/skkeleton",
      dependencies = { "vim-denops/denops.vim", "Shougo/ddc.vim" },
      config = function()
        local global_dictionaries = {}
        if vim.fn.filereadable("/usr/share/skk/SKK-JISYO.L") == 1 then
          global_dictionaries = {
            { "/usr/share/skk/SKK-JISYO.L", "euc-jp" },
          }
        end

        vim.fn["skkeleton#config"]({
          globalDictionaries = global_dictionaries,
          userDictionary = vim.fn.stdpath("data") .. "/.skkeleton/user.dict",
          eggLikeNewline = true,
          registerConvertResult = true,
        })

        vim.fn["skkeleton#register_keymap"]("input", "<Space>", "henkanFirst")
        vim.fn["skkeleton#register_keymap"]("henkan", "<Space>", "henkanForward")
        vim.fn["skkeleton#register_keymap"]("henkan", "<CR>", "kakutei")
        vim.fn["skkeleton#register_keymap"]("henkan", "<C-g>", "cancel")
      end,
    },
    { "delphinus/skkeleton_indicator.nvim", opts = {} },
    "y3owk1n/undo-glow.nvim",
    { "glacambre/firenvim", build = ":call firenvim#install(0)" },
  }
end

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    lazy = false,
    config = function()
      require("catppuccin").setup({
        flavour = "macchiato",
      })
      vim.cmd.colorscheme("catppuccin")
    end,
  },
  {
    "kylechui/nvim-surround",
    version = "^3.0.0", -- Use for stability; omit to use `main` branch for the latest features
    -- event = "VeryLazy",
    config = function()
      require("nvim-surround").setup({
        -- Configuration here, or leave empty to use defaults
      })
    end,
  },
  "dominikduda/vim_current_word", -- highlight current word
  "jghauser/mkdir.nvim", -- mkdir -p
  {
    "nacro90/numb.nvim", -- preview the line before :num
    config = function()
      require("numb").setup({})
    end,
  },
  "nvim-tree/nvim-web-devicons",
  "nvim-lua/plenary.nvim",
  {
    "ysmb-wtsg/in-and-out.nvim",
    keys = {
      {
        "<C-CR>",
        function()
          require("in-and-out").in_and_out()
        end,
        mode = "i",
      },
    },
    opts = {},
  },
  "vim-denops/denops.vim",
  "Shougo/ddc.vim",
  "skanehira/jumpcursor.vim",
  -- "cohama/lexima.vim",
  -- "windwp/nvim-ts-autotag",
  "tpope/vim-fugitive",
  "lewis6991/gitsigns.nvim",
  "neovim/nvim-lspconfig",
  "lukas-reineke/lsp-format.nvim",
  "lambdalisue/vim-kensaku",
  "lambdalisue/vim-kensaku-search",
  "yuki-yano/fuzzy-motion.vim",
  {
    "vim-skk/skkeleton",
    dependencies = { "vim-denops/denops.vim", "Shougo/ddc.vim" },
    config = function()
      local global_dictionaries = {}
      if vim.fn.filereadable("/usr/share/skk/SKK-JISYO.L") == 1 then
        global_dictionaries = {
          { "/usr/share/skk/SKK-JISYO.L", "euc-jp" },
        }
      end

      vim.fn["skkeleton#config"]({
        globalDictionaries = global_dictionaries,
        userDictionary = vim.fn.stdpath("data") .. "/.skkeleton/user.dict",
        eggLikeNewline = true,
        registerConvertResult = true,
      })

      vim.fn["skkeleton#register_keymap"]("input", "<Space>", "henkanFirst")
      vim.fn["skkeleton#register_keymap"]("henkan", "<Space>", "henkanForward")
      vim.fn["skkeleton#register_keymap"]("henkan", "<CR>", "kakutei")
      vim.fn["skkeleton#register_keymap"]("henkan", "<C-g>", "cancel")
    end,
    --
  },
  {
    "rmagatti/auto-session",
    config = function()
      require("auto-session").setup({
        auto_restore_enabled = true,
        auto_save_enabled = true,
      })
    end,
  },
  { "delphinus/skkeleton_indicator.nvim", opts = {} },
  "haya14busa/vim-edgemotion",
  "haya14busa/vim-asterisk",
  "nvim-lualine/lualine.nvim",
  "SmiteshP/nvim-navic",
  "pnx/lualine-lsp-status",
  "akinsho/bufferline.nvim",
  "rcarriga/nvim-notify",
  "j-hui/fidget.nvim",
  "matsui54/denops-popup-preview.vim",
  "matsui54/denops-signature_help",
  "shellRaining/hlchunk.nvim",
  "rafamadriz/friendly-snippets",
  "unblevable/quick-scope",
  "m-demare/hlargs.nvim",
  "chentoast/marks.nvim",
  "andersevenrud/nvim_context_vt",
  "y3owk1n/undo-glow.nvim",
  "emmanueltouzery/key-menu.nvim",
  "kevinhwang91/nvim-ufo",
  { "glacambre/firenvim", build = ":call firenvim#install(0)" },
  "tacroe/unite-mark",
  "djoshea/vim-autoread",
  "sindrets/diffview.nvim",
  {
    "rmagatti/goto-preview",
    dependencies = { "rmagatti/logger.nvim" },
    event = "BufEnter",
    config = function()
      require("goto-preview").setup({
        default_mappings = true,
      })
    end,
  },
}
