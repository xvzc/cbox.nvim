local h = require("helpers")
local cbox = require("cbox")

local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)

local function get_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

-- Simulate a linewise visual selection and exit visual mode, mirroring what
-- Neovim does before invoking a 'v'-mode keymap callback: the marks '< and '>
-- are committed and visualmode() returns "V", but we are back in normal mode.
local function select_lines(bufnr, start_line, end_line)
  vim.api.nvim_set_current_buf(bufnr)
  vim.cmd(string.format("normal! %dGV%dG", start_line, end_line))
  vim.api.nvim_feedkeys(esc, "x", false)
end

-- Place cursor at (line, col) in normal mode (col is 0-indexed byte offset).
local function place_cursor(bufnr, line, col)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_win_set_cursor(0, { line, col })
end

describe("cbox (init)", function()
  after_each(function()
    cbox.setup() -- reset to defaults
    h.clean_bufs()
  end)

  describe("top-level API", function()
    it("box, unbox, toggle are functions on the main module", function()
      assert.is_function(cbox.box)
      assert.is_function(cbox.unbox)
      assert.is_function(cbox.toggle)
    end)

    it("box reads the visual selection and draws a box", function()
      local bufnr = h.make_buf({ "hello" })
      select_lines(bufnr, 1, 1)
      cbox.box("thin")
      assert.are.same({
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      }, get_lines(bufnr))
    end)

    it("unbox reads the visual selection and erases the box", function()
      local bufnr = h.make_buf({
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      })
      h.with_visual(bufnr, 2, 2, nil, nil, "V", function()
        cbox.unbox()
      end)
      assert.are.same({ "hello" }, get_lines(bufnr))
    end)

    it("toggle wraps on first call, unwraps on second", function()
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.toggle("thin")
      end)
      -- box drawn: content is now on line 2
      h.with_visual(bufnr, 2, 2, nil, nil, "V", function()
        cbox.toggle("thin")
      end)
      assert.are.same({ "hello" }, get_lines(bufnr))
    end)

    it("box uses config.theme when no preset given", function()
      cbox.setup({ theme = "ascii" })
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box()
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "+"))
    end)

    it("toggle uses config.theme when no preset given", function()
      cbox.setup({ theme = "bold" })
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.toggle()
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "┏"))
    end)

    it("box accepts opts table with theme", function()
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box({ theme = "bold" })
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "┏"))
    end)

    it("toggle accepts opts table with theme", function()
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.toggle({ theme = "double" })
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "╔"))
    end)

    it("box with opts.width pads to fixed width", function()
      local bufnr = h.make_buf({ "hi" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box({ theme = "thin", width = 10 })
      end)
      assert.are.same({
        "┌────────┐",
        "│ hi     │",
        "└────────┘",
      }, get_lines(bufnr))
    end)

    it("box with opts.width + align=center centers content", function()
      local bufnr = h.make_buf({ "hi" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box({ theme = "thin", width = 10, align = "center" })
      end)
      assert.are.same({
        "┌────────┐",
        "│   hi   │",
        "└────────┘",
      }, get_lines(bufnr))
    end)
  end)

  describe("default config (no setup call)", function()
    it("config is available without calling setup", function()
      assert.is_not_nil(cbox.config)
    end)

    it("default theme is 'thin'", function()
      assert.are.equal("thin", cbox.config.theme)
    end)

    it("default presets include thin, bold, double, ascii", function()
      assert.is_not_nil(cbox.config.presets.thin)
      assert.is_not_nil(cbox.config.presets.bold)
      assert.is_not_nil(cbox.config.presets.double)
      assert.is_not_nil(cbox.config.presets.ascii)
    end)

    it("default comment_str includes common filetypes", function()
      assert.are.equal("-- %s", cbox.config.comment_str.lua)
      assert.are.equal("// %s", cbox.config.comment_str.c)
      assert.are.equal("// %s", cbox.config.comment_str.javascript)
      assert.are.equal("<!-- %s -->", cbox.config.comment_str.html)
    end)
  end)

  describe("setup()", function()
    it("setup with no args keeps defaults", function()
      cbox.setup()
      assert.are.equal("thin", cbox.config.theme)
      assert.is_not_nil(cbox.config.presets.thin)
    end)

    it("overrides theme", function()
      cbox.setup({ theme = "bold" })
      assert.are.equal("bold", cbox.config.theme)
    end)

    it("preserves other defaults when overriding theme", function()
      cbox.setup({ theme = "ascii" })
      assert.is_not_nil(cbox.config.presets.thin)
      assert.is_not_nil(cbox.config.comment_str.lua)
    end)

    it("deep-merges a custom preset without removing built-in presets", function()
      cbox.setup({
        presets = {
          custom = { "[", "-", "]", "|", "|", "[", "-", "]" },
        },
      })
      assert.is_not_nil(cbox.config.presets.custom)
      assert.is_not_nil(cbox.config.presets.thin)
      assert.is_not_nil(cbox.config.presets.bold)
    end)

    it("deep-merges a custom comment_str without removing built-in ones", function()
      cbox.setup({
        comment_str = {
          rust = "/// %s",
        },
      })
      assert.are.equal("/// %s", cbox.config.comment_str.rust)
      assert.is_not_nil(cbox.config.comment_str.lua)
    end)

    it("overrides an existing preset entry", function()
      local custom_thin = { "A", "B", "C", "D", "D", "E", "B", "F" }
      cbox.setup({ presets = { thin = custom_thin } })
      assert.are.same(custom_thin, cbox.config.presets.thin)
    end)

    it("last setup call wins", function()
      cbox.setup({ theme = "bold" })
      cbox.setup({ theme = "double" })
      assert.are.equal("double", cbox.config.theme)
    end)

    it("does not mutate the internal defaults table", function()
      cbox.setup({ theme = "ascii" })
      cbox.setup()
      assert.are.equal("thin", cbox.config.theme)
    end)

    it("sets vim.g.cbox_loaded so the auto-setup at load time skips", function()
      cbox.setup()
      assert.are.equal(1, vim.g.cbox_loaded)
    end)

    it("auto-setup ran on first require: config is populated", function()
      -- Whatever the test before us did, the auto-setup must have left the
      -- module with a valid config (otherwise nothing else in this file would
      -- have worked).  Re-assert the invariant explicitly.
      assert.is_not_nil(cbox.config)
      assert.is_not_nil(cbox.config.presets)
      assert.are.equal(1, vim.g.cbox_loaded)
    end)
  end)

  describe("normal mode selection", function()
    it("wrap on whitespace wraps a single column", function()
      -- cursor on the space between 'hello' and 'world' (0-indexed col 5 = 1-indexed col 6)
      -- single col → content_byte_width=1, inner_width=3 dashes
      -- ascii: tl/bl="+", l/r="|"
      -- border rows use spaces for the prefix ("hello" → 5 spaces), no trailing suffix
      local bufnr = h.make_buf({ "hello world" })
      place_cursor(bufnr, 1, 5) -- col 5 = the space char (0-indexed)
      cbox.box("ascii")
      local actual = get_lines(bufnr)
      assert.are.same({
        "     +---+",
        "hello|   |world",
        "     +---+",
      }, actual)
    end)

    it("wrap on non-whitespace selects the whole word", function()
      -- cursor on 'w' of 'world' (0-indexed col 6 = 1-indexed col 7)
      -- "world" is 5 bytes → inner_width=7 dashes; ascii l/r="|"
      -- border rows use spaces for prefix ("hello " → 6 spaces)
      local bufnr = h.make_buf({ "hello world" })
      place_cursor(bufnr, 1, 6) -- col 6 = 'w' (0-indexed)
      cbox.box("ascii")
      local actual = get_lines(bufnr)
      assert.are.same({
        "      +-------+",
        "hello | world |",
        "      +-------+",
      }, actual)
    end)

    it("wrap on non-whitespace at start of line wraps from col 1", function()
      -- "hello" is 5 bytes → inner_width=7; ascii l/r="|"
      local bufnr = h.make_buf({ "hello" })
      place_cursor(bufnr, 1, 0) -- col 0 = 'h'
      cbox.box("ascii")
      local actual = get_lines(bufnr)
      assert.are.same({
        "+-------+",
        "| hello |",
        "+-------+",
      }, actual)
    end)

    it(
      "merge_into_borders works when adjacent rows already contain multiple boxes",
      function()
        -- Regression: merge_into_borders previously checked top_preset on the
        -- whole stripped line, which fails when the line already contains
        -- multiple boxes (the "inner" between leftmost ┌ and rightmost ┐
        -- contains other corners, so all_fill fails).  Switched to
        -- find_borders (any pattern anywhere on the line).
        local bufnr = h.make_buf({
          "--         ┌───┐┌─────┐",
          "-- box box │ h ││ ell │o",
          "--         └───┘└─────┘",
        }, "lua")
        place_cursor(bufnr, 2, 31) -- cursor on "o"
        cbox.toggle()
        assert.are.same({
          "--         ┌───┐┌─────┐┌───┐",
          "-- box box │ h ││ ell ││ o │",
          "--         └───┘└─────┘└───┘",
        }, get_lines(bufnr))
      end
    )

    it(
      "merge_into_borders extends from the left when multi-box is on the right",
      function()
        local bufnr = h.make_buf({
          "--          ┌─────┐┌───┐",
          "-- box box h│ ell ││ o │",
          "--          └─────┘└───┘",
        }, "lua")
        place_cursor(bufnr, 2, 11) -- cursor on "h"
        cbox.toggle()
        assert.are.same({
          "--         ┌───┐┌─────┐┌───┐",
          "-- box box │ h ││ ell ││ o │",
          "--         └───┘└─────┘└───┘",
        }, get_lines(bufnr))
      end
    )

    it(
      "word boundary stops at adjacent box-drawing char (no word-extends-into-box)",
      function()
        -- Regression: cursor on "h" sandwiched between a space and the existing
        -- box's "│" must select just "h", NOT "h│".  Otherwise the sel cols
        -- overlap the box's disp range, find_boxes returns it, and toggle takes
        -- the merge_overlapping path (erase + re-wrap) which destroys the
        -- existing box.  With box-aware word boundary, sel = "h" only → plain
        -- wrap path → merge_into_borders extends the existing box's borders.
        local bufnr = h.make_buf({
          "--          ┌─────┐",
          "-- box box h│ ell │o",
          "--          └─────┘",
        }, "lua")
        place_cursor(bufnr, 2, 11) -- byte 12 = "h"
        cbox.toggle()
        assert.are.same({
          "--         ┌───┐┌─────┐",
          "-- box box │ h ││ ell │o",
          "--         └───┘└─────┘",
        }, get_lines(bufnr))
      end
    )

    it("wrap on empty line wraps a single column at col 1", function()
      -- empty → single col padded to " ", inner_width=3; ascii l/r="|"
      local bufnr = h.make_buf({ "" })
      place_cursor(bufnr, 1, 0)
      cbox.box("ascii")
      local actual = get_lines(bufnr)
      assert.are.same({ "+---+", "|   |", "+---+" }, actual)
    end)

    it("toggle from normal mode wraps a word", function()
      local bufnr = h.make_buf({ "hello world" })
      place_cursor(bufnr, 1, 6) -- cursor on 'w' of 'world'
      cbox.toggle("ascii")
      local after_wrap = get_lines(bufnr)
      assert.are.equal(3, #after_wrap)
      assert.are.equal("      +-------+", after_wrap[1])
    end)
  end)

  describe("comment-aware linewise", function()
    it("wrap strips comment prefix, draws box, restores prefix", function()
      local bufnr = h.make_buf({ "-- hello", "-- world" }, "lua")
      h.with_visual(bufnr, 1, 2, nil, nil, "V", function()
        cbox.box("thin")
      end)
      local expected = {
        "-- ┌───────┐",
        "-- │ hello │",
        "-- │ world │",
        "-- └───────┘",
      }
      assert.are.same(expected, get_lines(bufnr))
    end)

    it("unwrap strips comment prefix, erases box, restores prefix", function()
      local bufnr = h.make_buf({
        "-- ┌───────┐",
        "-- │ hello │",
        "-- │ world │",
        "-- └───────┘",
      }, "lua")
      h.with_visual(bufnr, 2, 3, nil, nil, "V", function()
        cbox.unbox()
      end)
      assert.are.same({ "-- hello", "-- world" }, get_lines(bufnr))
    end)

    it("toggle round-trips through wrap and unwrap", function()
      local bufnr = h.make_buf({ "-- hello" }, "lua")
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.toggle("thin")
      end)
      -- box drawn, content on line 2
      h.with_visual(bufnr, 2, 2, nil, nil, "V", function()
        cbox.toggle("thin")
      end)
      assert.are.same({ "-- hello" }, get_lines(bufnr))
    end)

    it("wrap without filetype does not crash (no comment stripping)", function()
      local bufnr = h.make_buf({ "-- hello" }) -- no filetype
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box("thin")
      end)
      -- no comment stripping: "-- hello" treated as plain content
      local lines = get_lines(bufnr)
      assert.are.equal(3, #lines)
      assert.truthy(vim.startswith(lines[1], "┌"))
    end)

    it("wrap with indented lua comments preserves indent", function()
      local bufnr = h.make_buf({ "  -- hello" }, "lua")
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box("thin")
      end)
      local lines = get_lines(bufnr)
      assert.truthy(vim.startswith(lines[1], "  -- ┌"))
    end)

    it("falls back to vim.bo.commentstring for filetypes not in comment_str", function()
      -- nix is not in defaults.comment_str; its commentstring is "# %s",
      -- which the resolve_template fallback should pick up.
      local bufnr = h.make_buf({ "# box" }, "nix")
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.toggle("thin")
      end)
      assert.are.same({
        "# ┌─────┐",
        "# │ box │",
        "# └─────┘",
      }, get_lines(bufnr))
    end)

    it("commentstring fallback works for normal-mode (cursor on word)", function()
      local bufnr = h.make_buf({ "# hello" }, "nix")
      place_cursor(bufnr, 1, 3) -- on 'h' of "hello"
      cbox.toggle("thin")
      assert.are.same({
        "# ┌───────┐",
        "# │ hello │",
        "# └───────┘",
      }, get_lines(bufnr))
    end)

    it("explicit comment_str entry overrides commentstring", function()
      cbox.setup({ comment_str = { nix = "## %s" } })
      local bufnr = h.make_buf({ "## hello" }, "nix")
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box("thin")
      end)
      assert.are.same({
        "## ┌───────┐",
        "## │ hello │",
        "## └───────┘",
      }, get_lines(bufnr))
    end)

    it(
      "blockwise selection that overlaps the comment prefix wraps just the post-prefix content",
      function()
        -- <C-v> from col 2 (the space inside `# `) through col 5 (end of box)
        -- on three commented rows.  The selection's start is inside the
        -- comment prefix; clamping treats it as "the part of the selection
        -- that's inside the stripped content" — equivalent to a V-style box
        -- around the post-prefix content.
        local bufnr = h.make_buf({ "# box", "# box", "# box" }, "nix")
        h.with_visual(bufnr, 1, 3, 2, 5, "\22", function()
          cbox.box("thin")
        end)
        assert.are.same({
          "# ┌─────┐",
          "# │ box │",
          "# │ box │",
          "# │ box │",
          "# └─────┘",
        }, get_lines(bufnr))
      end
    )

    it(
      "wrap canonicalizes the comment prefix: `#box` (no space) becomes `# ┌...┐`",
      function()
        local bufnr = h.make_buf({ "#box" }, "nix")
        place_cursor(bufnr, 1, 1) -- cursor on 'b'
        cbox.box("thin")
        assert.are.same({
          "# ┌─────┐",
          "# │ box │",
          "# └─────┘",
        }, get_lines(bufnr))
      end
    )

    it(
      "normal-mode toggle on `#box` content row inside a tiny adjacent box: merge with canonical prefix",
      function()
        -- The line above and below are border rows of an existing tiny box.
        -- Toggling on `box` of `#box│   │` wraps the word and merges the new
        -- box's borders into the existing ones, canonicalizing `#` → `# `.
        local bufnr = h.make_buf({
          "#   ┌───┐",
          "#box│   │",
          "#   └───┘",
        }, "nix")
        place_cursor(bufnr, 2, 1) -- on 'b' of "#box"
        cbox.toggle("thin")
        assert.are.same({
          "# ┌─────┐┌───┐",
          "# │ box ││   │",
          "# └─────┘└───┘",
        }, get_lines(bufnr))
      end
    )

    it(
      "<C-v> blockwise wrap on a non-leading column preserves the actual prefix verbatim",
      function()
        -- Trailing-style wrap (content_start > 1) should leave the original
        -- "#" prefix alone — silently inserting the canonical space would
        -- visually shift the surviving "#box" to "# box".
        local bufnr = h.make_buf({ "#boxA", "#boxA", "#boxA" }, "nix")
        h.with_visual(bufnr, 1, 3, 5, 5, "\22", function()
          cbox.box("thin")
        end)
        assert.are.same({
          "#   ┌───┐",
          "#box│ A │",
          "#box│ A │",
          "#box│ A │",
          "#   └───┘",
        }, get_lines(bufnr))
      end
    )

    it(
      "<C-v> word-wrap inside an existing 3-row tiny box: merge with canonical prefix",
      function()
        local bufnr = h.make_buf({
          "#   ┌───┐",
          "#box│   │",
          "#box│   │",
          "#box│   │",
          "#   └───┘",
        }, "nix")
        -- Visual block on the `box` chars across rows 2-4, cols 2-4.
        h.with_visual(bufnr, 2, 4, 2, 4, "\22", function()
          cbox.box("thin")
        end)
        assert.are.same({
          "# ┌─────┐┌───┐",
          "# │ box ││   │",
          "# │ box ││   │",
          "# │ box ││   │",
          "# └─────┘└───┘",
        }, get_lines(bufnr))
      end
    )
  end)

  describe("V-line indent and alignment round-trip", function()
    it(
      "V-line wrap places the box at line start; leading whitespace is content",
      function()
        local bufnr = h.make_buf({ "#   foo", "#   bar" }, "nix")
        h.with_visual(bufnr, 1, 2, nil, nil, "V", function()
          cbox.box("thin")
        end)
        assert.are.same({
          "# ┌───────┐",
          "# │   foo │",
          "# │   bar │",
          "# └───────┘",
        }, get_lines(bufnr))
      end
    )

    it("differing leading whitespace is preserved per-row as content", function()
      local bufnr = h.make_buf({ "#   foo", "#     bar" }, "nix")
      h.with_visual(bufnr, 1, 2, nil, nil, "V", function()
        cbox.box("thin")
      end)
      assert.are.same({
        "# ┌─────────┐",
        "# │   foo   │",
        "# │     bar │",
        "# └─────────┘",
      }, get_lines(bufnr))
    end)

    it(
      "unwrap of a pre-existing indented V-line box preserves the indent before the side char",
      function()
        local bufnr = h.make_buf({
          "#   ┌─────┐",
          "#   │ foo │",
          "#   │ bar │",
          "#   └─────┘",
        }, "nix")
        h.with_visual(bufnr, 2, 3, nil, nil, "V", function()
          cbox.unbox()
        end)
        assert.are.same({ "#   foo", "#   bar" }, get_lines(bufnr))
      end
    )

    it(
      "toggle V-line strips comment-internal leading whitespace (round-trip lossy on first cycle, idempotent after)",
      function()
        local bufnr = h.make_buf({ "#   foo", "#   bar" }, "nix")
        h.with_visual(bufnr, 1, 2, nil, nil, "V", function()
          cbox.toggle("thin")
        end)
        h.with_visual(bufnr, 2, 3, nil, nil, "V", function()
          cbox.toggle("thin")
        end)
        assert.are.same({ "# foo", "# bar" }, get_lines(bufnr))

        h.with_visual(bufnr, 1, 2, nil, nil, "V", function()
          cbox.toggle("thin")
        end)
        h.with_visual(bufnr, 2, 3, nil, nil, "V", function()
          cbox.toggle("thin")
        end)
        assert.are.same({ "# foo", "# bar" }, get_lines(bufnr))
      end
    )

    it(
      "V-line wrap with align=center: leading whitespace shifts content right uniformly",
      function()
        local bufnr = h.make_buf({ "box", "  box", "    box" })
        h.with_visual(bufnr, 1, 3, nil, nil, "V", function()
          cbox.box({ theme = "thin", width = 15, align = "center" })
        end)
        -- All rows share the core "box" (w=3), so center_min_lpad = (11-3)/2
        -- = 4 floor.  Each row's leading whitespace is then preserved in
        -- place, shifting `b` rightward by exactly leading-ws-width per row.
        assert.are.same({
          "┌─────────────┐",
          "│     box     │",
          "│       box   │",
          "│         box │",
          "└─────────────┘",
        }, get_lines(bufnr))
      end
    )

    it(
      "toggle V-line align=center round-trips: relative leading whitespace recovered",
      function()
        local bufnr = h.make_buf({ "box", "  box", "    box" })
        h.with_visual(bufnr, 1, 3, nil, nil, "V", function()
          cbox.toggle({ theme = "thin", width = 15, align = "center" })
        end)
        h.with_visual(bufnr, 2, 4, nil, nil, "V", function()
          cbox.toggle({ theme = "thin", width = 15, align = "center" })
        end)
        assert.are.same({ "box", "  box", "    box" }, get_lines(bufnr))
      end
    )

    it(
      "unwrap of a multi-row centered box recovers relative leading whitespace via min-baseline",
      function()
        -- Pre-existing centered box where content starts at different cols
        -- per row.  The leftmost `b` (row 1) becomes the baseline; later rows
        -- recover (their content_start - leftmost) leading spaces.
        local bufnr = h.make_buf({
          "┌─────────────┐",
          "│     box     │",
          "│       box   │",
          "│         box │",
          "└─────────────┘",
        })
        h.with_visual(bufnr, 1, 5, nil, nil, "V", function()
          cbox.unbox()
        end)
        assert.are.same({ "box", "  box", "    box" }, get_lines(bufnr))
      end
    )

    it("unwrap of a wide centered box recovers tight content (loses padding)", function()
      -- This is the user's reported case: width=80 align=center wraps "# box"
      -- into a wide centered bold box.  toggle() should give back "# box"
      -- without the centering padding.
      local bufnr = h.make_buf({
        "# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓",
        "# ┃                                   box                                   ┃",
        "# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛",
      }, "nix")
      h.with_visual(bufnr, 1, 3, nil, nil, "V", function()
        cbox.toggle()
      end)
      assert.are.same({ "# box" }, get_lines(bufnr))
    end)
  end)
end)
