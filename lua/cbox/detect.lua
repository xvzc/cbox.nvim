---@mod cbox.detect Detect
---@brief [[
---Box discovery, geometry, and selection capture.
---
---Given a Neovim selection, |cbox.detect.find_boxes| locates every existing
---box that intersects the selection, |cbox.detect.classify| labels how the
---selection sits relative to those boxes (INSIDE / OVERLAPPING / OUTSIDE),
---and |cbox.detect.boundaries_align| answers the toggle dispatcher's
---"strip vs. merge" question.  |cbox.detect.get_selection| also captures the
---current selection (visual or cursor-mode word span).
---@brief ]]

local cbox = require("cbox")
local comment = require("cbox.comment")

local M = {}

---@alias cbox.detect.position string `"inside"` | `"overlapping"` | `"outside"`
M.Position = {
  INSIDE = "inside",
  OVERLAPPING = "overlapping",
  OUTSIDE = "outside",
}

-- ===== Pure helpers =====

-- Check that `s` is entirely composed of repetitions of `fill`.
-- Needed because Lua patterns are byte-level: "─+" only repeats the last
-- byte of the 3-byte sequence, not the full character.
---@param s string
---@param fill string
---@return boolean
local function all_fill(s, fill)
  if s == "" then
    return true
  end
  if #fill == 0 or #s % #fill ~= 0 then
    return false
  end
  for i = 1, #s, #fill do
    if s:sub(i, i + #fill - 1) ~= fill then
      return false
    end
  end
  return true
end

---Finds the byte position of the character that occupies display column
---`target_disp` (1-indexed) on `line`.  Walks char-by-char rather than
---slicing prefixes because `strdisplaywidth` on a partial UTF-8 sequence is
---undefined.
---@param line string
---@param target_disp integer
---@return integer|nil
function M.byte_at_disp(line, target_disp)
  if target_disp <= 0 then
    return nil
  end
  local pos = 1
  local cum_disp = 0
  while pos <= #line do
    local b = string.byte(line, pos)
    local n
    if b < 0x80 then
      n = 1
    elseif b < 0xC0 then
      return nil
    elseif b < 0xE0 then
      n = 2
    elseif b < 0xF0 then
      n = 3
    else
      n = 4
    end
    local w = vim.fn.strdisplaywidth(line:sub(pos, pos + n - 1))
    if cum_disp + 1 <= target_disp and target_disp <= cum_disp + w then
      return pos
    end
    cum_disp = cum_disp + w
    pos = pos + n
  end
  return nil
end

-- Find every `lc ... rc` border pattern on a line (with `fill` between).
-- When `is_bottom` is true, looks for bl/fill/br instead of tl/fill/tr.
-- Returns list of { left_byte, right_byte, preset } where left_byte and
-- right_byte are the byte positions of the corner chars themselves.
---@param line string
---@param presets table
---@param is_bottom boolean
---@return table[]
local function parse_borders_on_line(line, presets, is_bottom)
  local result = {}
  for _, preset in pairs(presets) do
    local lc, fill, rc
    if is_bottom then
      lc, fill, rc = preset[6], preset[7], preset[8]
    else
      lc, fill, rc = preset[1], preset[2], preset[3]
    end
    if #lc > 0 and #fill > 0 and #rc > 0 then
      local pos = 1
      while pos + #lc - 1 <= #line do
        if line:sub(pos, pos + #lc - 1) == lc then
          local j = pos + #lc
          while j + #fill - 1 <= #line and line:sub(j, j + #fill - 1) == fill do
            j = j + #fill
          end
          if
            j > pos + #lc
            and j + #rc - 1 <= #line
            and line:sub(j, j + #rc - 1) == rc
          then
            table.insert(result, { left_byte = pos, right_byte = j, preset = preset })
            pos = j + #rc
          else
            pos = pos + 1
          end
        else
          pos = pos + 1
        end
      end
    end
  end
  return result
end

-- ===== Public border-preset primitives =====

---Returns every `lc ... rc` border pattern of either kind on `line`.  Used
---by |cbox.render.merge_into_borders| to check whether an adjacent row
---contains at least one border pattern, even when multiple boxes are
---present (where |cbox.detect.top_preset| on the full stripped line would
---fail because the "inner" between far corners contains other corners and
---is not all-fill).
---@param line string
---@param presets table<string, cbox.preset>
---@param is_bottom boolean
---@return table[]
function M.find_borders(line, presets, is_bottom)
  return parse_borders_on_line(line, presets, is_bottom)
end

---Detects which preset's top border matches `line`.  Returns the preset
---table or nil.
---@param line string
---@param presets table<string, cbox.preset>
---@return cbox.preset|nil
function M.top_preset(line, presets)
  for _, preset in pairs(presets) do
    local tl, fill, tr = preset[1], preset[2], preset[3]
    if vim.startswith(line, tl) and vim.endswith(line, tr) then
      local inner = line:sub(#tl + 1, #line - #tr)
      if all_fill(inner, fill) then
        return preset
      end
    end
  end
  return nil
end

---Detects which preset matches a blockwise border at specific byte columns.
---@param line string
---@param start_col integer 1-indexed byte column of the left corner char
---@param end_col integer   1-indexed byte column of the right corner char
---@param presets table<string, cbox.preset>
---@return cbox.preset|nil
function M.blockwise_preset(line, start_col, end_col, presets)
  for _, preset in pairs(presets) do
    local tl, fill, tr = preset[1], preset[2], preset[3]
    if
      line:sub(start_col, start_col + #tl - 1) == tl
      and line:sub(end_col, end_col + #tr - 1) == tr
    then
      local inner = line:sub(start_col + #tl, end_col - 1)
      if all_fill(inner, fill) then
        return preset
      end
    end
  end
  return nil
end

-- ===== Selection helpers =====

---@class cbox.detect.selection
---@field mode string "V"|"v"|"<C-v>"
---@field start_line integer 1-indexed
---@field end_line integer 1-indexed
---@field start_col integer 1-indexed byte column
---@field end_col integer 1-indexed byte column

---True iff `sel` represents a linewise selection (V mode, or v mode that
---spans multiple rows).
---@param sel cbox.detect.selection
---@return boolean
function M.is_linewise(sel)
  return sel.mode == "V" or (sel.mode == "v" and sel.start_line ~= sel.end_line)
end

local is_linewise = M.is_linewise

-- ===== Box construction =====

---@class cbox.detect.byte_range
---@field left_byte integer
---@field right_byte integer

---@class cbox.detect.box
---@field top integer                                  1-indexed top border row
---@field bottom integer                               1-indexed bottom border row
---@field preset cbox.preset
---@field top_range cbox.detect.byte_range             byte cols on top row
---@field bottom_range cbox.detect.byte_range          byte cols on bottom row
---@field side_range cbox.detect.byte_range            byte cols on the (single) content row
---@field disp_range { start: integer, end: integer }  display col range of the box (l..r inclusive)

-- Build a full Box descriptor given a parsed top border.  Walks downward
-- looking for the matching bottom border, validating each intermediate row as
-- a content row (l/r side chars at the expected display cols).  Returns nil
-- when the box is invalid (no matching bottom, or a content row's borders
-- don't line up).
--
-- side_range tracks byte positions on the FIRST content row.  Multi-content
-- row boxes drawn by `box.wrap_blockwise` have consistent byte cols across
-- content rows of the same width; mixed-width content rows aren't expected.
---@param top_row integer
---@param tb_info { left_byte: integer, right_byte: integer, preset: table }
---@param top_line string
---@param read_line fun(row: integer): string
---@param count integer
---@return cbox.detect.box|nil
local function build_box(top_row, tb_info, top_line, read_line, count)
  local preset = tb_info.preset

  local tb_disp_start = vim.fn.strdisplaywidth(top_line:sub(1, tb_info.left_byte - 1)) + 1
  local tb_disp_end =
    vim.fn.strdisplaywidth(top_line:sub(1, tb_info.right_byte + #preset[3] - 1))

  local l, r = preset[4], preset[5]
  local first_left_byte, first_right_byte
  local bottom_row, matched_bb

  for cur = top_row + 1, count do
    local line = read_line(cur)

    local bottoms = parse_borders_on_line(line, cbox.config.presets, true)
    for _, bb in ipairs(bottoms) do
      if bb.preset == preset then
        local bb_disp_start = vim.fn.strdisplaywidth(line:sub(1, bb.left_byte - 1)) + 1
        local bb_disp_end =
          vim.fn.strdisplaywidth(line:sub(1, bb.right_byte + #preset[8] - 1))
        if bb_disp_start == tb_disp_start and bb_disp_end == tb_disp_end then
          matched_bb = bb
          bottom_row = cur
          break
        end
      end
    end
    if matched_bb then
      break
    end

    -- Verify content row: l at tb_disp_start, r at tb_disp_end.
    local l_byte = M.byte_at_disp(line, tb_disp_start)
    local r_byte = M.byte_at_disp(line, tb_disp_end)
    if not l_byte or not r_byte then
      return nil
    end
    if line:sub(l_byte, l_byte + #l - 1) ~= l then
      return nil
    end
    if line:sub(r_byte, r_byte + #r - 1) ~= r then
      return nil
    end
    if cur == top_row + 1 then
      first_left_byte = l_byte
      first_right_byte = r_byte
    end
  end

  if not bottom_row or not first_left_byte then
    return nil
  end

  return {
    top = top_row,
    bottom = bottom_row,
    preset = preset,
    top_range = { left_byte = tb_info.left_byte, right_byte = tb_info.right_byte },
    bottom_range = {
      left_byte = matched_bb.left_byte,
      right_byte = matched_bb.right_byte,
    },
    side_range = { left_byte = first_left_byte, right_byte = first_right_byte },
    disp_range = { start = tb_disp_start, ["end"] = tb_disp_end },
  }
end

-- ===== Find boxes for a selection =====

-- How many rows above `sel.start_line` to search for top-border patterns when
-- looking for boxes that contain the selection.  Tall boxes (many content
-- rows) need a larger window; the limit caps work in pathological cases.
local SCAN_BACK = 50

---Finds every box whose row range AND column range intersect the
---selection's bounding rectangle.  For linewise selections, the column
---dimension is treated as unbounded (any box on a touched row is included).
---For blockwise selections, both dimensions must overlap.
---@param sel cbox.detect.selection
---@param bufnr? integer
---@return cbox.detect.box[]
function M.find_boxes(sel, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local presets = cbox.config.presets
  local count = vim.api.nvim_buf_line_count(bufnr)
  local linewise = is_linewise(sel)

  -- Lazy single-row reader with a cache: rows visited by both find_boxes
  -- (top-border scan) and build_box (downward content/bottom walk) are read
  -- exactly once per find_boxes call.
  local line_cache = {}
  local function read_line(row)
    local cached = line_cache[row]
    if cached ~= nil then
      return cached
    end
    local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
    line_cache[row] = line
    return line
  end

  local sel_disp_start, sel_disp_end
  if not linewise then
    local sel_ref_line = read_line(sel.start_line)
    sel_disp_start = vim.fn.strdisplaywidth(sel_ref_line:sub(1, sel.start_col - 1)) + 1
    sel_disp_end = vim.fn.strdisplaywidth(sel_ref_line:sub(1, sel.end_col))
  end

  local boxes = {}
  local seen = {}

  local scan_start = math.max(1, sel.start_line - SCAN_BACK)
  local scan_end = math.min(count, sel.end_line)

  for r = scan_start, scan_end do
    local top_line = read_line(r)
    local top_borders = parse_borders_on_line(top_line, presets, false)
    for _, tb in ipairs(top_borders) do
      local box = build_box(r, tb, top_line, read_line, count)
      if box and box.bottom >= sel.start_line and box.top <= sel.end_line then
        local col_overlap = linewise
          or (
            box.disp_range.start <= sel_disp_end
            and box.disp_range["end"] >= sel_disp_start
          )
        if col_overlap then
          local key = box.top .. ":" .. box.top_range.left_byte
          if not seen[key] then
            seen[key] = true
            table.insert(boxes, box)
          end
        end
      end
    end
  end

  return boxes
end

---True iff `box` cleanly wraps the linewise content of its content rows —
---i.e. on every content row, the only non-whitespace chars (after the
---comment prefix is stripped) lie inside the box's display range.  Used by
---the V-mode toggle dispatcher to decide between "unwrap this clean box"
---and "erase the partial box and re-wrap as a proper linewise box".
---@param box cbox.detect.box
---@param bufnr integer
---@return boolean
function M.box_is_clean_linewise(box, bufnr)
  local filetype = vim.bo[bufnr].filetype
  for r = box.top + 1, box.bottom - 1 do
    local line = vim.api.nvim_buf_get_lines(bufnr, r - 1, r, false)[1] or ""
    local stripped_lines, ctx = comment.strip({ line }, filetype)
    local stripped = stripped_lines[1] or ""
    local prefix_disp = (ctx and vim.fn.strdisplaywidth(ctx.prefix)) or 0

    local stripped_disp_start = box.disp_range.start - prefix_disp
    local stripped_disp_end = box.disp_range["end"] - prefix_disp

    if stripped_disp_start > 1 then
      local left_byte = M.byte_at_disp(stripped, stripped_disp_start) or (#stripped + 1)
      if stripped:sub(1, left_byte - 1):match("%S") then
        return false
      end
    end

    local stripped_disp = vim.fn.strdisplaywidth(stripped)
    if stripped_disp > stripped_disp_end then
      local right_byte = M.byte_at_disp(stripped, stripped_disp_end + 1)
      if right_byte and stripped:sub(right_byte):match("%S") then
        return false
      end
    end
  end
  return true
end

-- ===== Classification =====

---@class cbox.detect.adjusted_range
---@field start_line integer
---@field end_line integer

---@class cbox.detect.result
---@field position cbox.detect.position
---@field boxes cbox.detect.box[]                empty when OUTSIDE
---@field adjusted? cbox.detect.adjusted_range

---True iff the selection's boundaries don't cross the box's boundaries —
---one fully contains the other (sel ⊆ box, or box ⊆ sel) in both row and
---(for blockwise) column dimensions.  Used by toggle dispatch: when
---boundaries align, the user's intent is "remove this box"; when they
---cross (partial overlap), it's "merge the box into a wider wrap".
---@param sel cbox.detect.selection
---@param box cbox.detect.box
---@param bufnr integer
---@return boolean
function M.boundaries_align(sel, box, bufnr)
  local sel_rows_in_box = sel.start_line >= box.top and sel.end_line <= box.bottom
  local box_rows_in_sel = box.top >= sel.start_line and box.bottom <= sel.end_line
  local rows_align = sel_rows_in_box or box_rows_in_sel
  if not rows_align then
    return false
  end
  if is_linewise(sel) then
    return true
  end
  local content_line = vim.api.nvim_buf_get_lines(
    bufnr,
    sel.start_line - 1,
    sel.start_line,
    false
  )[1] or ""
  local sel_disp_start = vim.fn.strdisplaywidth(content_line:sub(1, sel.start_col - 1))
    + 1
  local sel_disp_end = vim.fn.strdisplaywidth(content_line:sub(1, sel.end_col))
  local sel_cols_in_box = sel_disp_start >= box.disp_range.start
    and sel_disp_end <= box.disp_range["end"]
  local box_cols_in_sel = box.disp_range.start >= sel_disp_start
    and box.disp_range["end"] <= sel_disp_end
  return sel_cols_in_box or box_cols_in_sel
end

---Classifies a selection given the boxes it intersects (typically obtained
---via |cbox.detect.find_boxes|).  Single-box semantics: entirely contained
---→ INSIDE; touching only the top or bottom border row from outside →
---OUTSIDE + adjusted; otherwise → OVERLAPPING.  Multiple boxes →
---OVERLAPPING with all of them.  Empty list → OUTSIDE.
---@param sel cbox.detect.selection
---@param boxes cbox.detect.box[]
---@return cbox.detect.result
function M.classify(sel, boxes)
  if #boxes == 0 then
    return { position = M.Position.OUTSIDE, boxes = {} }
  end

  if #boxes == 1 then
    local box = boxes[1]
    local sel_start, sel_end = sel.start_line, sel.end_line

    if sel_start >= box.top and sel_end <= box.bottom then
      return { position = M.Position.INSIDE, boxes = boxes }
    end

    if sel_end == box.top and sel_start < box.top then
      return {
        position = M.Position.OUTSIDE,
        boxes = boxes,
        adjusted = { start_line = sel_start, end_line = box.top - 1 },
      }
    end

    if sel_start == box.bottom and sel_end > box.bottom then
      return {
        position = M.Position.OUTSIDE,
        boxes = boxes,
        adjusted = { start_line = box.bottom + 1, end_line = sel_end },
      }
    end

    return {
      position = M.Position.OVERLAPPING,
      boxes = boxes,
      adjusted = { start_line = box.top, end_line = box.bottom },
    }
  end

  return { position = M.Position.OVERLAPPING, boxes = boxes }
end

-- ===== Selection capture =====

-- Set of every character (multi-byte sequences too) used by any preset.
-- Cached lazily on first access; word-boundary detection in the cursor-mode
-- selection treats these as boundaries so the selection doesn't extend
-- through adjacent box-drawing chars.
local box_char_set_cache
local function box_char_set()
  if box_char_set_cache then
    return box_char_set_cache
  end
  local set = {}
  for _, preset in pairs(cbox.config.presets) do
    for _, c in ipairs(preset) do
      if c and #c > 0 then
        set[c] = true
      end
    end
  end
  box_char_set_cache = set
  return set
end

-- Number of bytes in the UTF-8 char that starts at `byte_pos`.
local function utf8_char_bytes(line, byte_pos)
  local b = line:byte(byte_pos)
  if not b then
    return 0
  end
  if b < 0x80 then
    return 1
  end
  if b < 0xC0 then
    return 0 -- continuation byte; not a valid start
  end
  if b < 0xE0 then
    return 2
  end
  if b < 0xF0 then
    return 3
  end
  return 4
end

-- Find the byte position of the UTF-8 char that contains `byte_pos`.
local function char_start_byte(line, byte_pos)
  local p = byte_pos
  while p > 0 do
    local b = line:byte(p)
    if not b then
      return nil
    end
    if b < 0x80 or b >= 0xC0 then
      return p
    end
    p = p - 1
  end
  return nil
end

local function is_word_boundary(c, box_set)
  if not c or c == "" then
    return true
  end
  if c:match("^%s$") then
    return true
  end
  if box_set[c] then
    return true
  end
  return false
end

-- Build a blockwise single-column or word-span selection from cursor in normal mode.
---@return cbox.detect.selection
local function normal_mode_selection()
  local Cv = vim.keycode("<C-v>")
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local col0 = cursor[2]

  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
  local box_set = box_char_set()

  -- Resolve the char that contains the cursor (cursor may land on a
  -- continuation byte mid-multi-byte char).
  local cursor_byte = col0 + 1
  local cur_start = char_start_byte(line, cursor_byte) or cursor_byte
  local cur_n = utf8_char_bytes(line, cur_start)
  local cur_char = (cur_n > 0) and line:sub(cur_start, cur_start + cur_n - 1) or ""

  if is_word_boundary(cur_char, box_set) then
    local col1 = cur_start
    return {
      mode = Cv,
      start_line = row,
      end_line = row,
      start_col = col1,
      end_col = col1,
    }
  end

  -- Walk back to start of word, char-by-char.
  local sc = cur_start
  while sc > 1 do
    local prev_start = char_start_byte(line, sc - 1)
    if not prev_start then
      break
    end
    local prev_n = utf8_char_bytes(line, prev_start)
    local prev_char = (prev_n > 0) and line:sub(prev_start, prev_start + prev_n - 1) or ""
    if is_word_boundary(prev_char, box_set) then
      break
    end
    sc = prev_start
  end

  -- Walk forward to end of word, char-by-char.
  local ec = cur_start + cur_n - 1
  while ec < #line do
    local next_start = ec + 1
    local next_n = utf8_char_bytes(line, next_start)
    if next_n == 0 then
      break
    end
    local next_char = line:sub(next_start, next_start + next_n - 1)
    if is_word_boundary(next_char, box_set) then
      break
    end
    ec = next_start + next_n - 1
  end

  return {
    mode = Cv,
    start_line = row,
    end_line = row,
    start_col = sc,
    end_col = ec,
  }
end

---Captures the current selection as a |cbox.detect.selection| value.
---Reads from visual mode if active; otherwise builds a single-row blockwise
---selection covering the word under the cursor.
---@return cbox.detect.selection
function M.get_selection()
  -- vim.fn.mode() returns the *current* mode (accurate when called from a
  -- visual-mode mapping whose Lua function runs before Neovim exits visual).
  -- vim.fn.visualmode() returns the *last* visual mode (accurate when the
  -- keymap has already exited visual before invoking Lua, e.g. <Cmd> maps).
  -- Prefer mode() while we are still in a visual mode; fall back otherwise.
  local Cv = vim.keycode("<C-v>")
  local raw = vim.fn.mode()

  if raw == "n" then
    return normal_mode_selection()
  end

  local mode = (raw == "v" or raw == "V" or raw == Cv) and raw or vim.fn.visualmode()

  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")

  -- For linewise visual (V), Neovim sets '> col to v:maxcol (2^31-1).
  -- Clamp to 1 so downstream code cannot accidentally dispatch to the
  -- blockwise path with a multi-billion-byte column span.
  local start_col = start_pos[3]
  local end_col = end_pos[3]
  if mode == "V" then
    start_col = 1
    end_col = 1
  end

  return {
    mode = mode,
    start_line = start_pos[2],
    end_line = end_pos[2],
    start_col = start_col,
    end_col = end_col,
  }
end

return M
