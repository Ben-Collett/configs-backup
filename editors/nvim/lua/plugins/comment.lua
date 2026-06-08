-- add this to your lua/plugins.lua, lua/plugins/init.lua,  or the file you keep your other plugins:
return {
  "numToStr/Comment.nvim",
  opts = {
    -- add any options here
  },
  config = function()
    local mod = require("Comment.ft")
    mod.set("toml", "#%s")
  end,
}
