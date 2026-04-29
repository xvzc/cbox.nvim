---@mod cbox.api API
---@brief [[
---Buffer-aware orchestration around the pure rendering primitives in
---|cbox.render|.
---
---Each entry point reads the buffer's current state, decides how the
---selection relates to nearby boxes (via |cbox.detect|), and routes to one
---of: a fresh wrap, a merge into existing borders, an erase, or a no-op.
---@brief ]]

local detect = require("cbox.detect")
local snapshot = require("cbox.snapshot")
local box = require("cbox.render")
local comment = require("cbox.comment")

local M = {}

local P = detect.Position

---@param opts? cbox.opts|string
---@return cbox.opts
local function normalize_opts(opts)
  if type(opts) == "string" then
    return { theme = opts }
  end
  return opts or {}
end

---@param edits cbox.render.edit[]
---@param bufnr integer
local function apply(edits, bufnr)
  -- Apply highest-row-first so that earlier edits cannot shift the row indices
  -- of later ones (relevant when an edit's new_lines count differs from old).
  table.sort(edits, function(a, b)
    return a.row_start > b.row_start
  end)
  for _, e in ipairs(edits) do
    vim.api.nvim_buf_set_lines(bufnr, e.row_start, e.row_end, false, e.new_lines)
  end
end

-- Strip every box in `boxes` from the buffer, returning the cleaned content
-- row's location for downstream re-wrapping.  Boxes are assumed to share rows
-- (top above selection, content on selection row, bottom below).
---@param bufnr integer
---@param boxes cbox.detect.box[]
---@return integer top_row, integer bot_row, cbox.render.unwrap_result result
local function erase_overlapping(bufnr, boxes)
  local top, bot = math.huge, 0
  for _, b in ipairs(boxes) do
    top = math.min(top, b.top)
    bot = math.max(bot, b.bottom)
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, top - 1, bot, false)
  local filetype = vim.bo[bufnr].filetype

  -- Spanning input: strip the spanning, erase boxes on the plain content,
  -- then restore as per-line line markers (always-line unwrap).  Box
  -- display ranges shift left by the stripped prefix's display width;
  -- since `<indent_outer><before>` and `<indent_outer><inner_indent>`
  -- have matching display widths, the shift is uniform across rows.
  local stripped, cmt_ctx = comment.strip(lines, filetype, bufnr)
  if cmt_ctx and cmt_ctx.is_spanning then
    local shift = vim.fn.strdisplaywidth(cmt_ctx.indent_outer .. cmt_ctx.before)
    local adjusted_boxes = {}
    for _, b in ipairs(boxes) do
      table.insert(
        adjusted_boxes,
        vim.tbl_extend("force", {}, b, {
          disp_range = {
            start = b.disp_range.start - shift,
            ["end"] = b.disp_range["end"] - shift,
          },
        })
      )
    end
    local result =
      box.unwrap_overlapping_blockwise(stripped, top, adjusted_boxes, filetype, bufnr)
    local restore_ctx = comment.demote_for_unwrap(cmt_ctx, filetype, bufnr)
    local restored = restore_ctx and comment.restore(result.lines, restore_ctx)
      or result.lines
    vim.api.nvim_buf_set_lines(bufnr, top - 1, bot, false, restored)
    return top, bot, result
  end

  local result = box.unwrap_overlapping_blockwise(lines, top, boxes, filetype, bufnr)
  vim.api.nvim_buf_set_lines(bufnr, top - 1, bot, false, result.lines)
  return top, bot, result
end

-- Map a target line (1-indexed buffer row) inside the erased range [top, bot]
-- to a 0-indexed offset into the post-erase `result.lines`.  Falls back via
-- `search_dir` ("before" walks earlier rows, "after" walks later rows) when
-- the exact row was dropped, finally defaulting to the first content row.
---@param result cbox.render.unwrap_result
---@param target_line integer
---@param top integer
---@param n_orig integer  number of rows in the original range (bot - top + 1)
---@param search_dir "before"|"after"
---@return integer
local function map_inside_offset(result, target_line, top, n_orig, search_dir)
  local r_offset = target_line - top + 1
  if r_offset < 1 then
    r_offset = 1
  elseif r_offset > n_orig then
    r_offset = n_orig
  end
  if result.row_mapping[r_offset] then
    return result.row_mapping[r_offset]
  end
  if search_dir == "before" then
    for i = r_offset - 1, 1, -1 do
      if result.row_mapping[i] then
        return result.row_mapping[i]
      end
    end
  else
    for i = r_offset + 1, n_orig do
      if result.row_mapping[i] then
        return result.row_mapping[i]
      end
    end
  end
  return result.content_row_offset_first
end

-- Strip every overlapping box and re-wrap the resulting trimmed content with
-- `preset` — used by `M.wrap` when the selection touches existing boxes.
--
-- The re-wrap targets the original selection's rows mapped to post-erase
-- coordinates (so a sel touching only one of several content rows wraps just
-- that row, not the whole stripped box).  Multi-row results re-wrap linewise
-- so rows of differing widths get padded to the widest.
---@param sel cbox.detect.selection
---@param bufnr integer
---@param boxes cbox.detect.box[]
---@param preset table
---@param presets table
---@param opts? table
local function merge_overlapping(sel, bufnr, boxes, preset, presets, opts)
  local top, bot, result = erase_overlapping(bufnr, boxes)

  local n_orig = bot - top + 1
  local first_offset = map_inside_offset(result, sel.start_line, top, n_orig, "after")
  local last_offset = map_inside_offset(result, sel.end_line, top, n_orig, "before")
  if last_offset < first_offset then
    last_offset = first_offset
  end

  local first_row = top + first_offset
  local last_row = top + last_offset
  local mode = (first_row == last_row) and sel.mode or "V"

  -- Multi-box selection: wrap only the COMBINED box-contents range (not the
  -- whole post-erase line, which would include text that was outside any
  -- box).  Single-box: keep the existing behavior of wrapping the trimmed
  -- post-erase content (so sel that extends past the box still wraps the
  -- adjacent text).
  local start_col = result.content_byte_range.start_col
  local end_col = result.content_byte_range.end_col
  if #boxes >= 2 and result.box_content_post then
    local left, right = math.huge, 0
    for _, b in ipairs(boxes) do
      local pos = result.box_content_post[b]
      if pos then
        if pos.byte_start < left then
          left = pos.byte_start
        end
        if pos.byte_end > right then
          right = pos.byte_end
        end
      end
    end
    if left ~= math.huge and right ~= 0 then
      start_col = left
      end_col = right
    end
  end

  local new_sel = {
    mode = mode,
    start_line = first_row,
    end_line = last_row,
    start_col = start_col,
    end_col = end_col,
  }
  apply(box.wrap(snapshot.take(new_sel, bufnr), preset, presets, opts), bufnr)
end

-- Linewise (V mode) variant of merge_overlapping: erase every box that
-- overlaps the selection's row range and re-wrap as a single linewise box
-- around the cleaned content.  Used when V-mode toggle hits "dirty" state
-- (partial inner boxes, multiple boxes, etc.).
---@param sel cbox.detect.selection
---@param bufnr integer
---@param boxes cbox.detect.box[]
---@param preset table
---@param presets table
---@param opts? table
local function merge_overlapping_linewise(sel, bufnr, boxes, preset, presets, opts)
  local top, bot, result = erase_overlapping(bufnr, boxes)

  local n_orig = bot - top + 1
  local row_shift = #result.lines - n_orig

  local function map_row(target_line, search_dir)
    if target_line < top then
      return target_line
    elseif target_line > bot then
      return target_line + row_shift
    else
      return top + map_inside_offset(result, target_line, top, n_orig, search_dir)
    end
  end

  local first_row = map_row(sel.start_line, "after")
  local last_row = map_row(sel.end_line, "before")
  if last_row < first_row then
    last_row = first_row
  end

  local new_sel = {
    mode = "V",
    start_line = first_row,
    end_line = last_row,
    start_col = 1,
    end_col = 1,
  }
  apply(box.wrap(snapshot.take(new_sel, bufnr), preset, presets, opts), bufnr)
end

---Draws a box around the selection.  Internally smart:
--- - If the (single-line blockwise) selection touches one or more existing
---   boxes, erase them and re-wrap so the selection is enclosed by a single
---   new box (covers "select inside box", "select wider than box", and
---   "select across multiple adjacent boxes").
--- - If the selection touches a box's border row from outside, trim the
---   border row out of the wrap range.
--- - Otherwise, wrap the selection as-is.
---@param sel cbox.detect.selection
---@param bufnr? integer
---@param opts? cbox.opts|string
function M.wrap(sel, bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  opts = normalize_opts(opts)
  local cfg = require("cbox").config
  local presets = cfg.presets
  local preset = presets[opts.theme or cfg.theme]

  local linewise = detect.is_linewise(sel)

  -- V-line wrap with `visual_line.style = "block"`: route through the
  -- spanning-block emitter when the filetype has a block template.  If
  -- there's no block template, fall through to the regular wrap.
  if linewise and opts.visual_line and opts.visual_line.style == "block" then
    if require("cbox.vline_block").wrap(sel, bufnr, opts) then
      return
    end
  end

  -- Flatten visual_line.width/align onto opts for the per-row render path.
  -- Only applies when the selection is V-line — non-V-line wraps ignore
  -- width/align entirely.
  if linewise and opts.visual_line then
    opts = vim.tbl_extend("force", opts, {
      width = opts.visual_line.width,
      align = opts.visual_line.align,
    })
  end

  local boxes = detect.find_boxes(sel, bufnr)

  if not linewise and #boxes > 0 then
    merge_overlapping(sel, bufnr, boxes, preset, presets, opts)
    return
  end

  local class = #boxes > 0 and detect.classify(sel, boxes) or { position = P.OUTSIDE }

  -- Linewise wrap with existing boxes: erase them all and re-wrap as a
  -- clean linewise box around the cleaned content.  Skip when the selection
  -- is OUTSIDE (touching a single box's border from outside) — that's a
  -- "wrap alongside" case handled by the adjusted-sel path below.
  if linewise and #boxes > 0 and class.position ~= P.OUTSIDE then
    merge_overlapping_linewise(sel, bufnr, boxes, preset, presets, opts)
    return
  end

  local effective = sel
  if class.position == P.OUTSIDE and class.adjusted then
    effective = vim.tbl_extend("force", sel, {
      start_line = class.adjusted.start_line,
      end_line = class.adjusted.end_line,
    })
  end

  apply(box.wrap(snapshot.take(effective, bufnr), preset, presets, opts), bufnr)
end

---Removes the box(es) that the selection is inside, contains, or overlaps.
---No-op when the selection is entirely outside any box (including the case
---where the selection only touches a border row from outside).
---@param sel cbox.detect.selection
---@param bufnr? integer
function M.unwrap(sel, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local presets = require("cbox").config.presets

  local boxes = detect.find_boxes(sel, bufnr)
  if #boxes == 0 then
    return
  end

  if not detect.is_linewise(sel) then
    erase_overlapping(bufnr, boxes)
    return
  end

  -- Selection might be just touching a border row from outside; classify
  -- distinguishes that (OUTSIDE + adjusted) from genuine intersection.
  if detect.classify(sel, boxes).position == P.OUTSIDE then
    return
  end

  apply(box.unwrap(snapshot.take(sel, bufnr, boxes[1]), presets), bufnr)
end

return M
