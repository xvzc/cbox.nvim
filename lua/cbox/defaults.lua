return {
  theme = "thin",
  presets = {
    bold = { "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" },
    thin = { "┌", "─", "┐", "│", "│", "└", "─", "┘" },
    double = { "╔", "═", "╗", "║", "║", "╚", "═", "╝" },
    ascii = { "+", "-", "+", "|", "|", "+", "-", "+" },
  },
  -- Per-filetype comment templates: a single string with a "%s" placeholder.
  -- Block-form (`/* %s */`) is used only for filetypes with no line-comment
  -- syntax (HTML, CSS, XML, Markdown).  Filetypes not listed here fall back
  -- to `vim.bo[bufnr].commentstring`.
  comment_str = {
    c = "// %s",
    cpp = "// %s",
    go = "// %s",
    java = "// %s",
    javascript = "// %s",
    javascriptreact = "// %s",
    typescript = "// %s",
    typescriptreact = "// %s",
    rust = "// %s",
    swift = "// %s",
    kotlin = "// %s",
    scala = "// %s",
    lua = "-- %s",
    css = "/* %s */",
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
