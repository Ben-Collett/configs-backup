return {
  dir = "/home/ben/Documents/nvim_plugins/mason_controller",
  dependencies = { "MunifTanjim/nui.nvim" },
  cmd = { "MasonController", "LspController" },
  keys = {
    { "<leader>mc", "<cmd>MasonController<cr>", desc = "Mason controller" },
  },
  config = function()
    require("mason_controller").setup()
  end,
}
