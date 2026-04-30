# cbox.nvim

> **Experimental.** APIs may change without notice.

Comment-box drawing for Neovim. Wraps the visual selection (or the word under the cursor) in a configurable border, preserving per-filetype comment prefixes.

```text
┌─────────────┐
│ hello world │
└─────────────┘
```

## Requirements

- Neovim >= 0.12.1

## Installation

**lazy.nvim** — minimal:

```lua
{ "xvzc/cbox.nvim" }
```

Defaults are pre-loaded by `plugin/cbox.lua`, so no `setup()` call is required for the out-of-the-box behavior.

**With a keymap** — `gb` toggles a spanning block comment around the V-line selection (or wraps the cursor word in normal mode):

```lua
{
  "xvzc/cbox.nvim",
  event = "VeryLazy",
  keys = {
    {
      "gb",
      mode = { "n", "x" },
      function()
        require("cbox").toggle({ theme = "thin", visual_line = { style = "block" } })
      end,
      desc = "cbox: toggle",
    },
  },
}
```

`visual_line.style = "block"` only takes effect for V-line selections; normal-mode `gb` wraps the cursor word with the regular per-row line comment.

## Configuration

`setup()` is optional — defaults are pre-loaded. Override only what you need.

```lua
require("cbox").setup({
  theme = "thin",  -- default preset name from `presets`
  visual_line = {
    -- V-line-only wrap options (ignored for normal-mode and blockwise wraps).
    style = "line",  -- "line": per-row markers // box ...
                     -- "block": single spanning /* ┌...┐ ... └...┘ */
                     --          (only when the filetype has a block template)
    width = nil,     -- fixed total display width (default: auto-fit)
    align = "left",  -- "left" | "right" | "center"
  },
  presets = {
    bold   = { "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" },
    thin   = { "┌", "─", "┐", "│", "│", "└", "─", "┘" },
    double = { "╔", "═", "╗", "║", "║", "╚", "═", "╝" },
    ascii  = { "+", "-", "+", "|", "|", "+", "-", "+" },
    -- add your own:
    rounded = { "╭", "─", "╮", "│", "│", "╰", "─", "╯" },
  },
  comment_str = {
    -- Per-filetype comment template.  An entry is either:
    --   - a single string with `%s`, auto-classified as line/block by
    --     whether non-whitespace chars follow the placeholder, OR
    --   - a `{ line?, block? }` table that names both variants.
    -- Filetypes not listed fall back to `vim.bo.commentstring`.
    c    = { line = "// %s", block = "/* %s */" },
    lua  = { line = "-- %s", block = "--[[ %s --]]" },
    html = "<!-- %s -->",     -- block-only is fine; auto-classified
    nix  = "# %s",
  },
})
```

A preset is an 8-element list: top-left, top-fill, top-right, left side, right side, bottom-left, bottom-fill, bottom-right.

## Usage

Three top-level commands operate on the visual selection (or the word under the cursor in normal mode):

```lua
local cbox = require("cbox")

vim.keymap.set({ "n", "v" }, "<leader>cb", cbox.box,    { desc = "cbox: draw"   })
vim.keymap.set({ "n", "v" }, "<leader>cu", cbox.unbox,  { desc = "cbox: strip"  })
vim.keymap.set({ "n", "v" }, "<leader>cc", cbox.toggle, { desc = "cbox: toggle" })
```

Each accepts an optional `opts` table:

```lua
cbox.box({ theme = "double" })
cbox.box({ visual_line = { width = 60, align = "center" } })
cbox.box({ visual_line = { style = "block" } })  -- spanning /* ... */ around the whole box
```

Comment prefixes are detected and preserved automatically. Selecting `// foo bar` in a `.c` buffer and toggling produces:

```c
// ┌─────────┐
// │ foo bar │
// └─────────┘
```

V-line selection with `visual_line.style = "block"` emits a single spanning block comment around the whole box instead of per-row markers:

```c
/* ┌─────────┐
   │ foo bar │
   │ baz qux │
   └─────────┘ */
```

`toggle()` resolves wrap vs. strip from context: if the selection sits inside a clean box it strips; if it overlaps a partial box it redraws; if there's no box it wraps. See `:help cbox.nvim` for the full dispatch table.

## Help

Once installed, `:help cbox.nvim` (or `:help cbox`) shows the generated reference. The source is `doc/cbox.nvim.txt`.
