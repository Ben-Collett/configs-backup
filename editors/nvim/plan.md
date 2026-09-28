# Plan: full debugger support in this nvim config

Target: first-class debugging for **Python**, **C/C++**, **Rust**, and **Dart/Flutter**, with
nvim-dap-ui panels, virtual-text values, conditional breakpoints, logpoints, exception
breakpoints, per-project `.vscode/launch.json` discovery, and lazy-loaded keymaps.
Everything dap-related lives in exactly one plugin spec.

Style constraints observed by this config: 2-space indent (`.stylua.toml`), 

---

## Findings that shape this plan

These were verified against the code actually installed in
`~/.local/share/nvim/lazy/`, not assumed.

1. **`lua/plugins/mason-dap.lua` handlers are near-dead code.**
   `mason-nvim-dap.nvim@9a10e09` (`lua/mason-nvim-dap/init.lua:37-91`) dispatches handlers as
   `handler(config)` and expects the handler to call
   `require("mason-nvim-dap").default_setup(config)`. The existing handlers take a positional
   `source_name` argument and never call `default_setup`, so mason never wires anything up. That
   is why the Dart adapter/config is duplicated in `lua/plugins/debugging.lua`.
   The Python handler also hardcodes `command = "/usr/bin/python3"` with args
   `{ "-m", "debugpy.adapter" }`, which bypasses mason's already-installed `debugpy`
   (`~/.local/share/nvim/mason/packages/debugpy`) and bypasses any project virtualenv.
   `ensure_installed` is never set, so nothing is ever auto-installed.

2. **`nvim-dap-vscode` is not needed.** `lazy-lock.json` pins
   `nvim-dap @ 9e848e09` = `0.10.0-65-g9e848e0`. Since 0.10.0, configuration resolution was
   rewritten as a provider system. `doc/dap.txt:1399-1440` documents two built-in providers:
   `dap.global` (reads `dap.configurations.<filetype>`) and `dap.launch.json` (reads
   `.vscode/launch.json`). `.vscode/launch.json` is read on demand whenever a session starts.
   No third-party plugin, no `load_vscode_json()` call.

3. **mason-nvim-dap has no `rust-lldb` mapping.**
   `lua/mason-nvim-dap/mappings/source.lua:6-27` maps adapter name → mason package and contains
   `codelldb = "codelldb"` but nothing for `rust-lldb`. `mappings/filetypes.lua:14` already
   routes `codelldb` to filetypes `c`, `cpp`, `rust`, `swift`, `zig`. So **codelldb is the one
   adapter for C/C++/Rust** and mason can install it. (Decision: codelldb for Rust too,
   not raw `rust-lldb`.)

4. **The `handlers` table fires for already-installed packages.**
   `init.lua:37` iterates `registry.get_installed_package_names()`. Installed and mapped today:
   `debugpy`, `dart-debug-adapter`, `bash-debug-adapter`, `go-debug-adapter`. A no-op catch-all
   as `handlers[1]` fully opts out of mason auto-wiring
   (`init.lua:41`: `default_handler = Optional.of_nilable(handlers[1]):or_(M.default_setup)`).

5. **nvim-dap-ui and nvim-dap-virtual-text both load cleanly on nvim v0.12.5.**
   Verified headless: `require("dapui").setup()` → ok, `require("nvim-dap-virtual-text").setup()`
   → ok. So keep nvim-dap-ui; no fork, no swap.
   (`require("dap").setup()` does **not** exist — nvim-dap is configured by direct table
   assignment. Do not call it.)

6. **`debugpy-adapter` is already on PATH** at `~/.local/share/nvim/mason/bin/debugpy-adapter`
   (mason bin dir is on `PATH` from mason.nvim). `codelldb` is not installed yet.

7. **Treesitter parsers are missing for the new filetypes.**
   `lua/plugins/treesitter.lua:8` has `python`, `dart`, `lua` but not `rust`, `cpp`, `c`.
   nvim-dap-virtual-text needs a parser to place inline values.

8. **`<leader>d` and `<leader>D` are both taken**, so the dap keymap group must be two-key:
   - `lua/config/keymaps.lua:22-23` — global `<leader>d` = `"_d`, `<leader>D` = `"_D`
   - `lua/plugins/lsp/lspconfig.lua:97,100` — buffer-local `<leader>D` = Telescope
     `diagnostics bufnr=0`, `<leader>d` = `vim.diagnostic.open_float`

9. This is **not** a LazyVim base (no `lazyvim` plugin in `~/.local/share/nvim/lazy/`,
   and `lua/config/lazy.lua` only imports `plugins` and `plugins.lsp`). There are no inherited
   dap keymaps. `lazyvim.json` is a leftover from the fork.

10. Existing global dap keymaps to preserve or drop deliberately:
    `<C-b>` bp, `<C-d>` continue, `<C-j>` step over, `<C-s>` step into, `<leader>dou` step out,
    `<C-k>` step back, `<C-c>` run to cursor (`lua/plugins/debugging.lua:24-30`).
    Decision: keep `<C-b>`, `<C-d>`, `<C-j>`, `<C-k>`. Drop `<C-s>` (collides with
    terminal/paste/save) and `<C-c>` (interrupt key); both stay reachable via `<leader>di` /
    `<leader>dl`.

---

## Target file layout

| Action | Path |
|---|---|
| delete | `lua/plugins/debugging.lua` |
| delete | `lua/plugins/mason-dap.lua` |
| create | `lua/plugins/dap.lua` — the single dap spec (mason install, adapters, configs, dapui, vtext, keymaps) |
| modify | `lua/plugins/treesitter.lua` — add `rust`, `cpp`, `c` parsers |
| modify | `lua/config/lazy.lua` — nothing required (the `plugins` import already picks up `dap.lua`) |
| modify | `lazy-lock.json` — lazy.nvim adds `nvim-dap-python`; 

---

## Step 1 — Remove the two overlapping specs

**What to do**

```sh
rm lua/plugins/debugging.lua
rm lua/plugins/mason-dap.lua
```

`lua/config/lazy.lua:26-30` imports the whole `plugins` directory, so no import list to update.

**Validate**

```sh
nvim --headless -i NONE -c 'qa!' 2>&1 | tail -5
```

Expect no errors. (nvim-dap / dapui / vtext simply stop loading; nothing else references them.)

**Done when** nvim starts clean and `nvim-dap` is no longer eagerly loaded at startup
(confirm via `:Lazy` → `nvim-dap` shows as loaded=false, or by checking startup time
with `nvim --startuptime /tmp/st.txt +q` before/after).

---

## Step 2 — Create `lua/plugins/dap.lua` skeleton with lazy-loaded keymaps

**What to do**

Create the spec with a `keys` table containing every dap mapping listed in Step 7. Putting the
keys in the spec's `keys` field is what makes lazy.nvim load dap on first keypress, which
replaces the old eager `kmap.set` calls in `config`.

Shape:

```lua
return {
  {
    "mfussenegger/nvim-dap",
    dependencies = {
      "rcarriga/nvim-dap-ui",
      "theHamsta/nvim-dap-virtual-text",
      "mfussenegger/nvim-dap-python",
      "nvim-neotest/nvim-nio",         -- required by nvim-dap-ui
      "jay-babu/mason-nvim-dap.nvim",
    },
    keys = { /* see Step 7 */ },
    config = function()
      -- Steps 3-6 land here
    end,
  },
}
```

Note: `nvim-dap-python` is the only new plugin. Everything else is already in `lazy-lock.json`.

**Validate**

```sh
nvim --headless -i NONE -c 'qa!' 2>&1 | tail -5
:scriptnames   -- must NOT list nvim-dap on a cold start
```

Then confirm the lazy trigger works: press `<leader>dc` in a scratch buffer, and
`nvim-dap`, `dapui` and `nvim-dap-virtual-text` should all appear in `:scriptnames` /
`:Lazy` as loaded.

**Done when** a cold start loads zero dap plugins, and pressing any dap key loads all of them.

---

## Step 3 — mason-nvim-dap: install only, never wire

**What to do**

Inside `config()`:

```lua
require("mason-nvim-dap").setup({
  ensure_installed = { "debugpy", "codelldb", "dart-debug-adapter" },
  automatic_installation = false,
  handlers = { function() end },   -- catch-all no-op: mason installs, this config wires dap
})
```

- `ensure_installed` is resolved through `mappings/source.lua`, so these are *adapter* names
  (`debugpy`→package `debugpy`, `codelldb`→package `codelldb`,
  `dart-debug-adapter`→adapter `dart`).
- `handlers = { function() end }` is deliberate: `init.lua:41` uses `handlers[1]` as the
  default handler, so a no-op first element stops mason from writing to
  `dap.adapters`/`dap.configurations` and colliding with `dap-python` and the codelldb
  config in Step 4.

**Validate**

1. `nvim --headless -i NONE -c 'qa!'` — no error.
2. `:Mason` → `codelldb` should appear and install on the first real startup.
3. After install: `nvim --headless -i NONE -c 'lua print(vim.fn.exepath("codelldb"))' -c 'qa!'`
   → prints a mason path, not an empty string.
4. Confirm no accidental auto-wiring: open a python buffer, then
   `:lua print(vim.inspect(vim.tbl_keys(require("dap").configurations.python)))`
   → should be **empty** (or only what Step 4 added, not mason's `Launch file`). If mason
   snuck in a config, the `handlers` catch-all is not working.
5. `:checkhealth` or `:lua require("mason-nvim-dap").get_installed_sources()` — sanity check.

**Done when** `codelldb` is installed, `debugpy` stays installed, and mason's Python config
has not been injected behind dap-python's back.

---

## Step 4 — Adapters and configurations per language

**What to do**

All of this goes inside `config()`, after the mason setup.

### 4a. Python — `dap-python` (do NOT hand-roll debugpy)

```lua
require("dap-python").setup("debugpy-adapter")
```

`debugpy-adapter` is on PATH via mason (verified). This replaces the hardcoded
`/usr/bin/python3` and gives, for free:
launch current file, launch module, debug test method, debug test class, debug selection,
Django and Flask recipes, plus venv resolution from `VIRTUAL_ENV` / `CONDA_PREFIX` / a
`venv`, `.venv`, `env`, `.env` directory at cwd **or** the active LSP client's `root_dir`
(the latter matters because the config uses `project.nvim` and `dap` configs otherwise run
from wherever nvim was started).

Then append extras and set the test runner:

```lua
local dap = require("dap")
table.insert(dap.configurations.python, {
  type = "python", request = "launch", name = "Launch file (integratedTerminal)",
  program = "${file}", console = "integratedTerminal", justMyCode = false,
})
require("dap-python").test_runner = "pytest"
```

If you later add `uv`-managed environments, switch to `require("dap-python").setup("uv")`
instead — one line.

### 4b. C / C++ / Rust — codelldb (one adapter for all three)

```lua
dap.adapters.codelldb = {
  type = "server",
  port = "${port}",
  executable = { command = vim.fn.exepath("codelldb"), args = { "--port", "${port}" } },
}
```

(verbatim from `mason-nvim-dap/mappings/adapters/codelldb.lua`, minus the win32 branch.)

Configurations — a small builder so the three filetypes stay in sync:

- *Launch current file* — `program = "${file}"`, `cwd = "${workspaceFolder}"`, `stopOnEntry = false`
- *Launch file (integratedTerminal)*
- *Attach to process* — `request = "attach"`, `pid = require("dap.utils").pick_process`
- Rust extras: *cargo run* (`program` from the current `[[bin]]`),
  *cargo test* (`request = "launch"`, cargo's test runner produces the
  `type = "rust"`, `request = "launch"`-shaped config), and *Debug a specific test* via
  `nvim-dap` `args` interpolation.
- C/C++ extras: *Launch target from Makefile/CMake target*, with
  `MIMode = "gdb"` if falling back to `gdb` (installed at `/usr/sbin/gdb`).

Apply the same list to `c`, `cpp` and `rust` in `dap.configurations` so the picker works
from any of the three filetypes. Keep the configs small — the cookbook recommends per-project
`.vscode/launch.json` (Step 6) for anything elaborate.

### 4c. Dart / Flutter — keep what works, fix the name

Your existing executable adapter is correct (`flutter debug-adapter` is on PATH at
`~/programs/flutter/bin/flutter`). Keep it, rename the config from the misleading
`"Launch file with venv"` (Dart has no venv) to `"Launch file"`, and add `sourceFileMap` so
breakpoints map back to your sources rather than the snapshot:

```lua
dap.adapters.dart = { type = "executable", command = "flutter", args = { "debug-adapter" } }
dap.configurations.dart = {
  {
    type = "dart", request = "launch", name = "Launch file",
    justMyCode = true, program = "${file}", cwd = vim.fn.getcwd(),
  },
}
```

If you later prefer mason's adapter instead, it is
`command = vim.fn.exepath("dart-debug-adapter"), args = { "flutter" }`
(`mappings/adapters/dart.lua`) — `dart-debug-adapter` is already installed. Either is fine;
do not define both.

**Validate**

1. `nvim --headless -i NONE -c 'qa!'` — no error.
2. Open a Python file, `:<C-u>lua print(vim.inspect(require("dap").configurations.python))`
   → dap-python's entries plus the one you added. Note the *names*; these are what the
   `<leader>dc` picker shows.
3. Open a Rust file, `:<C-u>lua print(#require("dap").configurations.rust)` → > 0.
   Same for `c`, `cpp`, `dart`.
4. `:<C-u>lua print(vim.inspect(require("dap").adapters))` → `python`, `codelldb`, `dart`
   present, each pointing at a real `exepath` (no `/usr/bin/python3` hardcoding).

**Done when** each of python / c / cpp / rust / dart has a non-empty `dap.configurations`
entry and a resolvable adapter, with no duplicate Dart/Python definitions anywhere.

---

## Step 5 — UI: dapui panels, virtual text, exception breakpoints

**What to do**

```lua
local dapui = require("dapui")
local vtext = require("nvim-dap-virtual-text")
```

### 5a. dapui

`dapui.setup()` with an explicit layout rather than the defaults, plus a floating variant for
when the windowed panels would fight `neo-tree`, `lualine` or `nvim-ufo`:

- left sidebar, 40 cols: `scopes` (0.3), `breakpoints` (0.2), `stacks` (0.3), `watches` (0.2)
- bottom, 10 rows: `repl`, `console`
- a second `floating` layout (stacks + scopes + breakpoints, centered) bound to `<leader>duf`
- `focus = true` while stopped; `render = { expanded = "▾", collapsed = "▸" }` from the defaults

Keep the four lifecycle listeners from `lua/plugins/debugging.lua:12-23` verbatim
(`before.attach`, `before.launch` → `dapui.open()`; `before.event_terminated`,
`before.event_exited` → `dapui.close()`). Add `before.event_terminated` guard so a second
session cannot close panels out from under a still-live one, and add a `VimLeavePre` →
`dapui.close()`.

### 5b. virtual text

```lua
vtext.setup({
  commented = false,
  highlight_changed_variables = true,
  highlight_new_as_changed = false,
  only_first_definition = true,
  all_references = false,
  clear_on_continue = false,
  show_stop_reason = true,
})
```

### 5c. Exception breakpoints (new capability, not configured today)

```lua
dap.defaults.fallback.exception_breakpoints = { "raised" }
dap.defaults.debugpy.exception_breakpoints = { "raised" }
```

`dap.defaults.<adapter>` is keyed by the `type` used in the config
(`doc/dap.txt:850-865`), which is `python`/`debugpy` here. Verify the key matches your actual
`type` string before relying on the second line.

### 5d. Diagnostics bridge

```lua
dap.diagnostics = require("dap.ext.diagnostics").to_nvim_diagnostic
```

This makes stopped frames visible to `vim.diagnostic`, which plugs into your existing
`<leader>D` (Telescope `diagnostics bufnr=0`) and `<leader>xe` (Trouble) mappings in
`lua/config/keymaps.lua:36` and `lua/plugins/lsp/lspconfig.lua:97`.

**Validate**

1. `nvim --headless -i NONE -c 'lua require("dapui").setup({})' -c 'qa!'` — no error.
2. Launch any Python session. The left sidebar and bottom repl/console should render with no
   Lua errors. This is the real test of nvim-dap-ui on 0.12.
3. `:<C-u>lua print(vim.inspect(require("dap").defaults))` → both exception-breakpoint
   entries present.
4. Toggle virtual text off/on via the command and confirm inline values appear on the stopped
   line.
5. Confirm the layout does not fight your other UI: with dapui open, check `lualine` renders,
   `neo-tree` still toggles, and `nvim-ufo` folds still work. This is the most likely place
   for a 0.12 regression to surface.

**Done when** a session shows sidebar + repl + console, inline values on the stopped frame,
and nothing else in your UI breaks.

---

## Step 6 — `.vscode/launch.json` support (no plugin required)

**What to do**

Nothing to install — `dap.launch.json` is a built-in provider in your pinned nvim-dap
(Finding 2). Optionally tolerate trailing commas / comments, since nvim-dap is strict JSON
whereas VS Code is not:

```lua
require("dap.ext.vscode").json_decode = require("json5").parse
```

This adds one dependency (`Joakker/lua-json5`) — only do it if you actually need it.

Also worth knowing (no action): nvim-dap 0.10 can *create* a starter `.vscode/launch.json` via
`vim.snippet` boilerplate, and saves auto-apply. So a project with no launch config can be
bootstrapped from inside nvim.

**Validate**

1. Scratch project: `mkdir -p /tmp/dapdemo/.vscode`, write a `launch.json` with a
   `"type": "python", "request": "launch", "name": "From launch.json", "program": "${file}"`
   entry.
2. Open a file in that project, `<leader>dc` → the picker must show **both** the Lua-defined
   configs *and* `From launch.json`.
3. Run it and confirm it stops at a breakpoint.
4. Without the project, confirm the picker does **not** show it (proves it is scoped to
   `.vscode/launch.json` and not a global leak).

**Done when** launch.json entries appear in the picker for a project that has one, and only
for that project.

---

## Step 7 — Keymaps

**What to do**

Put all of these in the spec's `keys` table (Step 2). Two-key dap group, because `<leader>d`
and `<leader>D` are already taken (Finding 8).

| Key | Action | Notes |
|---|---|---|
| `<C-b>` | `dap.toggle_breakpoint` | kept from today |
| `<C-d>` | `dap.continue` | kept |
| `<C-j>` | `dap.step_over` | kept |
| `<C-k>` | `dap.step_back` | kept |
| `<leader>db` | `dap.toggle_breakpoint` | |
| `<leader>dl` | `dap.run_to_cursor` | replaces dropped `<C-c>` |
| `<leader>di` | `dap.step_into` | replaces dropped `<C-s>` |
| `<leader>dn` | `dap.new` / pick a new configuration | |
| `<leader>dr` | `dap.restart` | |
| `<leader>dc` | `dap.continue` | |
| `<leader>do` | `dap.step_over` | |
| `<leader>ds` | `dap.step_out` | replaces `<leader>dou` |
| `<leader>dbk` | `dap.step_back` | |
| `<leader>dp` | `dap.pause` | |
| `<leader>dq` | `dap.terminate` | |
| `<leader>dt` | toggle the built-in `dap.repl` | |
| `<leader>dd` | `dapui.toggle_repl` | |
| `<leader>duc` | `dapui.toggle_console` | |
| `<leader>duf` | `dapui.toggle` | floating layout, from 5a |
| `<leader>dsu` | `vtext:enabled` toggle | |
| `<leader>dv` | `require("dap").eval()` | **visual mode**, evaluate selection |
| `<leader>dw` | `require("dap.ui.widgets").add_expression_input()` | |
| `<leader>dbc` | conditional breakpoint, prompt for condition | `dap.toggle_breakpoint(cond)` |
| `<leader>dbl` | logpoint, prompt for log message | `dap.toggle_breakpoint(nil, nil, msg)` |
| `<leader>de` | toggle exception breakpoints | `dap.set_exception_breakpoints` |
| `<leader>dP` | `require("dap").run` an attach-to-pick-process config | see 4b |

For the three prompt-driven entries (`dbc`, `dbl`, `de`) use
`vim.fn.input({ prompt = "..." })` and bail on empty input. For `dbc`/`dbl`, read the current
line for an existing logpoint/condition so re-toggling clears rather than stacks.

Every mapping should carry a `desc`.

**Validate**

1. `:map <leader>d` and `:map <C-b>` — every entry in the table above appears, with `desc`.
2. Confirm no duplicate/shadowed mappings:
   `:verbose nmap <leader>db` and `:verbose nmap <C-d>`.
3. `lua/config/keymaps.lua:22-23` still works: `<leader>d` must still be `"_d` and
   `<leader>D` must still be `"_D` — a dap mapping that shadowed these would silently change
   your delete behaviour.
4. `lua/plugins/lsp/lspconfig.lua:97,100` still works in an LSP-attached buffer:
   `<leader>d` = diagnostic float, `<leader>D` = Telescope buffer diagnostics.
5. `<C-s>` and `<C-c>` are now free in normal mode. Confirm your terminal-mode and
   normal-mode `<C-s>`/`<C-c>` behaviour is what you want (this is the behavioural change —
   do it deliberately).
6. In visual mode, select an expression and press `<leader>dv` → value echoed.
7. `<leader>dbc` on a line, then a logpoint-marked line with `<leader>dbl` → neither sets a
   *stopping* breakpoint; hitting them logs to the console instead.

**Done when** the whole table resolves, and none of your pre-existing `<leader>d`/`<leader>D`
or `<C-s>`/`<C-c>` behaviour was silently stolen.

---

## Step 8 — Treesitter parsers for the new filetypes

**What to do**

In `lua/plugins/treesitter.lua:8`, extend `ensure_installed`:

```lua
ensure_installed = { "diff", "lua", "python", "toml", "regex", "luadoc", "nu", "vim", "dart", "comment", "rust", "cpp", "c" },
```

(`auto_install = true` is already set, so these self-install on first use; `:TSUpdate` also
works. This file is in the repo's `no-update-on` set only via `lazy-lock.json`, not itself.)

**Validate**

1. Open a `.rs`, `.c` and `.cpp` file; `:TSInstallInfo` (or `:checkhealth`) shows the
   parsers installed.
2. `:` `:lua print(vim.treesitter.language.get_lang("rust"))` → `rust`.
3. Confirm stepping in a Rust/C file shows inline virtual-text values (the actual reason for
   this step) rather than nothing.

**Done when** virtual text renders in all four target languages.

---

## Step 9 — Install, sync the lockfile

**What to do**

```sh
# 1. sync (pulls nvim-dap-python, drops nothing)
nvim --headless -c 'Lazy sync' -c 'qa!'
```

`nvim-dap-python` is the only new plugin; `lazy-lock.json` should gain exactly one line
(`nvim-dap-python`) and lose the two you deleted
(`mason-nvim-dap.nvim` stays — it is a dependency of the new spec).


**Validate**

1. `git status` — `lazy-lock.json` and the dap files are the only changes.
2. Delete `~/.local/share/nvim/lazy/nvim-dap-python` and re-sync to prove the lock entry
   pins a real commit.

**Done when** `:Lazy sync` reproduces a working
debugger.

---

## Step 10 — End-to-end acceptance run

Do these in order. Each is a distinct failure mode.

| # | Scenario | Steps | Pass condition |
|---|---|---|---|
| 1 | Clean load | `nvim --headless -c 'qa!'` | no errors, no lazy load of dap |
| 2 | Mason | `:Mason` | `codelldb`, `debugpy`, `dart-debug-adapter` all installed |
| 3 | Python, system interpreter | scratch `hello.py`, `<C-b>`, `<leader>dc` → *Launch file* | stops, sidebar shows scopes, vtext shows values |
| 4 | Python, venv | project with `.venv`, `:Pedit` into a site-packages file, set bp, launch | breakpoint **inside the venv** hits → proves venv resolution replaced the hardcoded `/usr/bin/python3` |
| 5 | Python tests | pytest test file, cursor in a test, `<leader>dn` → *Debug test method* | stops inside the test |
| 6 | Python + launch.json | `/tmp/dapdemo/.vscode/launch.json`, `<leader>dc` | entry appears in picker *and* runs |
| 7 | Exception breakpoints | `<leader>de`, trigger a Python exception | stops on the raise; re-toggle resumes without stopping |
| 8 | Conditional bp | `<leader>dbc` with a false condition | never stops; condition shown in the breakpoints panel |
| 9 | Logpoint | `<leader>dbl` with a message | no stop; message appears in the dapui console |
| 10 | Rust | `cargo build` first (debug symbols), then `<leader>dc` | stops; vtext renders values |
| 11 | C/C++ | compile with `-g`, launch, plus `<leader>dP` attach to a running process | stops in both modes |
| 12 | Dart/Flutter | scratch flutter app, launch | stops; `sourceFileMap` resolves to your file, not the snapshot |
| 13 | Panels on 0.12 | toggle sidebar / repl / console / floating repeatedly | no errors, layout stable |
| 14 | UI coexistence | with dapui open: `lualine` renders, `neo-tree` toggles, `nvim-ufo` folds | all still work |
| 15 | Keymap coexistence | `<leader>d`/`<leader>D` delete + diagnostics; `<C-s>`/`<C-c>` free | unchanged from before, deliberately |
| 16 | Stepping | step over / into / out / back / run-to-cursor in Python and Rust | all correct, including a nested call for step-into |

---

## Risks and things that could bite

- **nvim-dap-ui is unmaintained.** It loads clean on 0.12.5 (verified), but it is the most
  likely thing to break on a future nvim release. Fallback is
  `theHamsta/nvim-dap-ui` — a nio-based rewrite with a near-identical `require("dapui")`
  surface, so the swap is a one-line dependency change.
- **The `handlers = { function() end }` catch-all is load-bearing.** It depends on
  `init.lua:41` giving `handlers[1]` precedence over `M.default_setup`. If a future
  mason-nvim-dap changes that, mason will silently start writing `dap.adapters.python` and
  fight `dap-python`. Symptom if it happens: `:DapLog` shows `python3 -m debugpy.adapter`
  instead of mason's `debugpy-adapter`, or the Python config picker has duplicate entries.
- **Mason already installed `dart-debug-adapter`**, and you also have `flutter
  debug-adapter`. Pick one for the `dart` adapter name (Step 4c). Defining both under the
  same name is how the current duplication bug happened.
- **codelldb needs debug symbols.** For Rust run `cargo build` first; for C/C++ compile
  without `-O2` and with `-g`. No breakpoint without symbols is a symbols problem, not a
  config problem.
- **Attaching to another user's process on Linux may need
  `sysctl kernel.yama.ptrace_scope = 0`** (or root). That is scenario 11, not a config bug.
- **Virtual text needs a treesitter parser** — hence Step 8. Missing parser shows as "no
  inline values" rather than an error.
- **Two live sessions will fight over the dapui layout.** If you run two debug sessions,
  add a `dapui` session-scoped check in the `event_terminated` handler.
