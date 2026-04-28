---@mod cbox.snapshot Snapshot
---@brief [[
---Builds Snapshot tables from a Selection plus buffer state.  The only impure
---module besides |cbox.api|: it reads from the buffer.  Downstream consumers
---(|cbox.render|) operate on Snapshots without touching the buffer themselves,
---which keeps rendering pure and easy to test.
---@brief ]]

local detect = require("cbox.detect")

local M = {}

---@class cbox.snapshot.t
---@field lines string[]
---@field row_start integer  0-indexed (for nvim_buf_set_lines)
---@field row_end integer    0-indexed exclusive
---@field start_col integer  1-indexed byte column
---@field end_col integer    1-indexed byte column
---@field filetype string
---@field bufnr integer      source buffer (used by comment.strip for the commentstring fallback)
---@field is_linewise boolean
---@field above? string      adjacent line above (single-line blockwise wrap only)
---@field below? string      adjacent line below
---@field above_row? integer 0-indexed row of `above`
---@field below_row? integer 0-indexed row of `below`

---Captures the buffer state needed by |cbox.render.wrap| and |cbox.render.unwrap|.
---
---Without `box_extent`, the row range comes from the selection (wrap
---scenario); for blockwise selections, the rows immediately above and below
---the selection are captured too so `box.wrap` can merge into existing
---border rows.  With `box_extent`, the row range comes from the box's extent
---(unwrap scenario).
---@param sel cbox.detect.selection
---@param bufnr integer
---@param box_extent? cbox.detect.box
---@return cbox.snapshot.t
function M.take(sel, bufnr, box_extent)
  local row_top = box_extent and box_extent.top or sel.start_line
  local row_bot = box_extent and box_extent.bottom or sel.end_line

  ---@type cbox.snapshot.t
  local snap = {
    lines = vim.api.nvim_buf_get_lines(bufnr, row_top - 1, row_bot, false),
    row_start = row_top - 1,
    row_end = row_bot,
    start_col = sel.start_col,
    end_col = sel.end_col,
    filetype = vim.bo[bufnr].filetype,
    bufnr = bufnr,
    is_linewise = detect.is_linewise(sel),
  }

  if not box_extent and not snap.is_linewise and sel.start_line > 1 then
    local above =
      vim.api.nvim_buf_get_lines(bufnr, sel.start_line - 2, sel.start_line - 1, false)[1]
    local below =
      vim.api.nvim_buf_get_lines(bufnr, sel.end_line, sel.end_line + 1, false)[1]
    if above and below then
      snap.above = above
      snap.below = below
      snap.above_row = sel.start_line - 2
      snap.below_row = sel.end_line
    end
  end

  return snap
end

return M
