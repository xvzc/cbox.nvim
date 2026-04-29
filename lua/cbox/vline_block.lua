---@mod cbox.vline_block VLine block wrap
---@brief [[
---V-line spanning block wrap.  When the user wraps a V-line selection with
---`visual_line.style = "block"` AND the filetype has a block template,
---|cbox.vline_block.wrap| emits a single spanning block comment around
---the whole box instead of per-row line comments.
---
---Four input shapes are recognized:
---  - `"both"`   — selection contains a full `/* ... */` pair (or no comment
---                 context); emit standard spanning around the new box.
---  - `"opener"` — selection starts with `/*` but the closer sits OUTSIDE
---                 the selection; emit `/*` on its own row above the box.
---  - `"closer"` — selection ends with `*/` but the opener sits OUTSIDE;
---                 append `*/` to the box's last row.
---  - `"none"`   — no comment context; wrap as standard spanning.
---@brief ]]

local comment = require("cbox.comment")
local detect = require("cbox.detect")
local render = require("cbox.render")

local M = {}

-- Longest common leading whitespace prefix (bytes) across non-blank rows.
---@param lines string[]
---@return string
local function common_leading(lines)
  local lead
  for _, line in ipairs(lines) do
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
  return lead or ""
end

-- Expand the selection's row range to enclose any boxes that overlap it,
-- read the buffer slice, and dissolve those boxes in place.  Returns the
-- cleaned lines + the work range.
---@param sel cbox.detect.selection
---@param bufnr integer
---@param filetype string
---@return string[] lines, integer work_top, integer work_bot
local function read_and_dissolve(sel, bufnr, filetype)
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
  if #boxes > 0 and #lines > 0 then
    local result =
      render.unwrap_overlapping_blockwise(lines, work_top, boxes, filetype, bufnr)
    lines = result.lines
  end
  return lines, work_top, work_bot
end

-- Classify the input lines.  Try a full spanning detection first via
-- `comment.strip`; fall back to dangling-delimiter checks at the boundary
-- rows; otherwise treat as plain content.
---@param lines string[]
---@param block_tpl cbox.comment.template
---@param filetype string
---@param bufnr integer
---@return string mode "both"|"opener"|"closer"|"none"
---@return string[] stripped (mutated lines after stripping the boundary delimiters)
---@return string outer_indent
---@return cbox.comment.ctx|nil strip_ctx
local function classify(lines, block_tpl, filetype, bufnr)
  local opener = block_tpl.opener or ""
  local closer = block_tpl.closer or ""
  local before_disp = vim.fn.strdisplaywidth(block_tpl.before)

  local stripped, ctx = comment.strip(lines, filetype, bufnr)
  if ctx then
    if ctx.is_spanning then
      return "both", stripped, ctx.indent_outer or "", nil
    end
    return "none", stripped, "", ctx
  end

  local opener_indent
  if #lines >= 1 and #opener > 0 then
    local first = lines[1]
    opener_indent = first:match("^(%s*)" .. vim.pesc(opener) .. "%s")
      or first:match("^(%s*)" .. vim.pesc(opener) .. "$")
  end
  local has_closer = #lines >= 1 and #closer > 0 and vim.endswith(lines[#lines], closer)

  if opener_indent and has_closer then
    -- Both delimiters but spanning detect failed (middle rows don't conform
    -- to inner_indent).  Strip both ends, treat as "both".
    lines[1] =
      lines[1]:gsub("^" .. vim.pesc(opener_indent) .. vim.pesc(opener) .. "%s?", "")
    local last = lines[#lines]
    lines[#lines] = last:sub(1, #last - #closer):gsub("%s+$", "")
    return "both", lines, opener_indent, nil
  end

  if opener_indent then
    -- Strip opener (with optional space) from row 1.
    lines[1] =
      lines[1]:gsub("^" .. vim.pesc(opener_indent) .. vim.pesc(opener) .. "%s?", "")
    -- Strip <outer_indent><inner_indent> from rows 2..N so all rows align
    -- to the spanning's content indent before the wrap.
    local strip_w = #opener_indent + before_disp
    for i = 2, #lines do
      local row = lines[i]
      local row_indent = row:match("^(%s*)") or ""
      lines[i] = row:sub(math.min(strip_w, #row_indent) + 1)
    end
    return "opener", lines, opener_indent, nil
  end

  if has_closer then
    -- Strip closer (with optional leading space) from last row.
    local last = lines[#lines]
    lines[#lines] = last:sub(1, #last - #closer):gsub("%s+$", "")
    return "closer", lines, "", nil
  end

  return "none", lines, "", nil
end

-- Strip per-row trailing whitespace and the common leading prefix.  Returns
-- the augmented outer_indent (for "none"/"closer" the leading folds into
-- the box's column).
---@param stripped string[]
---@param mode string
---@param outer_indent string
---@param strip_ctx cbox.comment.ctx|nil
---@return string outer_indent (possibly extended)
local function normalize(stripped, mode, outer_indent, strip_ctx)
  if mode == "none" and strip_ctx then
    outer_indent = strip_ctx.prefix:match("^(%s*)") or ""
  end
  local lead = common_leading(stripped)
  for i, line in ipairs(stripped) do
    stripped[i] = line:sub(#lead + 1):gsub("%s+$", "")
  end
  if mode == "closer" then
    return lead
  end
  if mode == "none" then
    return outer_indent .. lead
  end
  -- For "both"/"opener", outer_indent stays as the spanning's outer; any
  -- common inner leading was just stripped (relative indents preserved).
  return outer_indent
end

-- Wrap `stripped` in a raw box and emit the spanning structure for `mode`.
---@param stripped string[]
---@param mode string
---@param outer_indent string
---@param block_tpl cbox.comment.template
---@param preset cbox.preset
---@param render_opts table
---@return string[]
local function build_output(stripped, mode, outer_indent, block_tpl, preset, render_opts)
  local before = block_tpl.before
  local after = block_tpl.after
  local opener = block_tpl.opener or ""
  local before_disp = vim.fn.strdisplaywidth(before)
  local inner_indent = string.rep(" ", before_disp)

  local max_disp = 0
  for _, line in ipairs(stripped) do
    max_disp = math.max(max_disp, vim.fn.strdisplaywidth(line))
  end
  local box_lines =
    render.wrap_lines(stripped, 1, math.max(max_disp, 1), preset, render_opts)

  local max_w = 0
  for _, line in ipairs(box_lines) do
    local w = vim.fn.strdisplaywidth(line)
    if w > max_w then
      max_w = w
    end
  end
  local function pad_last(line)
    local pad = max_w - vim.fn.strdisplaywidth(line)
    return pad > 0 and (line .. string.rep(" ", pad)) or line
  end

  local result = {}
  if mode == "both" or mode == "none" then
    -- Standard spanning: opener inline row 1, closer appended to last row.
    for i, line in ipairs(box_lines) do
      local lead = (i == 1) and (outer_indent .. before) or (outer_indent .. inner_indent)
      if i == #box_lines then
        table.insert(result, lead .. pad_last(line) .. after)
      else
        table.insert(result, lead .. line)
      end
    end
  elseif mode == "opener" then
    -- Opener on its own row; closer stays outside the selection.
    table.insert(result, outer_indent .. opener)
    for _, line in ipairs(box_lines) do
      table.insert(result, outer_indent .. inner_indent .. line)
    end
  else -- "closer"
    -- Closer appended to last row; opener stays outside the selection.
    for i, line in ipairs(box_lines) do
      if i == #box_lines then
        table.insert(result, outer_indent .. pad_last(line) .. after)
      else
        table.insert(result, outer_indent .. line)
      end
    end
  end
  return result
end

---Wraps a V-line selection with a spanning block comment.  Returns true on
---success; false when the filetype has no block template (caller should
---fall back to the regular per-row wrap).
---@param sel cbox.detect.selection
---@param bufnr integer
---@param opts cbox.opts
---@return boolean
function M.wrap(sel, bufnr, opts)
  local cfg = require("cbox").config
  local filetype = vim.bo[bufnr].filetype
  local block_tpl = comment.resolve_template(filetype, bufnr, "block")
  if not block_tpl or block_tpl.kind ~= "block" then
    return false
  end

  local lines, work_top, work_bot = read_and_dissolve(sel, bufnr, filetype)
  if #lines == 0 then
    return false
  end

  local mode, stripped, outer_indent, strip_ctx =
    classify(lines, block_tpl, filetype, bufnr)
  outer_indent = normalize(stripped, mode, outer_indent, strip_ctx)

  local preset = cfg.presets[opts.theme or cfg.theme]
  local vline = opts.visual_line or {}
  local render_opts = { width = vline.width, align = vline.align }
  local result =
    build_output(stripped, mode, outer_indent, block_tpl, preset, render_opts)

  vim.api.nvim_buf_set_lines(bufnr, work_top - 1, work_bot, false, result)
  return true
end

return M
