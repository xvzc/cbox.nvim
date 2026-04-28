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

    it("box uses config.style when no preset given", function()
      cbox.setup({ style = "ascii" })
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box()
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "+"))
    end)

    it("toggle uses config.style when no preset given", function()
      cbox.setup({ style = "bold" })
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.toggle()
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "┏"))
    end)

    it("box accepts opts table with style", function()
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box({ style = "bold" })
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "┏"))
    end)

    it("toggle accepts opts table with style", function()
      local bufnr = h.make_buf({ "hello" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.toggle({ style = "double" })
      end)
      assert.truthy(vim.startswith(get_lines(bufnr)[1], "╔"))
    end)

    it("box with opts.width pads to fixed width", function()
      local bufnr = h.make_buf({ "hi" })
      h.with_visual(bufnr, 1, 1, nil, nil, "V", function()
        cbox.box({ style = "thin", width = 10 })
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
        cbox.box({ style = "thin", width = 10, align = "center" })
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

    it("default style is 'thin'", function()
      assert.are.equal("thin", cbox.config.style)
    end)

    it("default presets include thin, bold, double, ascii", function()
      assert.is_not_nil(cbox.config.presets.thin)
      assert.is_not_nil(cbox.config.presets.bold)
      assert.is_not_nil(cbox.config.presets.double)
      assert.is_not_nil(cbox.config.presets.ascii)
    end)

    it("default comment_str includes common filetypes", function()
      assert.is_not_nil(cbox.config.comment_str.lua)
      assert.is_not_nil(cbox.config.comment_str.c)
      assert.is_not_nil(cbox.config.comment_str.javascript)
      assert.are.equal("-- %s", cbox.config.comment_str.lua.line)
      assert.are.equal("--[[ %s --]]", cbox.config.comment_str.lua.block)
    end)
  end)

  describe("setup()", function()
    it("setup with no args keeps defaults", function()
      cbox.setup()
      assert.are.equal("thin", cbox.config.style)
      assert.is_not_nil(cbox.config.presets.thin)
    end)

    it("overrides style", function()
      cbox.setup({ style = "bold" })
      assert.are.equal("bold", cbox.config.style)
    end)

    it("preserves other defaults when overriding style", function()
      cbox.setup({ style = "ascii" })
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
          rust = { line = "/// %s" },
        },
      })
      assert.are.equal("/// %s", cbox.config.comment_str.rust.line)
      assert.is_not_nil(cbox.config.comment_str.lua)
    end)

    it("overrides an existing preset entry", function()
      local custom_thin = { "A", "B", "C", "D", "D", "E", "B", "F" }
      cbox.setup({ presets = { thin = custom_thin } })
      assert.are.same(custom_thin, cbox.config.presets.thin)
    end)

    it("last setup call wins", function()
      cbox.setup({ style = "bold" })
      cbox.setup({ style = "double" })
      assert.are.equal("double", cbox.config.style)
    end)

    it("does not mutate the internal defaults table", function()
      cbox.setup({ style = "ascii" })
      cbox.setup()
      assert.are.equal("thin", cbox.config.style)
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
  end)
end)
