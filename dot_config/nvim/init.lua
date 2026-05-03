-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")

if vim.g.started_by_firenvim == true then
  -- 一般的なウェブ入力欄に近づける設定
  vim.opt.signcolumn = "no"
  vim.opt.laststatus = 0
  vim.opt.cursorline = false
  vim.opt.number = false
  vim.opt.fillchars:append({ eob = " " })

  -- 必要に応じてカラースキームやStatuslineも調整
  vim.g.ministatusline_disable = true -- 例: mini.nvimのステータスラインを無効化
end

-- Firenvim: ensure nvim has a valid servername (workaround for EINVAL in pipe_connect)
if vim.g.started_by_firenvim then
  if (vim.v.servername == nil) or (vim.v.servername == "") then
    local addr = string.format("/tmp/nvim-firenvim-%d.sock", vim.fn.getpid())
    vim.fn.serverstart(addr)
  end
end

-- soft wrap
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.showbreak = "↪ "

vim.opt.foldmethod = "expr"
vim.o.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.o.foldlevel = 99
vim.o.foldenable = true
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "markdown", "quarto" },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})
