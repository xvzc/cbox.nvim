local M = {}

local defaults = {
  style = "thin",
  presets = {
    bold = { "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" },
    thin = { "┌", "─", "┐", "│", "│", "└", "─", "┘" },
    double = { "╔", "═", "╗", "║", "║", "╚", "═", "╝" },
    ascii = { "+", "-", "+", "|", "|", "+", "-", "+" },
  },
  -- Per-filetype comment templates, with separate "line" and "block" forms.
  -- Each template is a string with a "%s" placeholder for the wrapped content.
  -- Used by the comment module to strip/restore prefixes and to wrap the box
  -- in block comment delimiters when `opts.block` is set (or when the
  -- filetype only has a block form, e.g. HTML).
  comment_str = {
    c = { line = "// %s", block = "/* %s */" },
    cpp = { line = "// %s", block = "/* %s */" },
    go = { line = "// %s", block = "/* %s */" },
    java = { line = "// %s", block = "/* %s */" },
    javascript = { line = "// %s", block = "/* %s */" },
    javascriptreact = { line = "// %s", block = "/* %s */" },
    typescript = { line = "// %s", block = "/* %s */" },
    typescriptreact = { line = "// %s", block = "/* %s */" },
    rust = { line = "// %s", block = "/* %s */" },
    swift = { line = "// %s", block = "/* %s */" },
    kotlin = { line = "// %s", block = "/* %s */" },
    scala = { line = "// %s", block = "/* %s */" },
    lua = { line = "-- %s", block = "--[[ %s --]]" },
    css = { block = "/* %s */" },
    html = { block = "<!-- %s -->" },
    xml = { block = "<!-- %s -->" },
    markdown = { block = "<!-- %s -->" },
    python = { line = "# %s" },
    ruby = { line = "# %s" },
    bash = { line = "# %s" },
    sh = { line = "# %s" },
    zsh = { line = "# %s" },
    vim = { line = '" %s' },
  },
}

-- Always pre-seeded with defaults so submodules work even without setup().
M.config = vim.deepcopy(defaults)

-- Merge user opts on top of defaults.  Safe to call multiple times.
---@param opts? table
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", defaults, opts or {})
end

---@class BoxOpts
---@field style? string                 preset name; defaults to config.style
---@field width? integer                fixed total display width (default: auto)
---@field align? "left"|"right"|"center" alignment with fixed width (default: "left")

---@param opts? BoxOpts|string
---@return BoxOpts
local function resolve_opts(opts)
  if type(opts) == "string" then
    opts = { style = opts }
  end
  opts = opts or {}
  return {
    style = opts.style or M.config.style,
    width = opts.width,
    align = opts.align or "left",
  }
end

-- Top-level user-facing commands.  They read the visual selection automatically
-- so keymaps can call them with no arguments (other than an optional opts table).
-- Sub-requires are lazy (inside function bodies) to avoid circular loading.

---@param opts? BoxOpts
function M.box(opts)
  local sel = require("cbox.detect").get_selection()
  require("cbox.api").wrap(sel, vim.api.nvim_get_current_buf(), resolve_opts(opts))
end

---@param opts? BoxOpts
function M.unbox(opts)
  local sel = require("cbox.detect").get_selection()
  require("cbox.api").unwrap(sel, vim.api.nvim_get_current_buf(), resolve_opts(opts))
end

---@param opts? BoxOpts
function M.toggle(opts)
  local detect = require("cbox.detect")
  local api = require("cbox.api")
  local sel = detect.get_selection()
  local bufnr = vim.api.nvim_get_current_buf()
  local boxes = detect.find_boxes(sel, bufnr)
  local resolved = resolve_opts(opts)

  -- Direction:
  --   * 0 boxes / multi-box / OUTSIDE classify       → wrap.
  --   * 1 box, linewise, sel strictly inside content
  --     of a partial box                             → wrap (erase + redraw).
  --   * 1 box, linewise, INSIDE/OVERLAPPING (clean)  → unwrap.
  --   * 1 box, blockwise, boundaries align (one
  --     contains the other)                          → unwrap.
  --   * 1 box, blockwise, partial overlap            → wrap (merge).
  if #boxes ~= 1 then
    return api.wrap(sel, bufnr, resolved)
  end

  local position = detect.classify(sel, boxes).position
  if position == detect.Position.OUTSIDE then
    return api.wrap(sel, bufnr, resolved)
  end

  if detect.is_linewise(sel) then
    local b = boxes[1]
    local strictly_inside = sel.start_line > b.top and sel.end_line < b.bottom
    if strictly_inside and not detect.box_is_clean_linewise(b, bufnr) then
      api.wrap(sel, bufnr, resolved)
    else
      api.unwrap(sel, bufnr, resolved)
    end
  elseif detect.boundaries_align(sel, boxes[1], bufnr) then
    api.unwrap(sel, bufnr, resolved)
  else
    api.wrap(sel, bufnr, resolved)
  end
end

return M
