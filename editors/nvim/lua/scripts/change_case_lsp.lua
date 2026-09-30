-- Registered as an lsp config rather than started by hand, so the name reaches
-- `vim.lsp._enabled_configs` and can be enabled/disabled like any other server.
-- vim.lsp.set_log_level("debug")
vim.lsp.config("change_case_lsp", {
  cmd = { "/home/ben/Documents/my_shit/lsp/dart/change_case_lsp/bin/change_case_lsp.exe" },
  -- No `filetypes`: nvim treats a nil filetypes as "applies to every buffer",
  -- which is what the old BufRead autocmd did.
  workspace_required = true,
  root_dir = function(bufnr, on_dir)
    local file = vim.api.nvim_buf_get_name(bufnr)
    if vim.fn.filereadable(file) == 1 then
      on_dir(vim.fs.dirname(file))
    else
      on_dir(nil)
    end
  end,
})

vim.lsp.enable("change_case_lsp")
