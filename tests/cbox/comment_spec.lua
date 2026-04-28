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
end)
