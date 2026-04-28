-- comment.lua is a pure module: no Neovim buffer API.
-- Tests use plain tables — no bufnr, no make_buf, no after_each cleanup needed.

local comment = require("cbox.comment")
local box = require("cbox.render")
local detect = require("cbox.detect")
local cbox = require("cbox")

local thin = cbox.config.presets.thin

describe("comment (pure functions)", function()
  describe("strip", function()
    it("strips lua line comments", function()
      local input = { "-- hello", "-- world" }
      local lines, ctx = comment.strip(input, "lua")
      assert.are.same({ "hello", "world" }, lines)
      assert.are.equal("-- ", ctx.prefix)
    end)

    it("strips c++ line comments", function()
      local input = { "// foo", "// bar" }
      local lines, ctx = comment.strip(input, "cpp")
      assert.are.same({ "foo", "bar" }, lines)
      assert.are.equal("// ", ctx.prefix)
    end)

    it("preserves leading indent in prefix", function()
      local input = { "  -- hello", "  -- world" }
      local lines, ctx = comment.strip(input, "lua")
      assert.are.same({ "hello", "world" }, lines)
      assert.are.equal("  -- ", ctx.prefix)
    end)

    it("handles marker without trailing space", function()
      local input = { "--hello" }
      local lines, ctx = comment.strip(input, "lua")
      assert.are.same({ "hello" }, lines)
      assert.are.equal("--", ctx.prefix)
    end)

    it("returns nil ctx for unknown filetype", function()
      local input = { "-- hello" }
      local lines, ctx = comment.strip(input, "unknown_ft")
      assert.are.same(input, lines)
      assert.is_nil(ctx)
    end)

    it("returns nil ctx when not all lines share the prefix", function()
      local input = { "-- hello", "world" }
      local lines, ctx = comment.strip(input, "lua")
      assert.are.same(input, lines)
      assert.is_nil(ctx)
    end)

    it("returns nil ctx when indent is inconsistent", function()
      local input = { "  -- hello", "-- world" }
      local lines, ctx = comment.strip(input, "lua")
      assert.are.same(input, lines)
      assert.is_nil(ctx)
    end)

    it("returns nil ctx for empty lines list", function()
      local lines, ctx = comment.strip({}, "lua")
      assert.are.same({}, lines)
      assert.is_nil(ctx)
    end)

    it("does not mutate the input table", function()
      local input = { "-- hello" }
      comment.strip(input, "lua")
      assert.are.same({ "-- hello" }, input)
    end)
  end)

  describe("restore", function()
    it("prepends prefix to all lines", function()
      local ctx = { prefix = "-- " }
      local actual = comment.restore({ "hello", "world" }, ctx)
      assert.are.same({ "-- hello", "-- world" }, actual)
    end)

    it("prepends prefix to box border lines", function()
      local ctx = { prefix = "-- " }
      local actual = comment.restore(
        { "┌───────┐", "│ hello │", "└───────┘" },
        ctx
      )
      local expected = {
        "-- ┌───────┐",
        "-- │ hello │",
        "-- └───────┘",
      }
      assert.are.same(expected, actual)
    end)

    it("preserves indent in prefix", function()
      local ctx = { prefix = "  -- " }
      local actual = comment.restore({ "hi" }, ctx)
      assert.are.same({ "  -- hi" }, actual)
    end)
  end)

  describe("round-trip", function()
    it("strip → wrap_lines → restore produces a commented box", function()
      local input = { "-- hello", "-- world" }
      local stripped, ctx = comment.strip(input, "lua")
      local boxed = box.wrap_lines(stripped, 1, 5, thin)
      local actual = comment.restore(boxed, ctx)
      local expected = {
        "-- ┌───────┐",
        "-- │ hello │",
        "-- │ world │",
        "-- └───────┘",
      }
      assert.are.same(expected, actual)
    end)

    it("strip → unwrap_lines → restore recovers commented content", function()
      local box_lines = {
        "-- ┌───────┐",
        "-- │ hello │",
        "-- │ world │",
        "-- └───────┘",
      }
      local stripped, ctx = comment.strip(box_lines, "lua")
      -- stripped = { "┌───────┐", "│ hello │", "│ world │", "└───────┘" }
      local preset = detect.top_preset(stripped[1], cbox.config.presets)
      local erased = box.unwrap_lines(stripped, 1, 9, preset)
      local actual = comment.restore(erased, ctx)
      assert.are.same({ "-- hello", "-- world" }, actual)
    end)
  end)

  describe("spanning block", function()
    it("strip detects a single spanning /* */ around a multi-row content", function()
      local input = {
        "/* foo",
        "   bar */",
      }
      local lines, ctx = comment.strip(input, "c")
      assert.are.same({ "foo", "bar" }, lines)
      assert.is_true(ctx.is_spanning)
      assert.are.equal("block", ctx.kind)
      assert.are.equal("", ctx.indent_outer)
      assert.are.equal("/* ", ctx.before)
      assert.are.equal(" */", ctx.after)
    end)

    it("strip detects spanning with outer indent", function()
      local input = {
        "  /* ┌─────┐",
        "     │ box │",
        "     └─────┘ */",
      }
      local lines, ctx = comment.strip(input, "c")
      assert.are.same(
        { "┌─────┐", "│ box │", "└─────┘" },
        lines
      )
      assert.is_true(ctx.is_spanning)
      assert.are.equal("  ", ctx.indent_outer)
    end)

    it("strip detects HTML spanning <!-- ... -->", function()
      local input = {
        "<!-- ┌─────┐",
        "     │ foo │",
        "     └─────┘ -->",
      }
      local lines, ctx = comment.strip(input, "html")
      assert.are.same(
        { "┌─────┐", "│ foo │", "└─────┘" },
        lines
      )
      assert.is_true(ctx.is_spanning)
    end)

    it(
      "per-line block-only filetype prefers per-line over spanning when both match",
      function()
        -- A 1-row HTML comment matches BOTH per-line (each row has prefix and
        -- suffix) and spanning (only row, has both delimiters).  detect_perline
        -- runs first so per-line wins — keeps existing block-only filetype
        -- behavior.
        local input = { "<!-- foo -->" }
        local lines, ctx = comment.strip(input, "html")
        assert.are.same({ "foo" }, lines)
        assert.is_nil(ctx.is_spanning)
      end
    )

    it("restore re-emits a tight spanning around content rows", function()
      local input = {
        "  /* foo bar",
        "     baz */",
      }
      local stripped, ctx = comment.strip(input, "c")
      assert.are.same({ "foo bar", "baz" }, stripped)
      local restored = comment.restore(stripped, ctx)
      assert.are.same({
        "  /* foo bar",
        "     baz     */",
      }, restored)
    end)

    it("strip → unwrap_lines → restore (spanning) emits tight spanning", function()
      -- restore with spanning ctx still works — used when callers want to
      -- preserve spanning form.  Unwrap callers use `demote_for_unwrap`
      -- before restore to get line output instead.
      local input = {
        "  /* ┌─────┐",
        "     │ box │",
        "     │ box │",
        "     └─────┘ */",
      }
      local stripped, ctx = comment.strip(input, "c")
      assert.is_true(ctx.is_spanning)
      local preset = detect.top_preset(stripped[1], cbox.config.presets)
      local erased = box.unwrap_lines(stripped, 1, 7, preset)
      local actual = comment.restore(erased, ctx)
      assert.are.same({
        "  /* box",
        "     box */",
      }, actual)
    end)

    it("demote_for_unwrap converts spanning ctx to per-line line ctx", function()
      local input = {
        "  /* foo",
        "     bar */",
      }
      local _, ctx = comment.strip(input, "c")
      assert.is_true(ctx.is_spanning)
      local demoted = comment.demote_for_unwrap(ctx, "c")
      assert.are.equal("line", demoted.kind)
      assert.are.equal("  // ", demoted.prefix)
      assert.are.equal("", demoted.suffix)
    end)

    it(
      "demote_for_unwrap on HTML (no line variant) falls back to block per-row",
      function()
        local input = {
          "<!-- foo",
          "     bar -->",
        }
        local _, ctx = comment.strip(input, "html")
        assert.is_true(ctx.is_spanning)
        local demoted = comment.demote_for_unwrap(ctx, "html")
        assert.are.equal("block", demoted.kind)
        assert.are.equal("<!-- ", demoted.prefix)
        assert.are.equal(" -->", demoted.suffix)
      end
    )

    it("demote_for_unwrap is a no-op for non-spanning ctx", function()
      local ctx = { kind = "line", prefix = "// ", restore_prefix = "// ", suffix = "" }
      local demoted = comment.demote_for_unwrap(ctx, "c")
      assert.are.same(ctx, demoted)
    end)
  end)
end)
