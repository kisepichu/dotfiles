if vim.g.started_by_firenvim then
  return {}
end

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {},
    config = function(_, opts)
      local rm = require("render-markdown")
      rm.setup(opts)

      vim.api.nvim_create_autocmd("FileType", {
        pattern = "markdown",
        callback = function(args)
          local lines = vim.api.nvim_buf_line_count(args.buf)
          if lines > 100 then
            -- disable for this buffer (plugin provides buffer-local enable/disable)
            pcall(rm.disable, args.buf)
          end
        end,
      })
    end,
  },
  "OXY2DEV/markdoc.nvim",
}
