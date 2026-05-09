vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

vim.opt.whichwrap:append("h")
vim.opt.whichwrap:append("l")

vim.keymap.set("n", "0", "g0", { silent = true })
vim.keymap.set("n", "$", "g$", { silent = true })

vim.keymap.set("n", "Y", "y$")

vim.keymap.set("n", "x", '"_d')
vim.keymap.set("n", "X", '"_D')
vim.keymap.set("x", "x", '"_x')
vim.keymap.set("o", "x", "d")

vim.keymap.set("o", "i<space>", "iW")
vim.keymap.set("x", "i<space>", "iW")

vim.keymap.set("n", "U", "<c-r>")
vim.keymap.set("n", "M", "%")

vim.keymap.set("x", "p", '"_dP', { noremap = true, silent = true, desc = "Paste without overwriting unnamed register" })
vim.keymap.set("x", "P", '"_dP', { noremap = true, silent = true, desc = "Paste without overwriting unnamed register" })

vim.keymap.set("x", "y", "mzy`z", { silent = true })

-- q prefix
vim.keymap.set("n", "<leader>qq", "qq", { silent = true })

vim.keymap.set("n", "Q", function()
  if vim.fn.reg_recording() == "" then
    return "@q"
  end
  return "q@q"
end, { expr = true, silent = true })

vim.keymap.set("n", "<leader>qg", ":<C-u>global/^/normal ", { silent = true })

vim.keymap.set("x", "qg", ":global/^/normal ", { silent = true })
vim.keymap.set("n", "<leader>qu", ":lua require'quarto'.quartoPreview()<cr>", { silent = true, desc = "quarto preview" })

-- plugins

vim.keymap.set({ "i", "n" }, "[j", "<Plug>(jumpcursor-jump)", { remap = true })

vim.keymap.set("i", "<C-j>", "<Plug>(skkeleton-toggle)", { remap = true })
vim.keymap.set("n", "<C-j>", "<Plug>(skkeleton-toggle)", { remap = true })
