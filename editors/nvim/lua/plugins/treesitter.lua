return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  build = ":TSUpdate",
  branch = "main",
  opts = {
    auto_install = true,
    -- rust/cpp/c are needed for dap virtual text to place inline values.
    ensure_installed = {
      "diff",
      "lua",
      "python",
      "toml",
      "regex",
      "luadoc",
      "nu",
      "vim",
      "dart",
      "comment",
      "rust",
      "cpp",
      "c",
    },
    indent = { enable = true },
  },
  config = function(_, opts)
    require("nvim-treesitter").setup(opts)

    vim.api.nvim_create_autocmd("FileType", {
      callback = function(args)
        pcall(vim.treesitter.start, args.buf)
      end,
    })
  end,
}
