return {
  theme = "thin",
  -- Preferred comment kind for V-line wraps.  "line" emits per-row markers
  -- (// box / // box / ...).  "block" emits a single spanning block comment
  -- surrounding the whole box (/* ┌...┐ ... └...┘ */).  Only takes effect
  -- when the filetype has a block template configured; otherwise falls back
  -- to whatever variant is available.
  vline_style = "line",
  presets = {
    bold = { "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" },
    thin = { "┌", "─", "┐", "│", "│", "└", "─", "┘" },
    double = { "╔", "═", "╗", "║", "║", "╚", "═", "╝" },
    ascii = { "+", "-", "+", "|", "|", "+", "-", "+" },
  },
  -- Per-filetype comment templates.  An entry can be either:
  --   - a single string with `%s` (auto-classified as line or block by
  --     whether non-whitespace chars follow `%s`), or
  --   - a `{ line?, block? }` table naming both variants explicitly.
  -- Filetypes not listed here fall back to `vim.bo[bufnr].commentstring`.
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
    css = "/* %s */",
    lua = { line = "-- %s", block = "--[[ %s --]]" },
    html = "<!-- %s -->",
    xml = "<!-- %s -->",
    markdown = "<!-- %s -->",
    python = "# %s",
    ruby = "# %s",
    bash = "# %s",
    sh = "# %s",
    zsh = "# %s",
    vim = '" %s',
  },
}
