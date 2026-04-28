---@mod cbox.comment Comment
---@brief [[
---Comment-template resolution and per-line prefix/suffix strip/restore.
---Pure where possible (no Neovim buffer API), but |cbox.comment.resolve_template|
---peeks at `vim.bo[bufnr].commentstring` as a fallback.
---
---Templates are a single string with a `%s` placeholder.  Whether the
---template is "line"-style or "block"-style is decided by whether there are
---non-whitespace characters after the `%s`: `"// %s"` is line; `"/* %s */"`
---and `"<!-- %s -->"` are block.  Block templates apply prefix and suffix
---per-line; line templates apply prefix only.
---@brief ]]

local M = {}

---@class cbox.comment.template
---@field template string
---@field kind string    "line" | "block"
---@field before string  chars before `%s` in the template
---@field after string   chars after `%s` in the template
---@field opener? string bare opener delimiter for block kind (`/*`, `<!--`, `--[[`)
---@field closer? string bare closer delimiter for block kind (`*/`, `-->`, `--]]`)

---@class cbox.comment.ctx
---@field prefix string             per-line leading prefix (indent + marker + actual space, what's stripped) — used for line and per-line block kinds; for spanning, this is row 1's leading prefix only
---@field restore_prefix string     canonical leading prefix (indent + template's `before`) used by `restore`; differs from `prefix` when the original line lacked the canonical space (e.g. `#box` → strip "#", restore "# ")
---@field suffix string             per-line trailing suffix (`after`, "" for line kind); for spanning, this is row N's trailing closer only
---@field kind string               "line" | "block"
---@field is_spanning? boolean      true when ctx describes a single SPANNING block comment (row 1 has `before` inline, row N has `after` inline, middle rows space-indented).  When false/nil, block-kind ctx describes per-line block-style wrapping (each row carries `before` and `after`).
---@field indent_outer? string      spanning only: leading whitespace before `before` on row 1
---@field before? string            spanning only: template's `before %s` portion (e.g. `"/* "`)
---@field after? string             spanning only: template's `%s after` portion (e.g. `" */"`)
---@field inner_indent? string      spanning only: spaces with display width matching `before` — used as row 2..N's lead-in

local function parse_template(template)
  local before, after = template:match("^(.-)%%s(.*)$")
  if not before then
    return nil
  end
  local kind = after:match("%S") and "block" or "line"
  local opener, closer
  if kind == "block" then
    opener = before:match("(%S+)%s*$") or ""
    closer = after:match("^%s*(%S+)") or ""
  end
  return {
    template = template,
    kind = kind,
    before = before,
    after = after,
    opener = opener,
    closer = closer,
  }
end

-- An entry in `comment_str` may be a string OR a `{ line?, block? }` table.
-- Pick the requested variant; if missing, fall back to the other.  Returns
-- the raw template string or nil.
local function pick_entry(entry, style)
  if type(entry) == "table" then
    if style and entry[style] then
      return entry[style]
    end
    return entry.line or entry.block
  elseif type(entry) == "string" then
    return entry
  end
  return nil
end

---Resolves the comment template for a filetype + style.  `style` is one of
---`"line"` or `"block"`; when the requested variant isn't configured, falls
---back to the other configured variant, then to `vim.bo[bufnr].commentstring`.
---@param filetype string
---@param bufnr? integer
---@param style? string  "line" | "block"
---@return cbox.comment.template|nil
function M.resolve_template(filetype, bufnr, style)
  local cbox = require("cbox")
  local entry = cbox.config.comment_str[filetype]
  local candidate = pick_entry(entry, style)

  if not candidate and bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local cs = vim.bo[bufnr].commentstring
    if cs and cs ~= "" then
      candidate = cs
    end
  end

  if candidate then
    return parse_template(candidate)
  end
  return nil
end

-- Try to recognize `lines` as per-line line/block markers (every row carries
-- prefix; for block kind, every row also carries suffix).
---@param lines string[]
---@param resolved cbox.comment.template
---@return cbox.comment.ctx|nil
local function detect_perline(lines, resolved)
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

  -- The canonical restore prefix uses the template's `before` (e.g. "# "),
  -- so wrapping `#foo` (no space after marker) emits "# ┌...┐" — the box is
  -- visually separated from the marker even when the source wasn't.
  local restore_prefix = indent .. resolved.before

  return {
    prefix = prefix,
    restore_prefix = restore_prefix,
    suffix = suffix,
    kind = resolved.kind,
  }
end

-- Try to recognize `lines` as a single SPANNING block comment: row 1 starts
-- with `<indent_outer><before>` and row N ends with `<after>`; rows 2..N
-- start with `<indent_outer><inner_indent>` where inner_indent has display
-- width matching `before`.  Last row's text past inner_indent must extend
-- past the closer (otherwise it's an empty span).
---@param lines string[]
---@param resolved cbox.comment.template
---@return cbox.comment.ctx|nil
local function detect_spanning(lines, resolved)
  if resolved.kind ~= "block" then
    return nil
  end
  local before = resolved.before
  local after = resolved.after
  if #before == 0 or #after == 0 then
    return nil
  end

  local first = lines[1]
  local indent_outer = first:match("^(%s*)" .. vim.pesc(before))
  if not indent_outer then
    return nil
  end
  if not vim.endswith(lines[#lines], after) then
    return nil
  end

  local inner_indent = string.rep(" ", vim.fn.strdisplaywidth(before))
  local lead_rest = indent_outer .. inner_indent
  for i = 2, #lines do
    if not vim.startswith(lines[i], lead_rest) then
      return nil
    end
  end

  -- Last row's content must extend past `<lead_rest>` and `<after>`.  An all-
  -- delimiter last row (e.g. `   */` alone, no content before) is rejected
  -- so a 2-row layout like `<!-- foo -->` / `<!-- bar -->` doesn't slip
  -- through as spanning.
  local last = lines[#lines]
  if #last < #lead_rest + #after then
    return nil
  end

  return {
    kind = "block",
    is_spanning = true,
    prefix = indent_outer .. before,
    restore_prefix = indent_outer .. before,
    suffix = after,
    indent_outer = indent_outer,
    before = before,
    after = after,
    inner_indent = inner_indent,
  }
end

-- Detect the comment shape of `lines`.  Try per-line first (matches the
-- existing line-comment + per-line block-only filetype paths), then fall
-- back to a single spanning block.  Returns ctx or nil.
---@param lines string[]
---@param filetype string
---@param bufnr? integer
---@return cbox.comment.ctx|nil
local function detect_prefix(lines, filetype, bufnr)
  if #lines == 0 then
    return nil
  end
  local resolved = M.resolve_template(filetype, bufnr)
  if not resolved then
    return nil
  end

  local perline = detect_perline(lines, resolved)
  if perline then
    return perline
  end

  -- Per-line failed.  If the filetype has a block variant configured (or
  -- the resolved template is itself block-shaped), try spanning.
  local block_tpl = resolved
  if resolved.kind ~= "block" then
    block_tpl = M.resolve_template(filetype, bufnr, "block")
  end
  if block_tpl and block_tpl.kind == "block" then
    local span = detect_spanning(lines, block_tpl)
    if span then
      return span
    end
  end
  return nil
end

---Strips the common comment marker (prefix and, for block kind, suffix) from
---every line.  Returns the stripped lines and a |cbox.comment.ctx|, or the
---original lines and nil when no common comment is found.
---@param lines string[]
---@param filetype string
---@param bufnr? integer
---@return string[] stripped
---@return cbox.comment.ctx|nil ctx
function M.strip(lines, filetype, bufnr)
  local ctx = detect_prefix(lines, filetype, bufnr)
  if not ctx then
    return lines, nil
  end
  local stripped = {}
  if ctx.is_spanning then
    -- Spanning: row 1 drops `<indent_outer><before>`; rows 2..N drop
    -- `<indent_outer><inner_indent>`; row N also drops `<after>` from the
    -- end.  The result is the inner content, free of any per-row marker.
    local lead_first = ctx.indent_outer .. ctx.before
    local lead_rest = ctx.indent_outer .. ctx.inner_indent
    for i, line in ipairs(lines) do
      local s
      if i == 1 then
        s = line:sub(#lead_first + 1)
      else
        s = line:sub(#lead_rest + 1)
      end
      if i == #lines and #ctx.after > 0 then
        s = s:sub(1, #s - #ctx.after)
      end
      table.insert(stripped, s)
    end
    return stripped, ctx
  end

  for _, line in ipairs(lines) do
    local s = line:sub(#ctx.prefix + 1)
    if ctx.suffix ~= "" then
      s = s:sub(1, #s - #ctx.suffix)
    end
    table.insert(stripped, s)
  end
  return stripped, ctx
end

---@class cbox.comment.restore_opts
---@field canonicalize? boolean  when true (default), use `ctx.restore_prefix` (the canonical "marker + space" from the template) so wraps emit a clean "# ┌...┐" even if the source line was "#box".  Pass `false` to use the actual line prefix verbatim — for trailing/empty wraps that don't consume the line's content, where injecting a canonical space would visually shift the original text.

---Restores the stored prefix (and suffix for block kind) to every line.
---For block kind, pads each line up to the max display width before
---appending the suffix so the closing delimiter aligns across rows.
---@param lines string[]
---@param ctx cbox.comment.ctx
---@param opts? cbox.comment.restore_opts
---@return string[]
---For unwrap paths.  Returns a per-line ctx that emits the filetype's line
---marker on every row (or the block per-row marker for filetypes with no
---line variant).  Spanning ctx is demoted so unwrap always produces line-
---commented content regardless of input form (line / per-line block /
---spanning).  Other ctx kinds are returned unchanged.
---@param ctx cbox.comment.ctx
---@param filetype string
---@param bufnr? integer
---@return cbox.comment.ctx|nil
function M.demote_for_unwrap(ctx, filetype, bufnr)
  if not ctx.is_spanning then
    return ctx
  end
  local indent = ctx.indent_outer or ""
  local line_tpl = M.resolve_template(filetype, bufnr, "line")
    or M.resolve_template(filetype, bufnr, "block")
  if not line_tpl then
    return nil
  end
  return {
    kind = line_tpl.kind,
    prefix = indent .. line_tpl.before,
    restore_prefix = indent .. line_tpl.before,
    suffix = line_tpl.kind == "block" and line_tpl.after or "",
  }
end

function M.restore(lines, ctx, opts)
  opts = opts or {}

  if ctx.is_spanning then
    -- Spanning: row 1 prepends `<indent_outer><before>`, rows 2..N prepend
    -- `<indent_outer><inner_indent>`, and row N appends `<after>` (with
    -- padding so the closer aligns with the widest content row).
    local indent_outer = ctx.indent_outer or ""
    local before = ctx.before or ""
    local after = ctx.after or ""
    local inner_indent = ctx.inner_indent or string.rep(" ", #before)

    local max_w = 0
    for _, line in ipairs(lines) do
      local w = vim.fn.strdisplaywidth(line)
      if w > max_w then
        max_w = w
      end
    end

    local result = {}
    for i, line in ipairs(lines) do
      local lead = (i == 1) and (indent_outer .. before) or (indent_outer .. inner_indent)
      local trail = ""
      if i == #lines and #after > 0 then
        local pad = max_w - vim.fn.strdisplaywidth(line)
        if pad > 0 then
          line = line .. string.rep(" ", pad)
        end
        trail = after
      end
      table.insert(result, lead .. line .. trail)
    end
    return result
  end

  local canonicalize = opts.canonicalize ~= false
  local prefix
  if canonicalize then
    prefix = ctx.restore_prefix or ctx.prefix
  else
    prefix = ctx.prefix
  end
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
