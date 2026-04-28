# Documentation

User-facing documentation in `doc/cbox.nvim.txt` is generated from the lua sources via `lemmy-help`. Run `make docs` to regenerate; `make check-docs` verifies the committed output matches the source. Both run in CI.

The list of source files passed to `lemmy-help` lives in the Makefile's `_gen-docs` target. Add new modules there.

## Tag collisions

Vim help tags must be unique within `doc/cbox.nvim.txt`. A function `M.foo` on the root module gets the tag `*cbox.foo*`, which collides with a submodule named `cbox.foo`. Pick submodule names that don't shadow public function names — for example, the box-rendering module is `cbox.render`, not `cbox.box`, because the root module already exposes `cbox.box()`.

## Annotation style

Documentation annotations follow the Lua type-annotation style: no leading space after `---`.

```lua
-- correct
---@mod cbox.api API
---@brief [[
---Buffer-aware wrap/unwrap orchestration.
---@brief ]]

-- incorrect
--- @mod cbox.api API
--- @brief [[
```

Body text inside `---@brief [[ ... ---@brief ]]` and `---@usage [[ ... ---@usage ]]` blocks may use a leading space for indentation purposes.

## Module headers

`init.lua` declares `---@toc cbox.contents` plus `---@mod cbox cbox.nvim` and `---@brief`.  Every other lua module uses `---@mod cbox.<name>` and `---@brief` headers too.

```lua
---@toc cbox.contents

---@mod cbox cbox.nvim
---@brief [[
---Comment-box drawing for Neovim.
---
---Quick start:
--->lua
---  require("cbox").setup()
---<
---@brief ]]
```

## Type names

Nested types use dot notation, not underscores. Public types live under the `cbox.*` namespace; module-local helper types may stay un-namespaced when they never appear in user-facing help.

```lua
-- correct
---@class cbox.opts
---@class cbox.api.selection

-- incorrect
---@class cbox.box_opts
---@class BoxOpts
```

## Public functions

Every exported function on `M` gets `---@param` and `---@return` (when applicable) plus a `---@usage` block showing a self-contained example:

```lua
---Wraps the visual selection in a comment box.
---@param opts? cbox.opts
---@usage [[
---require("cbox").box({ style = "double" })
---@usage ]]
function M.box(opts) end
```

## Examples

Example code blocks must declare every variable they reference. Never assume `bufnr`, `sel`, or any other local is already in scope:

```lua
-- correct
--->lua
---  local cbox = require("cbox")
---  local bufnr = vim.api.nvim_get_current_buf()
---  cbox.toggle()
---<

-- incorrect
--->lua
---  cbox.toggle()
---<
```

## Internal comments

Implementation comments (the non-`---` kind) follow the project's general comment guidance: only write one when the *why* is non-obvious. Do not narrate *what* the code does. A stale comment that describes a refactored shape is worse than no comment.
