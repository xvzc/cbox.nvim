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
---@field theme string                                                    theme name selected from `presets` (default: "thin")
---@field vline_style string                                              preferred comment kind for V-line wraps: `"line"` | `"block"` (default: `"line"`).  `"block"` emits a single spanning block comment around the whole box; only takes effect when the filetype has a block template configured.
---@field presets table<string, cbox.preset>                              named border-character sets
---@field comment_str table<string, string|{line?: string, block?: string}>  per-filetype comment template — either a string (auto-classified) or a `{ line?, block? }` table.  Filetypes not listed fall back to `vim.bo[bufnr].commentstring`.

---@class cbox.opts
---@field theme? string         border preset name; defaults to `config.theme`
---@field vline_style? string   override `config.vline_style` for this call
---@field width? integer        fixed total display width (default: auto)
---@field align? string         "left" | "right" | "center" — alignment when `width` is set (default: "left")

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
    vline_style = opts.vline_style or M.config.vline_style,
    width = opts.width,
    align = opts.align or "left",
  }
end

-- ===== V-line block wrap =====
--
-- When the user wraps a V-line selection with `vline_style = "block"` AND
-- the filetype has a block template, emit a single spanning block comment
-- around the whole box instead of the default per-row line comments:
--
--   // box      →   /* ┌─────┐
--   // box             │ box │
--   // box             │ box │
--   // box             └─────┘ */
--
-- Returns true on success.  Returns false when there's no block template
-- available — caller should fall back to the regular wrap path.
---@param sel cbox.detect.selection
---@param bufnr integer
---@param opts cbox.opts
---@return boolean
local function vline_block_wrap(sel, bufnr, opts)
  local cfg = M.config
  local comment = require("cbox.comment")
  local render = require("cbox.render")
  local detect = require("cbox.detect")

  local filetype = vim.bo[bufnr].filetype
  local block_tpl = comment.resolve_template(filetype, bufnr, "block")
  if not block_tpl or block_tpl.kind ~= "block" then
    return false
  end

  -- Expand the working range to include any boxes that overlap the
  -- selection — the selection conceptually covers the boxes as a unit, so
  -- the wrap dissolves them and re-emits around the cleaned content.
  local boxes = detect.find_boxes(sel, bufnr)
  local work_top = sel.start_line
  local work_bot = sel.end_line
  for _, b in ipairs(boxes) do
    if b.top < work_top then
      work_top = b.top
    end
    if b.bottom > work_bot then
      work_bot = b.bottom
    end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, work_top - 1, work_bot, false)
  if #lines == 0 then
    return false
  end

  -- Dissolve any existing boxes in the work range: in-place erase replaces
  -- box characters with content (or content-width spaces on border rows),
  -- and is_effectively_blank drops border-only rows.  After this step,
  -- `lines` holds the cleaned content with no inner boxes.
  if #boxes > 0 then
    local result =
      render.unwrap_overlapping_blockwise(lines, work_top, boxes, filetype, bufnr)
    lines = result.lines
  end

  -- Strip per-row comment markers when present, otherwise treat the input
  -- as plain content (keep leading whitespace as box-level outer indent).
  local stripped, ctx = comment.strip(lines, filetype, bufnr)
  local outer_indent
  if ctx then
    outer_indent = ctx.prefix:match("^(%s*)") or ""
  else
    -- Plain text: pull the longest common leading whitespace off all rows
    -- and use it as outer indent so the spanning emit sits at the source
    -- indent level.
    outer_indent = stripped[1]:match("^(%s*)") or ""
    for i = 2, #stripped do
      local row_indent = stripped[i]:match("^(%s*)") or ""
      while #outer_indent > 0 and not vim.startswith(row_indent, outer_indent) do
        outer_indent = outer_indent:sub(1, -2)
      end
      if outer_indent == "" then
        break
      end
    end
    for i, line in ipairs(stripped) do
      stripped[i] = line:sub(#outer_indent + 1)
    end
  end

  -- Render the raw box (no comment markers) around the stripped content.
  local max_disp = 0
  for _, line in ipairs(stripped) do
    max_disp = math.max(max_disp, vim.fn.strdisplaywidth(line))
  end
  local content_start = 1
  local content_end = math.max(max_disp, 1)
  local preset = cfg.presets[opts.theme or cfg.theme]
  local box_lines = render.wrap_lines(stripped, content_start, content_end, preset, opts)

  -- Wrap the box in a single spanning block comment.  Row 1 has the opener
  -- inline; middle rows are space-indented to align with the opener's
  -- trailing space; the last row has the closer appended (with padding so
  -- it aligns with the widest box row).
  local before = block_tpl.before
  local after = block_tpl.after
  local before_disp = vim.fn.strdisplaywidth(before)
  local inner_indent = string.rep(" ", before_disp)

  local max_w = 0
  for _, line in ipairs(box_lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_w then
      max_w = w
    end
  end

  local result = {}
  for i, line in ipairs(box_lines) do
    local lead = (i == 1) and (outer_indent .. before) or (outer_indent .. inner_indent)
    local trail = ""
    if i == #box_lines then
      local pad = max_w - vim.fn.strdisplaywidth(line)
      if pad > 0 then
        line = line .. string.rep(" ", pad)
      end
      trail = after
    end
    table.insert(result, lead .. line .. trail)
  end

  vim.api.nvim_buf_set_lines(bufnr, work_top - 1, work_bot, false, result)
  return true
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
  local detect = require("cbox.detect")
  local sel = detect.get_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local resolved = resolve_opts(opts)
  if detect.is_linewise(sel) and resolved.vline_style == "block" then
    if vline_block_wrap(sel, bufnr, resolved) then
      return
    end
  end
  require("cbox.api").wrap(sel, bufnr, resolved)
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

  -- V-line wrap with vline_style=block: route through the spanning-block
  -- emitter when the toggle's direction is "wrap".  Unwrap goes through
  -- api.unwrap; the spanning block delimiters around an erased box are not
  -- yet auto-stripped (deferred to a later pass).
  local function maybe_block_wrap()
    if detect.is_linewise(sel) and resolved.vline_style == "block" then
      if vline_block_wrap(sel, bufnr, resolved) then
        return true
      end
    end
    return false
  end

  -- Direction:
  --   * 0 boxes / multi-box / OUTSIDE classify       → wrap.
  --   * 1 box, linewise, sel strictly inside content
  --     of a partial box                             → wrap (erase + redraw).
  --   * 1 box, linewise, INSIDE/OVERLAPPING (clean)  → unwrap.
  --   * 1 box, blockwise, boundaries align (one
  --     contains the other)                          → unwrap.
  --   * 1 box, blockwise, partial overlap            → wrap (merge).
  if #boxes ~= 1 then
    if maybe_block_wrap() then
      return
    end
    return api.wrap(sel, bufnr, resolved)
  end

  local position = detect.classify(sel, boxes).position
  if position == detect.Position.OUTSIDE then
    if maybe_block_wrap() then
      return
    end
    return api.wrap(sel, bufnr, resolved)
  end

  if detect.is_linewise(sel) then
    local b = boxes[1]
    local strictly_inside = sel.start_line > b.top and sel.end_line < b.bottom
    if strictly_inside and not detect.box_is_clean_linewise(b, bufnr) then
      if maybe_block_wrap() then
        return
      end
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
