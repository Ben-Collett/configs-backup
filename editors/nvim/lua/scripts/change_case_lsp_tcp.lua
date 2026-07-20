-- vim.lsp.set_log_level("debug")
-- vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
--   callback = function(args)
--     if vim.fn.filereadable(args.file) == 1 then
--       -- @diagnostic disable-next-line: missing-fields
--       vim.lsp.start({
--         name = "change_case_lsp",
--         root_dir = vim.fs.dirname(args.file),
--         cmd = function()
--           local tcp = vim.uv.new_tcp()
--           vim.uv.tcp_connect(tcp, "127.0.0.1", 5050, function(err)
--             if err then
--               vim.notify("change_case_lsp TCP connection failed: " .. tostring(err), vim.log.levels.ERROR)
--               tcp:close()
--             end
--           end)
--           return tcp
--         end,
--       })
--     end
--   end,
-- })
--
vim.lsp.set_log_level("debug")

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  callback = function(args)
    if vim.fn.filereadable(args.file) == 1 then
      -- @diagnostic disable-next-line: missing-fields
      vim.lsp.start({
        name = "change_case_lsp",
        cmd = vim.lsp.rpc.connect("127.0.0.1", 5050),
        root_dir = vim.fs.dirname(args.file),
      })
    end
  end,
})
