-- Comment-template resolution and per-line prefix/suffix strip/restore.
-- Pure where possible (no Neovim buffer API), but resolve_template peeks at
-- vim.bo[bufnr].commentstring as a fallback.
--
-- Both line- and block-style filetypes are handled the same way: per-line.
-- For "// %s" each row gets `// ` prepended; for "<!-- %s -->" each row gets
-- `<!-- ` prepended and ` -->` appended.

local M = {}

---@class CommentTemplate
---@field template string
---@field kind "line"|"block"
---@field before string  -- chars before %s in the template
---@field after string   -- chars after %s in the template

---@class CommentCtx
---@field prefix string  -- per-line leading prefix (indent + before)
---@field suffix string  -- per-line trailing suffix (after, "" for line kind)
---@field kind "line"|"block"

local function parse_template(template)
  local before, after = template:match("^(.-)%%s(.*)$")
  if not before then
    return nil
  end
  local kind = after:match("%S") and "block" or "line"
  return { template = template, kind = kind, before = before, after = after }
end

-- Resolve the comment template for a filetype.  Looks up
-- `cbox.config.comment_str[filetype]` first, falling back to
-- `vim.bo[bufnr].commentstring`.  Returns nil when no template is available.
---@param filetype string
---@param bufnr? integer
---@return CommentTemplate|nil
function M.resolve_template(filetype, bufnr)
  local cbox = require("cbox")
  local entry = cbox.config.comment_str[filetype]
  if entry then
    -- Prefer line; fall back to block (block-only filetypes like HTML).
    if entry.line then
      return parse_template(entry.line)
    end
    if entry.block then
      return parse_template(entry.block)
    end
  end

  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local cs = vim.bo[bufnr].commentstring
    if cs and cs ~= "" then
      return parse_template(cs)
    end
  end

  return nil
end

-- Detect the common comment-prefix (and suffix for block kind) shared by all
-- lines.  Returns ctx or nil.
---@param lines string[]
---@param filetype string
---@return CommentCtx|nil
local function detect_prefix(lines, filetype)
  if #lines == 0 then
    return nil
  end
  local resolved = M.resolve_template(filetype, nil)
  if not resolved then
    return nil
  end

  -- Marker = non-whitespace head of `before`, e.g. "//", "--", "<!--".
  local marker = resolved.before:match("^%s*(%S+)") or ""
  if marker == "" then
    return nil
  end

  local first = lines[1]
  local indent = first:match("^(%s*)" .. vim.pesc(marker))
  if not indent then
    return nil
  end

  -- Allow optional trailing space after the marker even if the template has
  -- one (so "--foo" matches a "-- %s" template with the space treated as
  -- absent on this input).
  local after_marker_pos = #indent + #marker + 1
  local space = (first:sub(after_marker_pos, after_marker_pos) == " ") and " " or ""
  local prefix = indent .. marker .. space

  for i = 1, #lines do
    if not vim.startswith(lines[i], prefix) then
      return nil
    end
  end

  local suffix = ""
  if resolved.kind == "block" then
    suffix = resolved.after
    for i = 1, #lines do
      if not vim.endswith(lines[i], suffix) then
        return nil
      end
    end
  end

  return { prefix = prefix, suffix = suffix, kind = resolved.kind }
end

-- Strip the common comment marker (prefix and, for block kind, suffix) from
-- every line.  Returns the stripped lines and a CommentCtx, or the original
-- lines and nil when no common comment is found.
---@param lines string[]
---@param filetype string
---@return string[], CommentCtx|nil
function M.strip(lines, filetype)
  local ctx = detect_prefix(lines, filetype)
  if not ctx then
    return lines, nil
  end
  local stripped = {}
  for _, line in ipairs(lines) do
    local s = line:sub(#ctx.prefix + 1)
    if ctx.suffix ~= "" then
      s = s:sub(1, #s - #ctx.suffix)
    end
    table.insert(stripped, s)
  end
  return stripped, ctx
end

-- Restore the stored prefix (and suffix for block kind) to every line.
-- For block kind, pad each line up to the max display width before appending
-- the suffix so the closing delimiter aligns across rows.
---@param lines string[]
---@param ctx CommentCtx
---@return string[]
function M.restore(lines, ctx)
  local prefix = ctx.prefix
  local suffix = ctx.suffix or ""

  local max_w = 0
  if suffix ~= "" then
    for _, line in ipairs(lines) do
      local w = vim.fn.strdisplaywidth(line)
      if w > max_w then
        max_w = w
      end
    end
  end

  local result = {}
  for _, line in ipairs(lines) do
    local body = line
    if suffix ~= "" then
      local w = vim.fn.strdisplaywidth(line)
      if w < max_w then
        body = body .. string.rep(" ", max_w - w)
      end
    end
    table.insert(result, prefix .. body .. suffix)
  end
  return result
end

return M
