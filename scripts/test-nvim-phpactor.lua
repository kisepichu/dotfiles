local repo_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local project_dir = vim.fn.tempname()
local outside_dir = vim.fn.tempname()
local original_dir = vim.fn.getcwd()
vim.fn.mkdir(project_dir .. "/src", "p")
vim.fn.mkdir(outside_dir, "p")
vim.fn.writefile({ "{}" }, project_dir .. "/composer.json")
vim.fn.chdir(project_dir)

local function server(dispatchers)
  local closing = false
  return {
    request = function(method, _, callback)
      vim.schedule(function()
        if method == "initialize" then
          callback(nil, { capabilities = { textDocumentSync = 1 } })
        else
          callback(nil, nil)
        end
      end)
      return true, 1
    end,
    notify = function(method)
      if method == "exit" then
        closing = true
        dispatchers.on_exit(0, 0)
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = function()
      closing = true
      dispatchers.on_exit(0, 0)
    end,
  }
end

vim.lsp.config("phpactor", {
  cmd = server,
  filetypes = { "php" },
  root_markers = { "composer.json" },
  workspace_required = true,
})
for _, spec in ipairs(dofile(repo_dir .. "/dot_config/nvim/lua/plugins/general.lua")) do
  if type(spec) == "table" and spec[1] == "neovim/nvim-lspconfig" then
    vim.lsp.config("phpactor", spec.opts.servers.phpactor)
  end
end
vim.lsp.enable("phpactor")

local function open_php(name, buftype, diff)
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.bo[bufnr].buftype = buftype or ""
  vim.api.nvim_set_current_buf(bufnr)
  vim.wo.diff = diff or false
  vim.bo[bufnr].filetype = "php"
  return bufnr
end

local function assert_attached(bufnr, description)
  assert(
    vim.wait(2000, function()
      local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "phpactor" })
      return #clients == 1 and clients[1].initialized
    end),
    description .. ": phpactor did not attach"
  )
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "phpactor" })[1]
  assert(
    vim.uv.fs_realpath(client.config.root_dir) == vim.uv.fs_realpath(project_dir),
    description .. ": wrong workspace root"
  )
  print("PASS: " .. description)
end

local function assert_excluded(bufnr, description)
  local attached = vim.wait(200, function()
    return #vim.lsp.get_clients({ bufnr = bufnr, name = "phpactor" }) > 0
  end)
  assert(not attached, description .. ": phpactor attached to an excluded buffer")
  print("PASS: " .. description)
end

local ok, err = xpcall(function()
  assert_attached(open_php(project_dir .. "/src/normal.php"), "normal PHP file attaches")
  assert_excluded(
    open_php("diffview://" .. project_dir .. "/.git/:0:/src/index.php"),
    "editable Diffview index buffer is excluded"
  )
  assert_excluded(
    open_php("diffview://" .. project_dir .. "/.git/abcdef/src/commit.php", "nowrite"),
    "read-only Diffview commit buffer is excluded"
  )
  assert_attached(open_php(project_dir .. "/src/local.php", "", true), "real PHP file in a diff window still attaches")
  assert_excluded(open_php(outside_dir .. "/outside.php"), "PHP file without a workspace is excluded")
end, debug.traceback)

vim.lsp.enable("phpactor", false)
vim.wait(2000, function()
  return #vim.lsp.get_clients() == 0
end)
vim.fn.chdir(original_dir)
vim.fn.delete(project_dir, "rf")
vim.fn.delete(outside_dir, "rf")
if not ok then
  error(err)
end
