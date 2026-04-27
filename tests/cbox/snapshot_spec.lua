-- snapshot.lua is the only impure module besides api.lua: it reads the buffer
-- to produce Snapshot tables. These tests verify the buffer→Snapshot mapping.

local h = require("helpers")
local snapshot = require("cbox.snapshot")

local function sel(mode, start_line, end_line, start_col, end_col)
  return {
    mode = mode,
    start_line = start_line,
    end_line = end_line,
    start_col = start_col or 1,
    end_col = end_col or 1,
  }
end

local V = "V"
local BLK = vim.keycode("<C-v>")

describe("snapshot.take", function()
  after_each(h.clean_bufs)

  describe("without box (wrap scenario)", function()
    it("V mode: captures lines + 0-indexed row range", function()
      local bufnr = h.make_buf({ "alpha", "beta", "gamma" })
      local snap = snapshot.take(sel(V, 1, 2), bufnr)
      assert.are.same({ "alpha", "beta" }, snap.lines)
      assert.are.equal(0, snap.row_start)
      assert.are.equal(2, snap.row_end)
      assert.is_true(snap.is_linewise)
    end)

    it("blockwise single-line: linewise=false, captures the row", function()
      local bufnr = h.make_buf({
        "above row",
        "middle content",
        "below row",
      })
      local snap = snapshot.take(sel(BLK, 2, 2, 1, 6), bufnr)
      assert.is_false(snap.is_linewise)
      assert.are.same({ "middle content" }, snap.lines)
    end)

    it("multi-line v mode: linewise, captures the rows", function()
      local bufnr = h.make_buf({ "above", "x", "y", "below" })
      local snap = snapshot.take(sel("v", 2, 3, 1, 1), bufnr)
      assert.is_true(snap.is_linewise)
      assert.are.same({ "x", "y" }, snap.lines)
    end)

    it("captures filetype from the buffer", function()
      local bufnr = h.make_buf({ "-- hello" }, "lua")
      local snap = snapshot.take(sel(V, 1, 1), bufnr)
      assert.are.equal("lua", snap.filetype)
    end)
  end)

  describe("with box (erase scenario)", function()
    it("captures lines from box.top..box.bottom and the matching row range", function()
      local bufnr = h.make_buf({
        "leading",
        "+-------+",
        "| hello |",
        "+-------+",
        "trailing",
      })
      local snap = snapshot.take(sel(BLK, 3, 3, 1, 9), bufnr, { top = 2, bottom = 4 })
      assert.are.same({
        "+-------+",
        "| hello |",
        "+-------+",
      }, snap.lines)
      assert.are.equal(1, snap.row_start)
      assert.are.equal(4, snap.row_end)
      assert.are.equal(1, snap.start_col)
      assert.are.equal(9, snap.end_col)
      assert.is_false(snap.is_linewise)
    end)
  end)
end)
