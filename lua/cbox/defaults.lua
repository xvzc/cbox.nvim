return {
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
