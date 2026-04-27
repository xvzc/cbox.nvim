local detect = require("cbox.detect")
local snapshot = require("cbox.snapshot")
local box = require("cbox.box")

local M = {}

local P = detect.Position

---@param edits Edit[]
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
---@param boxes Box[]
---@return integer top_row, integer bot_row, UnwrapOverlappingResult result
local function erase_overlapping(bufnr, boxes)
  local top, bot = math.huge, 0
  for _, b in ipairs(boxes) do
    top = math.min(top, b.top)
    bot = math.max(bot, b.bottom)
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, top - 1, bot, false)
  local filetype = vim.bo[bufnr].filetype
  local result = box.unwrap_overlapping_blockwise(lines, top, boxes, filetype)

  vim.api.nvim_buf_set_lines(bufnr, top - 1, bot, false, result.lines)
  return top, bot, result
end

-- Strip every overlapping box and re-wrap the resulting trimmed content with
-- `preset` — used by `M.wrap` when the selection touches existing boxes.
--
-- The re-wrap targets the original selection's rows mapped to post-erase
-- coordinates (so a sel touching only one of several content rows wraps just
-- that row, not the whole stripped box).  Multi-row results re-wrap linewise
-- so rows of differing widths get padded to the widest.
---@param sel Selection
---@param bufnr integer
---@param boxes Box[]
---@param preset table
---@param presets table
---@param opts? table
local function merge_overlapping(sel, bufnr, boxes, preset, presets, opts)
  local top, bot, result = erase_overlapping(bufnr, boxes)

  local n_orig = bot - top + 1
  local function map_row(target_line, search_dir)
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

  local first_offset = map_row(sel.start_line, "after")
  local last_offset = map_row(sel.end_line, "before")
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
---@param sel Selection
---@param bufnr integer
---@param boxes Box[]
---@param preset table
---@param presets table
---@param opts? table
local function merge_overlapping_linewise(sel, bufnr, boxes, preset, presets, opts)
  local top, bot, result = erase_overlapping(bufnr, boxes)

  local n_orig = bot - top + 1
  local row_shift = #result.lines - n_orig

  local function map_inside(target_line, search_dir)
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

  local function map_row(target_line, search_dir)
    if target_line < top then
      return target_line
    elseif target_line > bot then
      return target_line + row_shift
    else
      return top + map_inside(target_line, search_dir)
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

-- Draw a box around the selection.  Internally smart:
--   * If the (single-line blockwise) selection touches one or more existing
--     boxes, erase them and re-wrap so the selection is enclosed by a single
--     new box (covers "select inside box", "select wider than box", and
--     "select across multiple adjacent boxes").
--   * If the selection touches a box's border row from outside, trim the
--     border row out of the wrap range.
--   * Otherwise, wrap the selection as-is.
---@param sel Selection
---@param bufnr? integer
---@param opts? BoxOpts|string
function M.wrap(sel, bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if type(opts) == "string" then
    opts = { style = opts }
  end
  opts = opts or {}
  local cfg = require("cbox").config
  local presets = cfg.presets
  local preset = presets[opts.style or cfg.style]

  local boxes = detect.find_boxes(sel, bufnr)

  if not detect.is_linewise(sel) and #boxes > 0 then
    merge_overlapping(sel, bufnr, boxes, preset, presets, opts)
    return
  end

  -- Linewise wrap with existing boxes: erase them all and re-wrap as a
  -- clean linewise box around the cleaned content.  Skip when the selection
  -- is OUTSIDE (touching a single box's border from outside) — that's a
  -- "wrap alongside" case handled by the adjusted-sel path below.
  if detect.is_linewise(sel) and #boxes > 0 then
    local class = detect.classify(sel, boxes)
    if class.position ~= P.OUTSIDE then
      merge_overlapping_linewise(sel, bufnr, boxes, preset, presets, opts)
      return
    end
  end

  local result = detect.classify(sel, boxes)
  local effective = sel
  if result.position == P.OUTSIDE and result.adjusted then
    effective = vim.tbl_extend("force", sel, {
      start_line = result.adjusted.start_line,
      end_line = result.adjusted.end_line,
    })
  end

  apply(box.wrap(snapshot.take(effective, bufnr), preset, presets, opts), bufnr)
end

-- Remove the box(es) that the selection is inside, contains, or overlaps.
-- No-op when the selection is entirely outside any box (including the case
-- where the selection only touches a border row from outside).
---@param sel Selection
---@param bufnr? integer
---@param opts? BoxOpts|string
function M.unwrap(sel, bufnr, opts)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if type(opts) == "string" then
    opts = { style = opts }
  end
  opts = opts or {}
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

  apply(box.unwrap(snapshot.take(sel, bufnr, boxes[1]), presets, opts), bufnr)
end

return M
