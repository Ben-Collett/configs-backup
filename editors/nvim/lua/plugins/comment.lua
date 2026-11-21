-- add this to your lua/plugins.lua, lua/plugins/init.lua,  or the file you keep your other plugins:
return {
  "numToStr/Comment.nvim",
  opts = {
    -- Comment.nvim looks the commentstring up through treesitter first. JSONC
    -- maps to the `json` parser, and without that parser installed the lookup
    -- fails silently, so gc/gcc do nothing. Return the commentstring directly
    -- for jsonc so commenting works even if the parser is missing.
    pre_hook = function()
      if vim.bo.filetype == "jsonc" then
        return "//%s"
      end
    end,
  },
  config = function()
    local mod = require("Comment.ft")
    mod.set("toml", "#%s")
    mod.set("jsonc", "//%s")
  end,
}
