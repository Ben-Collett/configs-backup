vim.opt.undofile = true
vim.opt.termguicolors = true
vim.cmd("syntax enable")
require("config.keymaps")
require("config.lazy")
--also has keymaps
require("scripts.load_scripts")

require("config.style")
vim.filetype.add({
  extension = {
    obf = "json",
  },
})

function HighlightSelection()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local lines = vim.fn.getline(start_pos[2], end_pos[2])

  if #lines == 0 then
    return
  end

  lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
  lines[1] = string.sub(lines[1], start_pos[3])

  local text = table.concat(lines, "\n")
  vim.fn.matchadd("IncSearch", vim.fn.escape(text, "\\/.*$^~[]"))
end

vim.keymap.set("v", "<leader>h", HighlightSelection)
-- vim.api.nvim_create_autocmd("UIEnter", {
--   callback = function()
--     print("hi")
--   end,
-- })
-- vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"

vim.g.python_indent = {
  disable_parentheses_indenting = 1,
}
