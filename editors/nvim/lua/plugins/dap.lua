-- Debugger support for Python, C/C++, Rust and Dart/Flutter.
--
-- Everything dap-related lives in this one spec: the mason installs, the
-- adapters, the per-language configurations, the dapui panels, virtual text,
-- and the keymaps.
--
-- The keymaps sit in `keys` rather than in `config` so that nothing here loads
-- until a debug key is pressed. That is also why every callback `require`s what
-- it needs: `keys` is evaluated at startup, before dap is loaded.
--
-- `<leader>d` and `<leader>D` are already spoken for -- `config/keymaps.lua`
-- maps them to `"_d`/`"_D`, and `plugins/lsp/lspconfig.lua` remaps them to
-- diagnostic actions inside LSP buffers -- so the dap group is two keys wide.
-- `<C-s>` (step into) and `<C-c>` (run to cursor) are dropped as normal-mode
-- mappings because they collide with paste/save and interrupt; both actions
-- stay reachable as `<leader>di` and `<leader>dl`.
--
-- `<C-b>` (breakpoint) and `<C-d>` (continue) are dropped for the same kind of
-- reason: `plugins/scroll.lua` gives whisk.nvim its scroll keymaps, and whisk
-- registers after lazy.nvim, so a mapping here would be silently overwritten.
-- Use `<leader>db` and `<leader>dc` instead.

--- Prompt for a value, returning nil if the user cancels or enters nothing.
---@param prompt string
---@return string|nil
local function ask(prompt)
  local value = vim.fn.input({ prompt = prompt })
  if value == nil or value == "" then
    return nil
  end
  return value
end

--- The breakpoint sitting on the current line, if any.
--- nvim-dap only tracks conditions and log messages locally (in signs), so
--- this is the only way to read one back before a session exists.
---@return { line: integer, condition: string?, logMessage: string? }|nil
local function breakpoint_here()
  local ok, breakpoints = pcall(require, "dap.breakpoints")
  if not ok then
    return nil
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  for _, bp in ipairs(breakpoints.get(bufnr)[bufnr] or {}) do
    if bp.line == line then
      return bp
    end
  end
  return nil
end

--- Set a condition or log message on the current line, or clear the line if it
--- already carries one. `set` receives the argument to pass to
--- `dap.toggle_breakpoint` as its third position, so both callers share the
--- clearing and replacing logic.
---@param kind "condition"|"log_message"
local function toggle_breakpoint_with(kind)
  local prompt = kind == "condition" and "Breakpoint condition: " or "Log message: "
  local value = ask(prompt)
  if not value then
    return
  end
  local existing = breakpoint_here()
  local dap = require("dap")
  if existing and (existing.condition or existing.logMessage) then
    -- Already conditional or logging here; toggle it off rather than stack a
    -- second breakpoint on the same line.
    dap.toggle_breakpoint()
  elseif kind == "condition" then
    -- replace_old so a plain breakpoint on this line becomes conditional.
    dap.toggle_breakpoint(value, nil, nil, true)
  else
    dap.toggle_breakpoint(nil, nil, value, true)
  end
end

-- Exception breakpoints are on by default (see `dap.defaults` in config below),
-- so the toggle starts in the on state to stay in sync with what the adapter
-- actually receives at session start.
local exception_breakpoints = true

local function toggle_exception_breakpoints()
  exception_breakpoints = not exception_breakpoints
  local dap = require("dap")
  dap.set_exception_breakpoints(exception_breakpoints and { "raised" } or {})
  vim.notify(
    exception_breakpoints and "Exception breakpoints: raised" or "Exception breakpoints: off",
    vim.log.levels.INFO,
    { title = "dap" }
  )
end

--- Adapter `type` for the current buffer, taken from its first configuration so
--- the attach-to-process map is not hardcoded to codelldb.
---@return string
local function adapter_type()
  local configs = require("dap").configurations[vim.bo.filetype] or {}
  return (configs[1] or {}).type or "codelldb"
end

--- Rust project facts for the current buffer, from the nearest Cargo.toml: the
--- binary to run, the package the test binaries are named after, and the
--- project root. `[[bin]]` name wins for the binary, `[package]` name for the
--- package; the file's own basename is the last resort for both.
---@return string bin, string package, string root
local function rust_crate()
  local file = vim.api.nvim_buf_get_name(0)
  local bin = vim.fn.fnamemodify(file, ":t:r")
  local manifest = vim.fs.find("Cargo.toml", { upward = true, path = vim.fn.fnamemodify(file, ":p:h") })[1]
  if not manifest then
    return bin, bin, vim.fn.getcwd()
  end
  local root = vim.fs.dirname(manifest)
  local package
  local in_package, in_bin = false, false
  for _, line in ipairs(vim.fn.readfile(manifest)) do
    local header = line:match("^%s*%[([^%]]+)%]%s*$")
    if header == "package" then
      in_package, in_bin = true, false
    elseif header == "bin" then
      in_package, in_bin = false, true
    elseif header then
      in_package, in_bin = false, false
    elseif line:match("^%s*%[%[bin%]%]%s*$") then
      in_package, in_bin = false, true
    else
      local declared = line:match('^%s*name%s*=%s*"([^"]+)"')
      if declared and in_bin then
        bin = declared
      elseif declared and in_package then
        package = declared
      end
    end
  end
  return bin, package or bin, root
end

--- Newest test binary cargo has built for `package`, if there is one. cargo
--- names these `<package>-<hash>`, independent of any `[[bin]]` name.
---@param package string
---@param root string
---@return string|nil
local function cargo_test_binary(package, root)
  local deps = vim.fs.joinpath(root, "target", "debug", "deps")
  local best, best_mtime
  for name in vim.fs.dir(deps) do
    if name:match("^" .. vim.pesc(package) .. "%-[0-9a-f]+$") then
      local path = vim.fs.joinpath(deps, name)
      local stat = vim.uv.fs_stat(path)
      if stat and stat.type == "file" and (not best_mtime or stat.mtime.sec > best_mtime) then
        best, best_mtime = path, stat.mtime.sec
      end
    end
  end
  return best
end

return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
      "mfussenegger/nvim-dap-python",
      "nvim-neotest/nvim-nio", -- required by nvim-dap-ui
      "jay-babu/mason-nvim-dap.nvim",
    },
    keys = {
      -- These fire even with no session, in which case nvim-dap notifies
      -- instead of erroring.
      {
        "<C-j>",
        function()
          require("dap").step_over()
        end,
        desc = "Debug: Step over",
      },
      {
        "<C-k>",
        function()
          require("dap").step_back()
        end,
        desc = "Debug: Step back",
      },

      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Debug: Toggle breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dap").continue()
        end,
        desc = "Debug: Continue",
      },
      {
        "<leader>do",
        function()
          require("dap").step_over()
        end,
        desc = "Debug: Step over",
      },
      {
        "<leader>ds",
        function()
          require("dap").step_out()
        end,
        desc = "Debug: Step out",
      },
      {
        "<leader>dbk",
        function()
          require("dap").step_back()
        end,
        desc = "Debug: Step back",
      },
      {
        "<leader>di",
        function()
          require("dap").step_into()
        end,
        desc = "Debug: Step into",
      },
      {
        "<leader>dl",
        function()
          require("dap").run_to_cursor()
        end,
        desc = "Debug: Run to cursor",
      },
      {
        "<leader>dp",
        function()
          require("dap").pause()
        end,
        desc = "Debug: Pause",
      },
      {
        "<leader>dr",
        function()
          require("dap").restart()
        end,
        desc = "Debug: Restart",
      },
      {
        "<leader>dq",
        function()
          require("dap").terminate()
        end,
        desc = "Debug: Terminate",
      },

      -- `:DapNew` is the public entry point for picking a configuration; with no
      -- arguments it shows the picker, which is how `.vscode/launch.json`
      -- entries (read by the built-in `dap.launch.json` provider) get reached.
      { "<leader>dn", "<cmd>DapNew<cr>", desc = "Debug: New session" },

      {
        "<leader>dbc",
        function()
          toggle_breakpoint_with("condition")
        end,
        desc = "Debug: Conditional breakpoint",
      },
      {
        "<leader>dbl",
        function()
          toggle_breakpoint_with("log_message")
        end,
        desc = "Debug: Logpoint",
      },
      { "<leader>de", toggle_exception_breakpoints, desc = "Debug: Toggle exception breakpoints" },

      {
        "<leader>dP",
        function()
          require("dap").run({
            type = adapter_type(),
            request = "attach",
            name = "Attach to process",
            pid = require("dap.utils").pick_process,
          })
        end,
        desc = "Debug: Attach to process",
      },

      -- Built-in dap REPL, distinct from the dapui one.
      {
        "<leader>dt",
        function()
          require("dap.repl").toggle()
        end,
        desc = "Debug: Toggle dap REPL",
      },
      {
        "<leader>dd",
        function()
          require("dapui").toggle()
        end,
        desc = "Debug: Toggle panels",
      },
      {
        "<leader>duc",
        function()
          require("dapui").float_element("console")
        end,
        desc = "Debug: Float console",
      },
      -- No element name, so dapui prompts for which one to float.
      {
        "<leader>duf",
        function()
          require("dapui").float_element()
        end,
        desc = "Debug: Float element",
      },
      {
        "<leader>dsu",
        function()
          require("nvim-dap-virtual-text").toggle()
        end,
        desc = "Debug: Toggle virtual text",
      },
      -- `:DapEval` opens a `dap-eval://` buffer pre-filled with the selection.
      { "<leader>dv", "<cmd>DapEval<cr>", desc = "Debug: Evaluate expression", mode = { "n", "v" } },
      {
        "<leader>dw",
        function()
          require("dapui").elements.watches.add()
        end,
        desc = "Debug: Add watch expression",
      },
    },
    config = function()
      local dap = require("dap")

      -- Mason installs the adapters; this config wires them. The catch-all first
      -- handler is load-bearing: mason otherwise writes its own `dap.adapters`
      -- and `dap.configurations` entries, which would duplicate dap-python and
      -- add a second Dart adapter under the same name.
      require("mason-nvim-dap").setup({
        ensure_installed = { "debugpy", "codelldb", "dart-debug-adapter" },
        automatic_installation = false,
        handlers = { function() end },
      })

      -- Python: dap-python resolves the interpreter from `VIRTUAL_ENV`,
      -- `CONDA_PREFIX`, or a venv at the project root, and brings launch /
      -- module / test / Django / Flask recipes with it.
      require("dap-python").setup("debugpy-adapter")
      require("dap-python").test_runner = "pytest"
      table.insert(dap.configurations.python, {
        type = "python",
        request = "launch",
        name = "Launch file (integratedTerminal)",
        program = "${file}",
        console = "integratedTerminal",
        justMyCode = false,
      })

      -- C, C++ and Rust all share the one codelldb adapter. Resolved lazily so
      -- that the path is looked up at launch time: on a first run codelldb is
      -- still being installed by mason when this spec's config() executes.
      dap.adapters.codelldb = function(callback, config)
        local executable = vim.fn.exepath("codelldb")
        if executable == "" then
          vim.notify("codelldb not found on PATH -- run `:Mason` to install it", vim.log.levels.ERROR)
          return
        end
        callback({
          type = "server",
          port = "${port}",
          executable = {
            command = executable,
            args = { "--port", "${port}" },
          },
        })
      end
      local codelldb = {
        {
          type = "codelldb",
          request = "launch",
          name = "Launch current file",
          program = "${file}",
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
        },
        {
          type = "codelldb",
          request = "launch",
          name = "Launch file (integratedTerminal)",
          program = "${file}",
          cwd = "${workspaceFolder}",
          stopOnEntry = false,
          runInTerminal = true,
        },
        {
          type = "codelldb",
          request = "attach",
          name = "Attach to process",
          pid = require("dap.utils").pick_process,
        },
      }
      for _, filetype in ipairs({ "c", "cpp", "rust" }) do
        dap.configurations[filetype] = vim.deepcopy(codelldb)
      end
      -- Rust: debug a prebuilt binary and the test binary. Both need `cargo
      -- build` (or `cargo test --no-run`) first, or codelldb has no symbols.
      table.insert(dap.configurations.rust, {
        type = "codelldb",
        request = "launch",
        name = "Cargo run",
        program = function()
          local bin, _, root = rust_crate()
          return vim.fs.joinpath(root, "target", "debug", bin)
        end,
        cwd = function()
          local _, _, root = rust_crate()
          return root
        end,
        stopOnEntry = false,
      })
      table.insert(dap.configurations.rust, {
        type = "codelldb",
        request = "launch",
        name = "Cargo test",
        program = function()
          local _, package, root = rust_crate()
          local binary = cargo_test_binary(package, root)
          if not binary then
            vim.notify("No test binary for " .. package .. " -- run `cargo test --no-run` first", vim.log.levels.WARN)
            return dap.ABORT
          end
          return binary
        end,
        -- Prompt for a filter, so one config covers both "run the suite" and
        -- "debug this specific test".
        args = function()
          local filter = ask("Test filter (empty for all): ") or {}
          return { filter }
        end,
        cwd = function()
          local _, _, root = rust_crate()
          return root
        end,
        stopOnEntry = false,
      })

      -- Dart/Flutter. `flutter debug-adapter` is on PATH; mason's
      -- `dart-debug-adapter` is installed too but only one of them may own the
      -- `dart` name.
      dap.adapters.dart = { type = "executable", command = "flutter", args = { "debug-adapter" } }
      dap.configurations.dart = {
        {
          type = "dart",
          request = "launch",
          name = "Launch file",
          justMyCode = true,
          program = "${file}",
          cwd = "${workspaceFolder}",
          -- Map the snapshot back to the working tree so breakpoints bind to
          -- your sources instead of the kernel snapshot.
          sourceFileMap = {
            {
              localRoot = "${workspaceFolder}",
              remoteRoot = "${workspaceFolder}",
            },
          },
        },
      }

      -- UI. Panels open without stealing focus, so the cursor stays in the
      -- source file when the debugger stops.
      local dapui = require("dapui")
      dapui.setup({
        layouts = {
          {
            size = 40,
            position = "left",
            elements = {
              { id = "scopes", size = 0.3 },
              { id = "breakpoints", size = 0.2 },
              { id = "stacks", size = 0.3 },
              { id = "watches", size = 0.2 },
            },
          },
          {
            size = 10,
            position = "bottom",
            elements = { "repl", "console" },
          },
        },
        icons = { expanded = "▾", collapsed = "▸" },
      })
      require("nvim-dap-virtual-text").setup({
        commented = false,
        highlight_changed_variables = true,
        highlight_new_as_changed = false,
        only_first_definition = true,
        all_references = false,
        clear_on_continue = false,
        show_stop_reason = true,
      })

      -- Stop on raised exceptions by default. Keyed by the `type` used in the
      -- configuration, so `python` covers every dap-python recipe.
      dap.defaults.fallback.exception_breakpoints = { "raised" }
      dap.defaults.python.exception_breakpoints = { "raised" }

      -- Panels follow the session lifecycle. A counter rather than a plain
      -- close so a second session cannot tear the panels down from under a
      -- still-live first one.
      local live_sessions = 0
      local function close_if_idle()
        if live_sessions > 1 then
          live_sessions = live_sessions - 1
          return
        end
        live_sessions = 0
        dapui.close()
      end
      dap.listeners.before.attach.dap_config = function()
        live_sessions = live_sessions + 1
        dapui.open()
      end
      dap.listeners.before.launch.dap_config = dapui.open
      dap.listeners.before.event_terminated.dap_config = close_if_idle
      dap.listeners.before.event_exited.dap_config = close_if_idle
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = vim.api.nvim_create_augroup("dap_config", { clear = true }),
        callback = function()
          dapui.close()
        end,
      })
    end,
  },
}
