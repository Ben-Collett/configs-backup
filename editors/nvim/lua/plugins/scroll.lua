return {
  "josstei/whisk.nvim",

  -- `plugin/whisk.vim` ends with `if g:whisk_auto_setup | lua require('whisk').setup() | endif`,
  -- and it is sourced by lazy's `packadd` *before* the `config` below gets a
  -- say. That self-setup takes no arguments, so it runs on whisk's defaults --
  -- `keymaps = { cursor = true, scroll = true }` -- and creates mappings for
  -- `<C-b>`, `<C-d>`, `<C-f>`, `<C-u>`, `zz` and friends. The `whisk.setup` in
  -- `config` then opens by clearing every key the motion registry lists, which
  -- reaches across and takes `plugins/dap.lua`'s `<C-b>` down with it.
  --
  -- Opting out of the auto-setup is what stops either half from happening: the
  -- only setup that ever runs is the one in `config`, with these opts.
  init = function()
    vim.g.whisk_auto_setup = 0
  end,

  opts = {
    cursor = {
      duration = 150,
      easing = "ease-out",
      enabled = true,
    },
    scroll = {
      duration = 200,
      easing = "ease-in-out",
      enabled = true,
    },
    -- `scroll = false` keeps whisk from *creating* the scroll keymaps. Left on,
    -- it claims `<C-b>`, `<C-d>`, `<C-f>`, `<C-u>`, `zz`, `zt` and `zb` -- and
    -- because `whisk.disable()` below turns the animations off, each of those
    -- becomes a handler that returns immediately, swallowing vim's own
    -- behaviour rather than adding to it. `<C-b>` and `<C-d>` in particular
    -- belong to `plugins/dap.lua`, for breakpoints and continue.
    --
    -- Nothing is lost: the motion keys below are wired to the orchestrator by
    -- hand, so they stay smooth whenever whisk is toggled on with `<leader>sc`.
    keymaps = {
      cursor = false,
      scroll = false,
    },
  },
  config = function(_, opts)
    local whisk = require("whisk")

    -- Both keymap categories are off, so whisk creates no keymaps of its own.
    -- `whisk.setup` still opens by running `keymaps.clear`, which deletes every
    -- key each *registered motion* lists whether or not whisk ever created it
    -- -- and `scroll_ctrl_b` still lists `<C-b>`. Harmless on the first load,
    -- since the registry is empty, but on a `:Lazy reload whisk` (<leader>rl)
    -- it would delete dap's breakpoint mapping again, and nothing here sets it
    -- back. Whisk owns nothing to clear, so make clear a no-op.
    require("whisk.registry.keymaps").clear = function() end

    whisk.setup(opts)
    whisk.disable()
    vim.keymap.set("n", "<leader>sc", whisk.toggle)

    local orchestrator = require("whisk.engine.orchestrator")

    local normal_motions = {
      { key = "h", id = "basic_h" },
      { key = "j", id = "basic_j" },
      { key = "k", id = "basic_k" },
      { key = "l", id = "basic_l" },
      { key = "0", id = "basic_0" },
      { key = "$", id = "basic_$" },
      { key = "gg", id = "line_gg" },
      { key = "go", id = "line_gg" },
      { key = "G", id = "line_G" },
      { key = "|", id = "line_|" },
    }
    for _, m in ipairs(normal_motions) do
      vim.keymap.set("n", m.key, function()
        orchestrator.execute(m.id, { count = vim.v.count1, direction = m.key })
      end)
    end

    local visual_motions = {
      { key = "h", id = "basic_h" },
      { key = "j", id = "basic_j" },
      { key = "k", id = "basic_k" },
      { key = "l", id = "basic_l" },
      { key = "0", id = "basic_0" },
      { key = "$", id = "basic_$" },
    }
    for _, m in ipairs(visual_motions) do
      vim.keymap.set("v", m.key, function()
        orchestrator.execute(m.id, { count = vim.v.count1, direction = m.key })
      end)
    end
  end,
}
