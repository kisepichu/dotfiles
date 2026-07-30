vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })

vim.opt.whichwrap:append("h")
vim.opt.whichwrap:append("l")

vim.keymap.set("n", "0", "g0", { silent = true })
vim.keymap.set("n", "$", "g$", { silent = true })

vim.keymap.set("n", "Y", "y$")

vim.keymap.set("n", "x", '"_x')
vim.keymap.set("n", "X", '"_X')
vim.keymap.set("x", "x", '"_x')

vim.keymap.set("o", "i<space>", "iW")
vim.keymap.set("x", "i<space>", "iW")

vim.keymap.set("n", "U", "<c-r>")
vim.keymap.set("n", "M", "%")

vim.keymap.set("x", "p", '"_dP', { noremap = true, silent = true, desc = "Paste without overwriting unnamed register" })
vim.keymap.set("x", "P", '"_dP', { noremap = true, silent = true, desc = "Paste without overwriting unnamed register" })

vim.keymap.set("x", "y", "mzy`z", { silent = true })

local function paste_markdown()
  local script = [=[
    osascript -e 'try' -e 'return the clipboard as «class HTML»' -e 'end try' \
      | perl -ne 'if (/«data HTML([0-9A-Fa-f]+)»/) { print pack("H*", $1) }' \
      | pandoc -f html -t gfm-raw_html --wrap=none
  ]=]
  local md = vim.fn.system(script)
  if vim.v.shell_error ~= 0 or vim.trim(md) == "" then
    vim.notify("PasteMarkdown: no HTML on clipboard, falling back to plain paste", vim.log.levels.INFO)
    vim.cmd('normal! "+p')
    return
  end
  local lines = vim.split(vim.trim(md), "\n", { plain = true })
  vim.api.nvim_put(lines, "c", true, true)
end

vim.api.nvim_create_user_command("PasteMarkdown", paste_markdown, { desc = "Paste clipboard HTML converted to Markdown" })
vim.keymap.set("n", "<leader>pm", paste_markdown, { silent = true, desc = "Paste HTML clipboard as Markdown" })

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
