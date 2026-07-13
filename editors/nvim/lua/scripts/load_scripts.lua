-- ~/.config/nvim/lua/scripts/load_scripts.lua
require("scripts.change_case_lsp")
local replace_word = require("scripts.replace_word")


-- Use Lua function callback for keymap
vim.keymap.set(
  "n", -- normal mode
  "<leader>rp", -- your shortcut
  replace_word.replace_under_cursor, -- directly call the function
  { noremap = true, silent = true, desc = "Replace word under cursor" }
)
