-- box.lua is a pure module: no Neovim buffer API, only string[] → string[].
-- Tests use plain tables — no bufnr, no make_buf, no after_each cleanup needed.

local box = require("cbox.render")
local cbox = require("cbox")

local thin = { "┌", "─", "┐", "│", "│", "└", "─", "┘" }
local bold = { "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" }
local double = { "╔", "═", "╗", "║", "║", "╚", "═", "╝" }
local ascii = { "+", "-", "+", "|", "|", "+", "-", "+" }

describe("box (pure primitives)", function()
  describe("wrap_lines", function()
    it("wraps a single line with thin preset", function()
      local input = { "hello" }
      local expected = {
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      }
      assert.are.same(expected, box.wrap_lines(input, 1, 5, thin))
    end)

    it("wraps multiple lines", function()
      local input = { "foo", "bar" }
      local expected = {
        "┌─────┐",
        "│ foo │",
        "│ bar │",
        "└─────┘",
      }
      assert.are.same(expected, box.wrap_lines(input, 1, 3, thin))
    end)

    it("pads shorter lines so all rows align", function()
      local input = { "hi", "hello" }
      local expected = {
        "┌───────┐",
        "│ hi    │",
        "│ hello │",
        "└───────┘",
      }
      assert.are.same(expected, box.wrap_lines(input, 1, 5, thin))
    end)

    it("preserves prefix bytes before content_start_disp", function()
      local input = { "  hello" }
      local expected = {
        "  ┌───────┐",
        "  │ hello │",
        "  └───────┘",
      }
      assert.are.same(expected, box.wrap_lines(input, 3, 7, thin))
    end)

    it("preserves suffix bytes after content_end_disp", function()
      local input = { "hello world" }
      local result = box.wrap_lines(input, 1, 5, ascii)
      assert.are.equal("+-------+", result[1])
      assert.are.equal("| hello | world", result[2])
      assert.are.equal("+-------+", result[3])
    end)

    it("uses bold preset", function()
      local actual = box.wrap_lines({ "hello" }, 1, 5, bold)
      assert.are.equal("┏", actual[1]:sub(1, 3))
    end)

    it("uses double preset", function()
      local actual = box.wrap_lines({ "hello" }, 1, 5, double)
      assert.are.equal("╔", actual[1]:sub(1, 3))
    end)

    it("uses ascii preset", function()
      local input = { "hello" }
      local expected = {
        "+-------+",
        "| hello |",
        "+-------+",
      }
      assert.are.same(expected, box.wrap_lines(input, 1, 5, ascii))
    end)

    it("handles unicode content (display-col coordinate)", function()
      local result = box.wrap_lines({ "日本語" }, 1, 6, thin)
      assert.are.equal("┌", result[1]:sub(1, 3))
      assert.truthy(vim.startswith(result[2], "│"))
    end)

    it("does not mutate the input table", function()
      local input = { "hello" }
      box.wrap_lines(input, 1, 5, thin)
      assert.are.same({ "hello" }, input)
    end)

    it("opts.width pads content with default left align", function()
      local actual = box.wrap_lines({ "hi" }, 1, 2, thin, { width = 10 })
      assert.are.same({
        "┌────────┐",
        "│ hi     │",
        "└────────┘",
      }, actual)
    end)

    it("opts.width + align=right pads on the left", function()
      local actual = box.wrap_lines({ "hi" }, 1, 2, thin, { width = 10, align = "right" })
      assert.are.same({
        "┌────────┐",
        "│     hi │",
        "└────────┘",
      }, actual)
    end)

    it("opts.width + align=center pads both sides", function()
      local actual = box.wrap_lines(
        { "hi" },
        1,
        2,
        thin,
        { width = 10, align = "center" }
      )
      assert.are.same({
        "┌────────┐",
        "│   hi   │",
        "└────────┘",
      }, actual)
    end)

    it("opts.width smaller than content: overflow (use content width)", function()
      local actual = box.wrap_lines({ "hello world" }, 1, 11, thin, { width = 5 })
      assert.are.same({
        "┌─────────────┐",
        "│ hello world │",
        "└─────────────┘",
      }, actual)
    end)

    it("opts.width pads multiple rows to same width with align", function()
      local actual = box.wrap_lines({ "hi", "hello" }, 1, 5, thin, {
        width = 12,
        align = "center",
      })
      assert.are.same({
        "┌──────────┐",
        "│    hi    │",
        "│  hello   │",
        "└──────────┘",
      }, actual)
    end)
  end)

  describe("unwrap_lines", function()
    it("strips a single-content-row box", function()
      local input = {
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      }
      assert.are.same({ "hello" }, box.unwrap_lines(input, 1, 9, thin))
    end)

    it("strips a multi-content-row box", function()
      local input = {
        "┌─────┐",
        "│ foo │",
        "│ bar │",
        "└─────┘",
      }
      assert.are.same({ "foo", "bar" }, box.unwrap_lines(input, 1, 7, thin))
    end)

    it("removes trailing padding spaces", function()
      local input = {
        "┌───────┐",
        "│ hi    │",
        "│ hello │",
        "└───────┘",
      }
      assert.are.same({ "hi", "hello" }, box.unwrap_lines(input, 1, 9, thin))
    end)

    it("preserves prefix and suffix around the box", function()
      local input = {
        "  +-------+",
        "  | hello | extra",
        "  +-------+",
      }
      assert.are.same({ "  hello extra" }, box.unwrap_lines(input, 3, 11, ascii))
    end)

    it("round-trips with wrap_lines (thin)", function()
      local original = { "foo", "bar baz" }
      local drawn = box.wrap_lines(original, 1, 7, thin)
      -- Box's right side sits at display col content_end + 4 (l + space +
      -- content + space + r), so r_disp = 7 + 4 = 11.
      assert.are.same(original, box.unwrap_lines(drawn, 1, 11, thin))
    end)

    it("round-trips with wrap_lines (bold)", function()
      local original = { "hello" }
      local drawn = box.wrap_lines(original, 1, 5, bold)
      assert.are.same(original, box.unwrap_lines(drawn, 1, 9, bold))
    end)

    it("round-trips with wrap_lines (ascii)", function()
      local original = { "hello" }
      local drawn = box.wrap_lines(original, 1, 5, ascii)
      assert.are.same(original, box.unwrap_lines(drawn, 1, 9, ascii))
    end)
  end)

  describe("box.wrap (Snapshot → Edit[])", function()
    it("linewise: returns one edit covering the selection range", function()
      local snap = {
        lines = { "hello" },
        row_start = 0,
        row_end = 1,
        start_col = 1,
        end_col = 1,
        filetype = "",
        is_linewise = true,
      }
      local edits = box.wrap(snap, thin, cbox.config.presets)
      assert.are.equal(1, #edits)
      assert.are.equal(0, edits[1].row_start)
      assert.are.equal(1, edits[1].row_end)
      assert.are.same({
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      }, edits[1].new_lines)
    end)

    it("linewise: strips and restores comment prefix", function()
      local snap = {
        lines = { "-- hello" },
        row_start = 0,
        row_end = 1,
        start_col = 1,
        end_col = 1,
        filetype = "lua",
        is_linewise = true,
      }
      local edits = box.wrap(snap, thin, cbox.config.presets)
      assert.are.same({
        "-- ┌───────┐",
        "-- │ hello │",
        "-- └───────┘",
      }, edits[1].new_lines)
    end)

    it("blockwise: returns a single edit when no adjacent borders to merge", function()
      local snap = {
        lines = { "hello" },
        row_start = 0,
        row_end = 1,
        start_col = 1,
        end_col = 5,
        filetype = "",
        is_linewise = false,
      }
      local edits = box.wrap(snap, ascii, cbox.config.presets)
      assert.are.equal(1, #edits)
      assert.are.same({
        "+-------+",
        "| hello |",
        "+-------+",
      }, edits[1].new_lines)
    end)

    it("blockwise: plain wrap (no merge) — content + new sides preserved", function()
      -- box.wrap is the rendering primitive; it does not detect existing
      -- boxes around the selection.  api.wrap routes those through
      -- erase + re-wrap (merge_overlapping) before getting here.
      local snap = {
        lines = { "┃ hello ┃ world" },
        row_start = 1,
        row_end = 2,
        start_col = 15,
        end_col = 19,
        filetype = "",
        is_linewise = false,
      }
      local edits = box.wrap(snap, bold, cbox.config.presets)
      assert.are.equal(1, #edits)
      assert.are.same({
        "          ┏━━━━━━━┓",
        "┃ hello ┃ ┃ world ┃",
        "          ┗━━━━━━━┛",
      }, edits[1].new_lines)
    end)

    it("rejects degenerate column ranges", function()
      local snap = {
        lines = { "hello" },
        row_start = 0,
        row_end = 1,
        start_col = 5,
        end_col = 1,
        filetype = "",
        is_linewise = false,
      }
      assert.are.same({}, box.wrap(snap, ascii, cbox.config.presets))
    end)

    it("blockwise: overlays comment prefix on border rows", function()
      local snap = {
        lines = { "-- hello world" },
        row_start = 0,
        row_end = 1,
        start_col = 10,
        end_col = 14,
        filetype = "lua",
        is_linewise = false,
      }
      local edits = box.wrap(snap, ascii, cbox.config.presets)
      assert.are.same({
        "--       +-------+",
        "-- hello | world |",
        "--       +-------+",
      }, edits[1].new_lines)
    end)
  end)

  describe("box.unwrap (Snapshot → Edit[])", function()
    it("returns empty edit list when first line is not a recognized border", function()
      local snap = {
        lines = { "plain", "text", "here" },
        row_start = 0,
        row_end = 3,
        start_col = 1,
        end_col = 1,
        filetype = "",
        is_linewise = true,
      }
      assert.are.same({}, box.unwrap(snap, cbox.config.presets))
    end)

    it("strips a linewise box back to its content", function()
      local snap = {
        lines = {
          "┌───────┐",
          "│ hello │",
          "└───────┘",
        },
        row_start = 0,
        row_end = 3,
        start_col = 1,
        end_col = 1,
        filetype = "",
        is_linewise = true,
      }
      local edits = box.unwrap(snap, cbox.config.presets)
      assert.are.equal(1, #edits)
      assert.are.same({ "hello" }, edits[1].new_lines)
    end)

    it("strips a blockwise box back to its content", function()
      local snap = {
        lines = {
          "+-------+",
          "| hello |",
          "+-------+",
        },
        row_start = 0,
        row_end = 3,
        start_col = 1,
        end_col = 9,
        filetype = "",
        is_linewise = false,
      }
      local edits = box.unwrap(snap, cbox.config.presets)
      assert.are.same({ "hello" }, edits[1].new_lines)
    end)
  end)

  describe("unwrap_overlapping_blockwise", function()
    it("collapses two adjacent boxes into trimmed content", function()
      local lines = {
        "┏━━━━━━━┓ ┏━━━━━━━┓",
        "┃ hello ┃ ┃ world ┃",
        "┗━━━━━━━┛ ┗━━━━━━━┛",
      }
      local boxes = {
        {
          top = 1,
          bottom = 3,
          preset = bold,
          top_range = { left_byte = 1, right_byte = 25 },
          bottom_range = { left_byte = 1, right_byte = 25 },
          side_range = { left_byte = 1, right_byte = 11 },
          disp_range = { start = 1, ["end"] = 9 },
        },
        {
          top = 1,
          bottom = 3,
          preset = bold,
          top_range = { left_byte = 29, right_byte = 53 },
          bottom_range = { left_byte = 29, right_byte = 53 },
          side_range = { left_byte = 15, right_byte = 25 },
          disp_range = { start = 11, ["end"] = 19 },
        },
      }
      local result = box.unwrap_overlapping_blockwise(lines, 1, boxes)
      assert.are.same({ "hello world" }, result.lines)
      assert.are.equal(0, result.content_row_offset_first)
      assert.are.same({ start_col = 1, end_col = 11 }, result.content_byte_range)
    end)
  end)
end)
