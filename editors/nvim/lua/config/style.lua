local opt = vim.opt

opt.relativenumber = true
opt.number = true

opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.autoindent = true

opt.wrap = false

opt.ignorecase = true
opt.smartcase = true

vim.cmd("colorscheme mytheme")

--toggles the cmd height so I don't loose lua line when I enter command mode
vim.opt.cmdheight = 0
-- Create an autocommand group
local augroup = vim.api.nvim_create_augroup("CmdModeEvents", { clear = true })

-- Autocommand for entering command-line mode
vim.api.nvim_create_autocmd("CmdlineEnter", {
  group = augroup,
  pattern = "*",
  callback = function()
    vim.opt.cmdheight = 0
  end,
})

-- Autocommand for leaving command-line mode
vim.api.nvim_create_autocmd("CmdlineLeave", {
  group = augroup,
  pattern = "*",
  callback = function()
    vim.opt.cmdheight = 0
  end,
})
