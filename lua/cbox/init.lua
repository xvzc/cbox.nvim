---@toc cbox.contents

---@mod cbox cbox.nvim
---@brief [[
---Comment-box drawing for Neovim.
---
---Three top-level commands wrap the current visual selection (or the word
---under the cursor in normal mode):
---
--- - |cbox.box|     — draw a box.
--- - |cbox.unbox|   — strip the box around the selection.
--- - |cbox.toggle|  — draw or strip depending on context.
---
---Comment prefixes (per filetype) are detected and preserved, so wrapping a
---selection inside a `// ...` block keeps the new box commented.
---
---Quick start:
--->lua
---  require("cbox").setup()
---  vim.keymap.set({ "n", "v" }, "<leader>cb", function()
---    require("cbox").toggle()
---  end)
---<
---@brief ]]

---@alias cbox.preset string[] 8-element list: tl, top-fill, tr, left, right, bl, bottom-fill, br

---@class cbox.config
---@field theme string                          theme name selected from `presets` (default: "thin")
---@field presets table<string, cbox.preset>    named border-character sets
---@field comment_str table<string, string>     per-filetype comment template, e.g. `{ lua = "-- %s" }`.  Filetypes not present here fall back to `vim.bo[bufnr].commentstring`.

---@class cbox.opts
---@field theme? string  border preset name; defaults to `config.theme`
---@field width? integer fixed total display width (default: auto)
---@field align? string  "left" | "right" | "center" — alignment when `width` is set (default: "left")

local defaults = require("cbox.defaults")

local M = {}

---Merges `opts` over the defaults.  Safe to call multiple times.  Sets
---`vim.g.cbox_loaded` so the auto-setup at the bottom of this file becomes
---a no-op once user setup runs.
---@param opts? cbox.config
---@usage [[
---require("cbox").setup({
---  theme = "double",
---  presets = {
---    rounded = { "╭", "─", "╮", "│", "│", "╰", "─", "╯" },
---  },
---})
---@usage ]]
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
  vim.g.cbox_loaded = 1
end

---@param opts? cbox.opts|string
---@return cbox.opts
local function resolve_opts(opts)
  if type(opts) == "string" then
    opts = { theme = opts }
  end
  opts = opts or {}
  return {
    theme = opts.theme or M.config.theme,
    width = opts.width,
    align = opts.align or "left",
  }
end

---Wraps the visual selection (or the word under the cursor in normal mode)
---in a comment box.
---@param opts? cbox.opts
---@usage [[
---vim.keymap.set("v", "<leader>cb", function()
---  require("cbox").box({ theme = "double" })
---end)
---@usage ]]
function M.box(opts)
  local sel = require("cbox.detect").get_selection()
  require("cbox.api").wrap(sel, vim.api.nvim_get_current_buf(), resolve_opts(opts))
end

---Strips the box that contains (or overlaps) the visual selection.  No-op
---when the selection is not inside any box.
---@usage [[
---vim.keymap.set({ "n", "v" }, "<leader>cu", function()
---  require("cbox").unbox()
---end)
---@usage ]]
function M.unbox()
  local sel = require("cbox.detect").get_selection()
  require("cbox.api").unwrap(sel, vim.api.nvim_get_current_buf())
end

---Draws a box if the selection has none, strips it if a box already encloses
---it, or merges/redraws when the selection partially overlaps existing boxes.
---@param opts? cbox.opts
---@usage [[
---vim.keymap.set({ "n", "v" }, "<leader>cc", function()
---  require("cbox").toggle()
---end)
---@usage ]]
function M.toggle(opts)
  local detect = require("cbox.detect")
  local api = require("cbox.api")
  local sel = detect.get_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local boxes = detect.find_boxes(sel, bufnr)
  local resolved = resolve_opts(opts)

  -- Direction:
  --   * 0 boxes / multi-box / OUTSIDE classify       → wrap.
  --   * 1 box, linewise, sel strictly inside content
  --     of a partial box                             → wrap (erase + redraw).
  --   * 1 box, linewise, INSIDE/OVERLAPPING (clean)  → unwrap.
  --   * 1 box, blockwise, boundaries align (one
  --     contains the other)                          → unwrap.
  --   * 1 box, blockwise, partial overlap            → wrap (merge).
  if #boxes ~= 1 then
    return api.wrap(sel, bufnr, resolved)
  end

  local position = detect.classify(sel, boxes).position
  if position == detect.Position.OUTSIDE then
    return api.wrap(sel, bufnr, resolved)
  end

  if detect.is_linewise(sel) then
    local b = boxes[1]
    local strictly_inside = sel.start_line > b.top and sel.end_line < b.bottom
    if strictly_inside and not detect.box_is_clean_linewise(b, bufnr) then
      api.wrap(sel, bufnr, resolved)
    else
      api.unwrap(sel, bufnr)
    end
  elseif detect.boundaries_align(sel, boxes[1], bufnr) then
    api.unwrap(sel, bufnr)
  else
    api.wrap(sel, bufnr, resolved)
  end
end

if not vim.g.cbox_loaded then
  M.setup()
end

return M
