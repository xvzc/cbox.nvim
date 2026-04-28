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

---@class cbox.visual_line_opts
---@field style? string  "line" (per-row markers) | "block" (single spanning block comment around the whole box, when the filetype has a block template) — default: `"line"`
---@field width? integer fixed total display width for the box (default: auto-fit)
---@field align? string  "left" | "right" | "center" — alignment within `width` (default: `"left"`)

---@class cbox.config
---@field theme string                                                    theme name selected from `presets` (default: "thin")
---@field visual_line cbox.visual_line_opts                               V-line-only wrap options (style, width, align).  Non-V-line wraps ignore these.
---@field presets table<string, cbox.preset>                              named border-character sets
---@field comment_str table<string, string|{line?: string, block?: string}>  per-filetype comment template — either a string (auto-classified) or a `{ line?, block? }` table.  Filetypes not listed fall back to `vim.bo[bufnr].commentstring`.

---@class cbox.opts
---@field theme? string                         border preset name; defaults to `config.theme`
---@field visual_line? cbox.visual_line_opts    V-line-only options (style/width/align) — partial override of `config.visual_line`

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
  local cfg_vline = M.config.visual_line or {}
  local opt_vline = opts.visual_line or {}
  return {
    theme = opts.theme or M.config.theme,
    visual_line = {
      style = opt_vline.style or cfg_vline.style or "line",
      width = opt_vline.width or cfg_vline.width,
      align = opt_vline.align or cfg_vline.align or "left",
    },
  }
end

-- ===== V-line block wrap =====
--
-- When the user wraps a V-line selection with `visual_line.style = "block"`
-- AND the filetype has a block template, emit a single spanning block
-- comment around the whole box instead of per-row line comments:
--
--   // box      →   /* ┌─────┐
--   // box             │ box │
--   // box             │ box │
--   // box             └─────┘ */
--
-- Four input shapes are recognized:
--   "both":    selection contains a full /* ... */ pair (or no comment context
--              and we wrap fresh as standard spanning).
--   "opener":  selection starts with `/*` but the closer sits OUTSIDE the
--              selection above/below — emit `/*` on its own row above the
--              new box, leave the closer where it is.
--   "closer":  selection ends with `*/` but the opener sits OUTSIDE — append
--              `*/` to the box's last row, leave the opener where it is.
--   "none":    no comment context — wrap as standard spanning.
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

  local opener = block_tpl.opener or ""
  local closer = block_tpl.closer or ""
  local before = block_tpl.before
  local after = block_tpl.after
  local before_disp = vim.fn.strdisplaywidth(before)
  local inner_indent = string.rep(" ", before_disp)

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

  -- Dissolve any existing boxes: in-place erase + drop border-only rows.
  if #boxes > 0 then
    local result =
      render.unwrap_overlapping_blockwise(lines, work_top, boxes, filetype, bufnr)
    lines = result.lines
  end

  -- Detect the comment shape.  Try full spanning via comment.strip first;
  -- fall back to dangling-delimiter detection.
  local mode -- "both" | "opener" | "closer" | "none"
  local outer_indent -- where opener row would sit (relevant for both/opener/none)
  local stripped
  local strip_ctx

  do
    local s, c = comment.strip(lines, filetype, bufnr)
    if c then
      -- Any per-line or spanning detection wins; dangling-delimiter
      -- detection is only for inputs comment.strip can't classify.
      stripped = s
      if c.is_spanning then
        mode = "both"
        outer_indent = c.indent_outer or ""
      else
        mode = "none"
        strip_ctx = c
      end
    end
  end

  if not mode then
    -- Check for dangling opener at start of row 1.
    local dangling_opener_indent
    if #lines >= 1 and #opener > 0 then
      local first = lines[1]
      local m = first:match("^(%s*)" .. vim.pesc(opener) .. "%s")
        or first:match("^(%s*)" .. vim.pesc(opener) .. "$")
      if m then
        dangling_opener_indent = m
      end
    end

    -- Check for dangling closer at end of last row.
    local dangling_closer = false
    if #lines >= 1 and #closer > 0 then
      if vim.endswith(lines[#lines], closer) then
        dangling_closer = true
      end
    end

    if dangling_opener_indent and dangling_closer then
      -- Both delimiters present but spanning detect failed (middle rows
      -- don't conform to the spanning's inner_indent).  Strip both ends
      -- and treat as "both".
      mode = "both"
      outer_indent = dangling_opener_indent
      lines[1] = lines[1]:gsub(
        "^" .. vim.pesc(dangling_opener_indent) .. vim.pesc(opener) .. "%s?",
        ""
      )
      local last = lines[#lines]
      lines[#lines] = last:sub(1, #last - #closer):gsub("%s+$", "")
      stripped = lines
    elseif dangling_opener_indent then
      mode = "opener"
      outer_indent = dangling_opener_indent
      -- Strip opener (with optional trailing space) from row 1.
      lines[1] = lines[1]:gsub(
        "^" .. vim.pesc(dangling_opener_indent) .. vim.pesc(opener) .. "%s?",
        ""
      )
      -- Strip <outer_indent><inner_indent> from rows 2..N so all rows
      -- align to the spanning's content indent before the wrap.
      local strip_w = #dangling_opener_indent + before_disp
      for i = 2, #lines do
        local row = lines[i]
        local row_indent = row:match("^(%s*)") or ""
        local w = math.min(strip_w, #row_indent)
        lines[i] = row:sub(w + 1)
      end
      stripped = lines
    elseif dangling_closer then
      mode = "closer"
      -- Strip closer (with optional leading space) from last row.
      local last = lines[#lines]
      lines[#lines] = last:sub(1, #last - #closer):gsub("%s+$", "")
      stripped = lines
      -- outer_indent computed below from common leading ws.
    else
      -- No comment context anywhere — plain content.
      mode = "none"
      stripped = lines
    end
  end

  -- For "none" and "closer", derive outer_indent from the input.
  if mode == "none" then
    if strip_ctx then
      outer_indent = strip_ctx.prefix:match("^(%s*)") or ""
    else
      outer_indent = ""
    end
  end
  -- Compute the longest common leading whitespace of the stripped content
  -- (in bytes) — this becomes additional outer indent on top of whatever
  -- the comment/dangling context already gave us.  Trailing whitespace is
  -- always dropped (symmetric with unwrap).
  if mode == "none" or mode == "closer" then
    local lead = nil
    for _, line in ipairs(stripped) do
      if line:match("%S") then
        local row_lead = line:match("^(%s*)") or ""
        if lead == nil then
          lead = row_lead
        else
          while #lead > 0 and not vim.startswith(row_lead, lead) do
            lead = lead:sub(1, -2)
          end
          if #lead == 0 then
            break
          end
        end
      end
    end
    lead = lead or ""
    for i, line in ipairs(stripped) do
      stripped[i] = line:sub(#lead + 1):gsub("%s+$", "")
    end
    if mode == "closer" then
      -- For closer-only, the selection's leading IS the box's column.
      outer_indent = lead
    else
      outer_indent = outer_indent .. lead
    end
  elseif mode == "both" or mode == "opener" then
    -- For both/opener modes, strip min common leading inside the spanning
    -- context.  Any remaining inner leading becomes additional content
    -- (preserving relative indentation between rows).
    local lead = nil
    for _, line in ipairs(stripped) do
      if line:match("%S") then
        local row_lead = line:match("^(%s*)") or ""
        if lead == nil then
          lead = row_lead
        else
          while #lead > 0 and not vim.startswith(row_lead, lead) do
            lead = lead:sub(1, -2)
          end
          if #lead == 0 then
            break
          end
        end
      end
    end
    lead = lead or ""
    for i, line in ipairs(stripped) do
      stripped[i] = line:sub(#lead + 1):gsub("%s+$", "")
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
  local vline = opts.visual_line or {}
  local render_opts = { width = vline.width, align = vline.align }
  local box_lines =
    render.wrap_lines(stripped, content_start, content_end, preset, render_opts)

  local max_w = 0
  for _, line in ipairs(box_lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_w then
      max_w = w
    end
  end

  local result = {}
  if mode == "both" or mode == "none" then
    -- Standard spanning: opener inline row 1, closer appended (padded) to
    -- the last row.  Middle rows space-indented.
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
  elseif mode == "opener" then
    -- Opener on its own row above the box (the closer is outside the
    -- selection and stays untouched in the buffer).
    table.insert(result, outer_indent .. opener)
    for _, line in ipairs(box_lines) do
      table.insert(result, outer_indent .. inner_indent .. line)
    end
  else -- mode == "closer"
    -- Box at the existing inner indent; closer appended (padded) to last
    -- row.  Opener is outside the selection and stays untouched.
    for i, line in ipairs(box_lines) do
      local trail = ""
      if i == #box_lines then
        local pad = max_w - vim.fn.strdisplaywidth(line)
        if pad > 0 then
          line = line .. string.rep(" ", pad)
        end
        trail = after
      end
      table.insert(result, outer_indent .. line .. trail)
    end
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
-- Build flat opts for the api.wrap path.  visual_line.width/align apply
-- only when the selection is V-line; non-V-line wraps drop them entirely.
local function api_opts(resolved, sel_is_linewise)
  local vline = resolved.visual_line or {}
  if sel_is_linewise then
    return { theme = resolved.theme, width = vline.width, align = vline.align }
  end
  return { theme = resolved.theme }
end

function M.box(opts)
  local detect = require("cbox.detect")
  local sel = detect.get_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local resolved = resolve_opts(opts)
  local linewise = detect.is_linewise(sel)
  if linewise and resolved.visual_line.style == "block" then
    if vline_block_wrap(sel, bufnr, resolved) then
      return
    end
  end
  require("cbox.api").wrap(sel, bufnr, api_opts(resolved, linewise))
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
  local linewise = detect.is_linewise(sel)

  -- V-line wrap with visual_line.style=block: route through the spanning-
  -- block emitter when the toggle's direction is "wrap".  Unwrap goes
  -- through api.unwrap (which demotes spanning back to per-line line).
  local function maybe_block_wrap()
    if linewise and resolved.visual_line.style == "block" then
      if vline_block_wrap(sel, bufnr, resolved) then
        return true
      end
    end
    return false
  end
  local flat = api_opts(resolved, linewise)

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
    return api.wrap(sel, bufnr, flat)
  end

  local position = detect.classify(sel, boxes).position
  if position == detect.Position.OUTSIDE then
    if maybe_block_wrap() then
      return
    end
    return api.wrap(sel, bufnr, flat)
  end

  if linewise then
    local b = boxes[1]
    local strictly_inside = sel.start_line > b.top and sel.end_line < b.bottom
    if strictly_inside and not detect.box_is_clean_linewise(b, bufnr) then
      if maybe_block_wrap() then
        return
      end
      api.wrap(sel, bufnr, flat)
    else
      api.unwrap(sel, bufnr)
    end
  elseif detect.boundaries_align(sel, boxes[1], bufnr) then
    api.unwrap(sel, bufnr)
  else
    api.wrap(sel, bufnr, flat)
  end
end

if not vim.g.cbox_loaded then
  M.setup()
end

return M
