---@mod cbox.render Render
---@brief [[
---Pure rendering: turns Snapshots and lower-level inputs into Edit lists or
---transformed string lists.  No Neovim buffer API — all functions operate on
---plain string lists / tables.
---
---Border classification primitives (`top_preset` / `blockwise_preset`) and
---`byte_at_disp` live in |cbox.detect|; this module imports them.
---
---The wrap/unwrap primitives use display columns as their coordinate system,
---the same width-aware coordinate that linewise (full-line) and blockwise
---(column rectangle) ultimately share.  Comment-prefix handling is done by
---the high-level wrap/unwrap (Snapshot → Edit[]) via strip-then-restore, so
---the primitives themselves are prefix-agnostic.
---@brief ]]

local comment = require("cbox.comment")
local detect = require("cbox.detect")

local M = {}

---@class cbox.render.edit
---@field row_start integer 0-indexed (for nvim_buf_set_lines)
---@field row_end integer   0-indexed exclusive
---@field new_lines string[]

-- ===== Unified primitives: lines → lines =====

-- Pad `content` to `target_w` display columns based on `align`.
-- Trailing whitespace on `content` is treated as padding (stripped before
-- measuring) so multi-row content extracted from rows of differing widths
-- aligns based on each row's meaningful chars.
---@param content string
---@param target_w integer
---@param align "left"|"right"|"center"
---@return string
local function pad_content(content, target_w, align)
  local trimmed = content:gsub("%s+$", "")
  local current_w = vim.fn.strdisplaywidth(trimmed)
  local slack = target_w - current_w
  if slack <= 0 then
    return trimmed
  end
  if align == "right" then
    return string.rep(" ", slack) .. trimmed
  elseif align == "center" then
    local lpad = math.floor(slack / 2)
    local rpad = slack - lpad
    return string.rep(" ", lpad) .. trimmed .. string.rep(" ", rpad)
  end
  return trimmed .. string.rep(" ", slack)
end

---Wraps each line's content at display columns `[content_start, content_end]`
---with side chars from `preset`.  Lines whose display width is less than
---`content_end` are right-padded with spaces so all wrapped rows align.
---When `opts.width` is set, the box's outer display width is clamped to at
---least that value (overflow when content is wider — `opts.width` is ignored
---in that case), and content is aligned within per `opts.align`.
---Returns `{ top_border, side-wrapped lines..., bottom_border }`.
---@param lines string[]
---@param content_start integer 1-indexed display col where content begins
---@param content_end integer   1-indexed display col where content ends (inclusive)
---@param preset cbox.preset
---@param opts? cbox.opts
---@return string[]
function M.wrap_lines(lines, content_start, content_end, preset, opts)
  local tl, fill, tr = preset[1], preset[2], preset[3]
  local l, r = preset[4], preset[5]
  local bl, bfill, br = preset[6], preset[7], preset[8]

  local content_disp_width = content_end - content_start + 1
  local target_content_w = content_disp_width
  if opts and opts.width then
    -- opts.width is the outer width; subtract 2 sides + 2 inner padding spaces.
    target_content_w = math.max(opts.width - 4, content_disp_width)
  end
  local inner_disp = target_content_w + 2
  local indent_disp = content_start - 1
  local border_indent = string.rep(" ", indent_disp)
  local align = (opts and opts.align) or "left"

  local new_lines = {}
  for _, line in ipairs(lines) do
    local line_disp = vim.fn.strdisplaywidth(line)
    if line_disp < content_end then
      line = line .. string.rep(" ", content_end - line_disp)
    end
    local content_start_byte = detect.byte_at_disp(line, content_start) or 1
    local end_plus_one_byte = detect.byte_at_disp(line, content_end + 1)
    local content_end_byte = end_plus_one_byte and (end_plus_one_byte - 1) or #line
    local prefix_bytes = line:sub(1, content_start_byte - 1)
    local content = line:sub(content_start_byte, content_end_byte)
    local suffix = line:sub(content_end_byte + 1)
    local padded = pad_content(content, target_content_w, align)
    table.insert(new_lines, prefix_bytes .. l .. " " .. padded .. " " .. r .. suffix)
  end

  local top_border = border_indent .. tl .. string.rep(fill, inner_disp) .. tr
  local bot_border = border_indent .. bl .. string.rep(bfill, inner_disp) .. br

  local result = { top_border }
  vim.list_extend(result, new_lines)
  table.insert(result, bot_border)
  return result
end

---Strips a box from `lines`.  `lines[1]` is the top border, `lines[#lines]`
---is the bottom border, and the middle rows have side chars at display
---columns `l_disp` (left side) and `r_disp` (right side).  Returns the
---content rows with side chars, padding spaces, and trailing whitespace
---stripped.
---@param lines string[]
---@param l_disp integer 1-indexed display col of the left side char
---@param r_disp integer 1-indexed display col of the right side char
---@param preset cbox.preset
---@param linewise? boolean  when true, also strip leading whitespace from
---                          inner content (recovers `box` from `   box   `
---                          in centered/right-aligned linewise wraps).
---                          Blockwise calls keep leading whitespace because
---                          the caller's column selection determined it.
---@return string[]
function M.unwrap_lines(lines, l_disp, r_disp, preset, linewise)
  local l, r = preset[4], preset[5]

  local stripped = {}
  for i = 2, #lines - 1 do
    local line = lines[i]
    local l_byte = detect.byte_at_disp(line, l_disp)
    local r_byte = detect.byte_at_disp(line, r_disp)
    if not l_byte or not r_byte then
      table.insert(stripped, line)
    else
      local prefix_part = line:sub(1, l_byte - 1)
      local inner = line:sub(l_byte + #l, r_byte - 1)
      local suffix = line:sub(r_byte + #r)
      if vim.startswith(inner, " ") then
        inner = inner:sub(2)
      end
      if vim.endswith(inner, " ") then
        inner = inner:sub(1, #inner - 1)
      end
      if linewise then
        inner = inner:match("^%s*(.-)%s*$")
      else
        inner = inner:match("^(.-)%s*$")
      end
      table.insert(stripped, prefix_part .. inner .. suffix)
    end
  end
  return stripped
end

---@class cbox.render.unwrap_result
---@field lines string[]                                                cleaned lines (border-only rows dropped)
---@field content_row_offset_first integer                              0-indexed offset of the first row that formerly held box content
---@field content_byte_range { start_col: integer, end_col: integer }   trimmed content's byte range on the first content row
---@field row_mapping integer[]                                         0-indexed offset of each original row in the cleaned `lines` (nil when dropped)

-- True when `line` is empty after stripping its comment prefix (if any).  A
-- former top/bottom border row that only ever held box chars + padding will
-- look like `"-- "` after the unwrap removes the box; we want to drop it.
local function is_effectively_blank(line, filetype, bufnr)
  if line:match("^%s*$") then
    return true
  end
  local stripped = comment.strip({ line }, filetype or "", bufnr)[1]
  return stripped:match("^%s*$") ~= nil
end

---Strips one or more boxes that share top/bottom border rows.  Each box may
---span multiple content rows.
---
---Alignment-preserving erase: each box's display range on a row is replaced
---in place with content (on a content row) or with content-width spaces
---(on the border rows).  This keeps row widths consistent so other boxes on
---the same rows stay where they belong.  Border-only rows that become
---effectively blank (whitespace only, optionally after a comment prefix) are
---dropped; content rows are always preserved, even if blank after stripping.
---@param lines string[]      lines spanning rows [top_row_offset, top_row_offset+#lines-1]
---@param top_row_offset integer  1-indexed row index of `lines[1]`
---@param boxes cbox.detect.box[]
---@param filetype? string
---@param bufnr? integer       source buffer (for the `commentstring` fallback)
---@return cbox.render.unwrap_result
function M.unwrap_overlapping_blockwise(lines, top_row_offset, boxes, filetype, bufnr)
  local processed = {}
  local is_content_row = {}
  -- box → { row_offset, byte_start, byte_end } recording each box's first
  -- content row's post-erase byte range.  Used by merge_overlapping to map
  -- a multi-box selection to the combined-box-contents-only range.
  local box_content_post = {}

  for r_offset, line in ipairs(lines) do
    local row = top_row_offset + r_offset - 1

    -- Process boxes on this row from rightmost (highest display col) first
    -- so that earlier replacements don't invalidate later display→byte
    -- conversions.
    local boxes_on_row = {}
    for _, box in ipairs(boxes) do
      if row >= box.top and row <= box.bottom then
        table.insert(boxes_on_row, box)
      end
    end
    table.sort(boxes_on_row, function(a, b)
      return a.disp_range.start > b.disp_range.start
    end)

    local current = line
    local row_has_content = false
    for _, box in ipairs(boxes_on_row) do
      local box_start_byte = detect.byte_at_disp(current, box.disp_range.start)
      local end_plus_one_byte = detect.byte_at_disp(current, box.disp_range["end"] + 1)
      local box_end_byte = end_plus_one_byte and (end_plus_one_byte - 1) or #current
      if not box_start_byte then
        box_start_byte = #current + 1
      end

      local replacement
      if row > box.top and row < box.bottom then
        -- Content row: pull out the box's actual content (between the inner
        -- padding spaces) and use that as the replacement.  Trailing
        -- whitespace is the wrap_lines pad (only present when the row is
        -- shorter than the widest content), so strip it — but only when the
        -- raw content has at least one non-whitespace char, so we don't
        -- destroy whitespace-only content (e.g. a wrapped single space).
        local content_start_byte = detect.byte_at_disp(current, box.disp_range.start + 2)
        local content_end_plus_one =
          detect.byte_at_disp(current, box.disp_range["end"] - 1)
        if content_start_byte and content_end_plus_one then
          local raw = current:sub(content_start_byte, content_end_plus_one - 1)
          if raw:match("%S") then
            replacement = raw:match("^(.-)%s*$") or raw
          else
            replacement = raw
          end
        else
          replacement = ""
        end
        row_has_content = true
      else
        -- Top or bottom border row: replace with content-width spaces so the
        -- row keeps the same display width as the (now stripped) content row.
        local content_width = box.disp_range["end"] - box.disp_range.start - 3
        if content_width < 0 then
          content_width = 0
        end
        replacement = string.rep(" ", content_width)
      end

      current = current:sub(1, box_start_byte - 1)
        .. replacement
        .. current:sub(box_end_byte + 1)

      -- Track this box's content position on this row in the post-erase line.
      -- Processing is rightmost-first, so previously-recorded boxes (further
      -- right) shift LEFT by this replacement's byte savings.
      if row > box.top and row < box.bottom then
        box_content_post[box] = box_content_post[box]
          or {
            row_offset = r_offset,
            byte_start = box_start_byte,
            byte_end = box_start_byte + #replacement - 1,
          }
        local savings = (box_end_byte - box_start_byte + 1) - #replacement
        if savings ~= 0 then
          for prev_box, pos in pairs(box_content_post) do
            if
              prev_box ~= box
              and pos.row_offset == r_offset
              and pos.byte_start > box_end_byte
            then
              pos.byte_start = pos.byte_start - savings
              pos.byte_end = pos.byte_end - savings
            end
          end
        end
      end
    end

    if row_has_content then
      is_content_row[r_offset] = true
    end
    table.insert(processed, current)
  end

  -- Keep every content row; drop border-only rows that are now blank.  Rows
  -- between two stacked boxes are border-only for both, so they collapse out.
  local final = {}
  local content_offset_first
  local row_mapping = {}
  for i, line in ipairs(processed) do
    if is_content_row[i] then
      content_offset_first = content_offset_first or #final
      row_mapping[i] = #final
      table.insert(final, line)
    elseif not is_effectively_blank(line, filetype, bufnr) then
      row_mapping[i] = #final
      table.insert(final, line)
    end
  end

  -- The wrap should target the content AFTER the comment prefix and any
  -- leading whitespace inside the comment, computed from the first content row.
  local first_content_line = final[(content_offset_first or 0) + 1] or ""
  local _, cmt_ctx = comment.strip({ first_content_line }, filetype or "", bufnr)
  local prefix = (cmt_ctx and cmt_ctx.prefix) or ""
  local after_prefix = first_content_line:sub(#prefix + 1)
  local leading_ws = after_prefix:match("^(%s*)") or ""
  local trimmed = after_prefix:match("^%s*(.-)%s*$") or ""

  return {
    lines = final,
    content_row_offset_first = content_offset_first or 0,
    content_byte_range = {
      start_col = #prefix + #leading_ws + 1,
      end_col = #prefix + #leading_ws + #trimmed,
    },
    row_mapping = row_mapping,
    box_content_post = box_content_post,
  }
end

-- A byte is a valid UTF-8 sequence start when it is not a continuation
-- byte (0x80–0xBF). nil (past end-of-string) is also fine.
local function is_utf8_start(b)
  return b == nil or b <= 0x7F or b >= 0xC0
end

-- Byte-replace strategy: only structurally valid when above/below have the
-- same display layout as the content line up to start_col (e.g. existing
-- border with space-padding that matches the content line's prefix).
-- Otherwise the byte cols [start_col, end_col] on above/below land at
-- unrelated positions and the replacement cuts mid-character.
local function try_byte_replace(
  above,
  below,
  start_col,
  end_col,
  content_disp_pre,
  raw_top,
  raw_bot
)
  if
    vim.fn.strdisplaywidth(above:sub(1, start_col - 1)) ~= content_disp_pre
    or vim.fn.strdisplaywidth(below:sub(1, start_col - 1)) ~= content_disp_pre
    or not is_utf8_start(above:byte(start_col))
    or not is_utf8_start(above:byte(end_col + 1))
    or not is_utf8_start(below:byte(start_col))
    or not is_utf8_start(below:byte(end_col + 1))
  then
    return nil
  end
  return {
    above = above:sub(1, start_col - 1) .. raw_top .. above:sub(end_col + 1),
    below = below:sub(1, start_col - 1) .. raw_bot .. below:sub(end_col + 1),
  }
end

-- Display-based splice strategy: locate the disp range that aligns with the
-- sel on the content row and replace it with raw_top/raw_bot, preserving
-- anything past it verbatim (so an existing right-side border on above/below
-- shifts right by the box's expansion).  Handles the case where above/below
-- have multiple existing borders separated by whitespace gaps and the sel
-- sits inside one of those gaps — byte-replace can't cope because above/below
-- have wider chars at different byte offsets than content_line.
local function try_splice(
  above,
  below,
  box_disp_start,
  box_disp_inner_end,
  raw_top,
  raw_bot
)
  local function splice(line)
    local left_byte = detect.byte_at_disp(line, box_disp_start)
    if not left_byte then
      return nil
    end
    if vim.fn.strdisplaywidth(line:sub(1, left_byte - 1)) ~= box_disp_start - 1 then
      return nil
    end
    local right_byte = detect.byte_at_disp(line, box_disp_inner_end + 1)
    if
      right_byte
      and vim.fn.strdisplaywidth(line:sub(1, right_byte - 1)) ~= box_disp_inner_end
    then
      return nil
    end
    return line:sub(1, left_byte - 1), right_byte and line:sub(right_byte) or ""
  end
  local left_a, right_a = splice(above)
  local left_b, right_b = splice(below)
  if not (left_a and left_b) then
    return nil
  end
  return {
    above = left_a .. raw_top .. right_a,
    below = left_b .. raw_bot .. right_b,
  }
end

-- Pad-and-append strategy: when both lines end before the box's left edge,
-- pad with spaces up to that edge and append the border.  Trailing whitespace
-- on above/below is ignored — padding after the existing border shouldn't
-- block the merge, and any extra trailing space gets absorbed into the new gap.
local function try_append(above, below, box_disp_start, raw_top, raw_bot)
  local rtrim_above = above:gsub("%s+$", "")
  local rtrim_below = below:gsub("%s+$", "")
  local dw_a = vim.fn.strdisplaywidth(rtrim_above)
  local dw_b = vim.fn.strdisplaywidth(rtrim_below)
  if dw_a >= box_disp_start or dw_b >= box_disp_start then
    return nil
  end
  return {
    above = rtrim_above .. string.rep(" ", box_disp_start - 1 - dw_a) .. raw_top,
    below = rtrim_below .. string.rep(" ", box_disp_start - 1 - dw_b) .. raw_bot,
  }
end

-- Extend the new box's top/bottom borders into the rows above/below the
-- selection — but ONLY when those rows are themselves recognizable box
-- borders (so the new box visually merges into an existing one).  When the
-- adjacent rows are plain text (or only one is a border), returns nil and
-- the caller falls back to inserting fresh border rows.
--
-- Three strategies are tried in order: try_byte_replace, try_splice,
-- try_append (see each helper above for the precise applicability).
-- Returns { above, below } when one strategy succeeds, otherwise nil.
---@param above string
---@param below string
---@param content_line string  the first content line (used for the box's display range)
---@param start_col integer    1-indexed byte column on the content line
---@param end_col integer      1-indexed byte column on the content line
---@param preset table         preset for the new borders
---@param presets table        all known presets (used to verify above/below are borders)
---@param prefix? string       comment prefix to strip from above/below before detection
---@param suffix? string       comment suffix (block kind) to strip from above/below
---@return { above: string, below: string }|nil
function M.merge_into_borders(
  above,
  below,
  content_line,
  start_col,
  end_col,
  preset,
  presets,
  prefix,
  suffix
)
  -- Block-kind suffix on above/below interferes with every replace/append
  -- strategy below (it makes the line longer than box_disp_start, prevents
  -- byte-replace from finding utf-8 boundaries, and breaks rtrim).  Strip it
  -- up front and re-attach to the merged result at the end.
  local has_suffix = suffix and #suffix > 0
  if has_suffix then
    if vim.endswith(above, suffix) then
      above = above:sub(1, #above - #suffix)
    end
    if vim.endswith(below, suffix) then
      below = below:sub(1, #below - #suffix)
    end
  end

  local function strip(line)
    local s = line
    if prefix and #prefix > 0 and vim.startswith(line, prefix) then
      s = s:sub(#prefix + 1)
    end
    return s:match("^%s*(.-)%s*$")
  end
  -- Above/below need to contain AT LEAST one border pattern (not necessarily
  -- a single full-line border) — covers the case where multiple boxes are
  -- already adjacent on the row, where top_preset on the whole stripped line
  -- would fail because the "inner" between far corners contains other corners.
  if
    #detect.find_borders(strip(above), presets, false) == 0
    or #detect.find_borders(strip(below), presets, true) == 0
  then
    return nil
  end

  local content_disp_pre = vim.fn.strdisplaywidth(content_line:sub(1, start_col - 1))
  local disp_in = vim.fn.strdisplaywidth(content_line:sub(start_col, end_col))
  -- After wrap, the box's left side sits at display column box_disp_start;
  -- the right side at content_disp_pre + disp_in + 4 (l + " " + content + " " + r).
  local box_disp_start = content_disp_pre + 1
  local box_disp_inner_end = content_disp_pre + disp_in
  local inner_w = disp_in + 2

  local tl, fill, tr = preset[1], preset[2], preset[3]
  local bl, bfill, br = preset[6], preset[7], preset[8]
  local raw_top = tl .. string.rep(fill, inner_w) .. tr
  local raw_bot = bl .. string.rep(bfill, inner_w) .. br

  local result = try_byte_replace(
    above,
    below,
    start_col,
    end_col,
    content_disp_pre,
    raw_top,
    raw_bot
  ) or try_splice(above, below, box_disp_start, box_disp_inner_end, raw_top, raw_bot) or try_append(
    above,
    below,
    box_disp_start,
    raw_top,
    raw_bot
  )

  if result and has_suffix then
    result.above = result.above .. suffix
    result.below = result.below .. suffix
  end
  return result
end

-- ===== High-level: Snapshot → Edit[] =====

-- Blockwise wrap helper: when the rows immediately above and below the
-- selection are both recognizable box borders, extend them in place to merge
-- the new box into the existing one.  Returns the resulting Edit[] on
-- success, or nil to signal that the caller should fall through to a plain
-- wrap (inserting fresh border rows).
---@param snap cbox.snapshot.t
---@param stripped string[]   comment-stripped content rows
---@param content_start integer
---@param content_end integer
---@param preset table
---@param presets table
---@param opts table
---@param cmt_ctx cbox.comment.ctx|nil
---@param prefix string       comment prefix (or "")
---@return cbox.render.edit[]|nil
local function try_merge_into_adjacent_borders(
  snap,
  stripped,
  content_start,
  content_end,
  preset,
  presets,
  opts,
  cmt_ctx,
  prefix
)
  if not (snap.above and snap.below) then
    return nil
  end
  local suffix = (cmt_ctx and cmt_ctx.suffix) or ""
  local merged = M.merge_into_borders(
    snap.above,
    snap.below,
    snap.lines[1],
    snap.start_col,
    snap.end_col,
    preset,
    presets,
    prefix,
    suffix
  )
  if not merged then
    return nil
  end
  local wrapped = M.wrap_lines(stripped, content_start, content_end, preset, opts)
  local content_lines = {}
  for i = 2, #wrapped - 1 do
    table.insert(content_lines, wrapped[i])
  end
  if cmt_ctx then
    content_lines = comment.restore(content_lines, cmt_ctx)
  end
  return {
    {
      row_start = snap.above_row,
      row_end = snap.above_row + 1,
      new_lines = { merged.above },
    },
    {
      row_start = snap.row_start,
      row_end = snap.row_end,
      new_lines = content_lines,
    },
    {
      row_start = snap.below_row,
      row_end = snap.below_row + 1,
      new_lines = { merged.below },
    },
  }
end

---Wraps a Snapshot's content with a box.  Strips the common comment prefix
---(if any), determines the content's display range from the selection mode,
---runs the unified `wrap_lines` primitive, and restores the prefix.
---
---For single-line blockwise selections that sit between adjacent border
---rows (`snap.above` / `snap.below`), tries |cbox.render.merge_into_borders|
---first to extend the existing box layout.
---@param snap cbox.snapshot.t
---@param preset cbox.preset
---@param presets table<string, cbox.preset>
---@param opts? cbox.opts
---@return cbox.render.edit[]
function M.wrap(snap, preset, presets, opts)
  opts = opts or {}
  -- Only commenting input produces a commented box.  Plain input always
  -- produces a plain box, preserving wrap → unwrap reversibility regardless
  -- of filetype.
  local stripped, cmt_ctx = comment.strip(snap.lines, snap.filetype, snap.bufnr)
  local prefix = (cmt_ctx and cmt_ctx.prefix) or ""
  local prefix_bytes = #prefix

  local content_start, content_end
  if snap.is_linewise then
    -- Hoist the longest common leading whitespace of the (post-comment-strip)
    -- content lines into the box's indent: a V-line wrap of `["  foo", "  bar"]`
    -- produces "  ┌────┐ / `  │ foo │` / `  │ bar │` / `  └────┘`, not a box
    -- starting at col 1 with "  " baked into the content.  The unwrap path
    -- restores the indent automatically because the chars before the left
    -- side char are preserved as `prefix_part`.
    local common = nil
    for _, line in ipairs(stripped) do
      if line:match("%S") then
        local lws = line:match("^(%s*)") or ""
        if common == nil then
          common = lws
        else
          local n = math.min(#common, #lws)
          local i = 1
          while i <= n and common:sub(i, i) == lws:sub(i, i) do
            i = i + 1
          end
          common = common:sub(1, i - 1)
        end
      end
    end
    common = common or ""

    local max_disp = 0
    for _, line in ipairs(stripped) do
      max_disp = math.max(max_disp, vim.fn.strdisplaywidth(line))
    end
    local common_disp = vim.fn.strdisplaywidth(common)
    content_start = common_disp + 1
    content_end = math.max(max_disp, content_start)
  else
    if snap.end_col < snap.start_col or snap.end_col - snap.start_col > 10000 then
      return {}
    end
    local first = stripped[1] or ""
    local sc = snap.start_col - prefix_bytes
    local ec = snap.end_col - prefix_bytes
    content_start = vim.fn.strdisplaywidth(first:sub(1, sc - 1)) + 1
    content_end = vim.fn.strdisplaywidth(first:sub(1, ec))
    -- Empty selection on a short/empty line: ensure at least one display col
    -- of content so the box has a non-degenerate width (matches the legacy
    -- byte-based behavior of "1-byte content padded to 1 space").
    if content_end < content_start then
      content_end = content_start
    end

    local merged_edits = try_merge_into_adjacent_borders(
      snap,
      stripped,
      content_start,
      content_end,
      preset,
      presets,
      opts,
      cmt_ctx,
      prefix
    )
    if merged_edits then
      return merged_edits
    end
  end

  local wrapped = M.wrap_lines(stripped, content_start, content_end, preset, opts)
  if cmt_ctx then
    wrapped = comment.restore(wrapped, cmt_ctx)
  end
  return {
    { row_start = snap.row_start, row_end = snap.row_end, new_lines = wrapped },
  }
end

---Strips a box from a Snapshot.  Removes any comment form around the box
---(line prefix or block delim) before stripping the box itself, then
---restores the marker per line so the surviving content keeps its
---commenting.
---@param snap cbox.snapshot.t
---@param presets table<string, cbox.preset>
---@return cbox.render.edit[]
function M.unwrap(snap, presets)
  local stripped, cmt_ctx = comment.strip(snap.lines, snap.filetype, snap.bufnr)
  local prefix_bytes = (cmt_ctx and #cmt_ctx.prefix) or 0

  -- Detect preset + box display range from the stripped first line (top
  -- border) — both linewise and blockwise borders lay out the same way after
  -- the comment prefix is removed.
  local top_line = stripped[1] or ""
  local preset
  local l_disp, r_disp

  if snap.is_linewise then
    -- Find the (single) box on the comment-stripped top border row.  The box
    -- may be indented inside the comment (e.g. "  ┌─────┐") so derive
    -- l_disp/r_disp from the actual corner positions rather than assuming
    -- the box fills the line.
    local borders = detect.find_borders(top_line, presets, false)
    if #borders == 0 then
      return {}
    end
    local tb = borders[1]
    preset = tb.preset
    l_disp = vim.fn.strdisplaywidth(top_line:sub(1, tb.left_byte - 1)) + 1
    r_disp = vim.fn.strdisplaywidth(top_line:sub(1, tb.right_byte + #preset[3] - 1))
  else
    -- Blockwise: selection cols indicate where the corner chars are.
    local sc = snap.start_col - prefix_bytes
    local ec = snap.end_col - prefix_bytes
    preset = detect.blockwise_preset(top_line, sc, ec, presets)
    if not preset then
      return {}
    end
    l_disp = vim.fn.strdisplaywidth(top_line:sub(1, sc - 1)) + 1
    r_disp = vim.fn.strdisplaywidth(top_line:sub(1, ec))
  end

  local result = M.unwrap_lines(stripped, l_disp, r_disp, preset, snap.is_linewise)
  if cmt_ctx then
    result = comment.restore(result, cmt_ctx)
  end
  return {
    { row_start = snap.row_start, row_end = snap.row_end, new_lines = result },
  }
end

return M
