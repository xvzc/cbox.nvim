local M = {}

---@param lines string[]
---@param ft? string
---@return integer bufnr
function M.make_buf(lines, ft)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  if ft then
    -- Switch to the buffer so buffer-local options (commentstring, etc.) are set
    -- by the FileType autocmds that fire when filetype is assigned.
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = ft
  end
  return bufnr
end

function M.clean_bufs()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.bo[b].buftype == "nofile" then
      vim.api.nvim_buf_delete(b, { force = true })
    end
  end
end

--- Perform a visual selection on bufnr and call fn() while visual mode is
--- still active.  cbox functions call exit_visual_if_needed() internally to
--- commit '< '> marks before reading the selection, so fn() must be called
--- *before* Escape is sent.
---
--- start_col / end_col are 1-indexed screen columns (the vim `|` motion).
--- Pass nil for both when columns are irrelevant (linewise "V" mode).
---@param bufnr integer
---@param start_row integer 1-indexed
---@param end_row integer 1-indexed
---@param start_col? integer 1-indexed screen column (for v / \22 modes)
---@param end_col? integer 1-indexed screen column (for v / \22 modes)
---@param mode? string "V"|"v"|"\22"  (default "V")
---@param fn function
function M.with_visual(bufnr, start_row, end_row, start_col, end_col, mode, fn)
  mode = mode or "V"
  vim.api.nvim_set_current_buf(bufnr)
  -- Enter visual mode and select.  Do NOT send Escape here — fn() is called
  -- while still in visual mode so that vim.fn.mode() returns the correct
  -- visual-mode character inside fn().
  local cmd
  if start_col and end_col then
    -- Position at start (row, col), enter visual mode, extend to end (row, col).
    -- The `|` motion moves to the given screen column.
    cmd = string.format(
      "normal! %dG%d|%s%dG%d|",
      start_row,
      start_col,
      mode,
      end_row,
      end_col
    )
  else
    cmd = string.format("normal! %dG%s%dG", start_row, mode, end_row)
  end
  vim.cmd(cmd)
  fn()
end

return M
