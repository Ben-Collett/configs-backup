-- vim.lsp.set_log_level("debug")
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  callback = function(args)
    if vim.fn.filereadable(args.file) == 1 then
      -- @diagnostic disable-next-line: missing-fields
      vim.lsp.start({
        name = "change_case_lsp",
        cmd = { "/home/ben/Documents/my_shit/lsp/dart/change_case_lsp/bin/change_case_lsp.exe" },
        root_dir = vim.fs.dirname(args.file),
      })
    end
  end,
})
