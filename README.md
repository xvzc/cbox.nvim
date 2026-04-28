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

**lazy.nvim**

```lua
{
  "xvzc/cbox.nvim",
  config = function()
    require("cbox").setup()
  end,
}
```

## Configuration

`setup()` is optional — defaults are pre-loaded. Override only what you need.

```lua
require("cbox").setup({
  style = "thin",  -- default preset name from `presets`
  presets = {
    bold   = { "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" },
    thin   = { "┌", "─", "┐", "│", "│", "└", "─", "┘" },
    double = { "╔", "═", "╗", "║", "║", "╚", "═", "╝" },
    ascii  = { "+", "-", "+", "|", "|", "+", "-", "+" },
    -- add your own:
    rounded = { "╭", "─", "╮", "│", "│", "╰", "─", "╯" },
  },
  comment_str = {
    -- per-filetype comment templates; falls back to `vim.bo.commentstring`
    lua = { line = "-- %s", block = "--[[ %s --]]" },
    html = { block = "<!-- %s -->" },
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
cbox.box({ style = "double" })
cbox.box({ width = 60, align = "center" })
```

Comment prefixes are detected and preserved automatically. Selecting `// foo bar` in a `.c` buffer and toggling produces:

```c
// ┌─────────┐
// │ foo bar │
// └─────────┘
```

`toggle()` resolves wrap vs. strip from context: if the selection sits inside a clean box it strips; if it overlaps a partial box it redraws; if there's no box it wraps. See `:help cbox` for the full dispatch table.

## Help

Once installed, `:help cbox` shows the generated reference. The source is `doc/cbox.nvim.txt`.
