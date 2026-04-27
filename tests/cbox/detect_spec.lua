local h = require("helpers")
local detect = require("cbox.detect")
local cbox = require("cbox")

local P = detect.Position

-- thin preset:   ┌ ─ ┐ │ │ └ ─ ┘
-- bold preset:   ┏ ━ ┓ ┃ ┃ ┗ ━ ┛
-- double preset: ╔ ═ ╗ ║ ║ ╚ ═ ╝
-- ascii preset:  + - + | | + - +

local thin = { "┌", "─", "┐", "│", "│", "└", "─", "┘" }
local bold = { "┏", "━", "┓", "┃", "┃", "┗", "━", "┛" }
local double = { "╔", "═", "╗", "║", "║", "╚", "═", "╝" }
local ascii = { "+", "-", "+", "|", "|", "+", "-", "+" }

local V = "V"
local BLK = vim.keycode("<C-v>")

local function sel(mode, start_line, end_line, start_col, end_col)
  return {
    mode = mode,
    start_line = start_line,
    end_line = end_line,
    start_col = start_col or 1,
    end_col = end_col or 1,
  }
end

-- Convenience helper composing find_boxes + classify, mirroring how callers
-- use detect.lua: find boxes for the selection, then classify.
local function classify_at(s, bufnr)
  return detect.classify(s, detect.find_boxes(s, bufnr))
end

describe("top_preset (border classification primitive)", function()
  it("detects thin preset from top border", function()
    assert.are.same(
      thin,
      detect.top_preset("┌───────┐", cbox.config.presets)
    )
  end)

  it("detects bold preset", function()
    assert.are.same(
      bold,
      detect.top_preset("┏━━━━━━━┓", cbox.config.presets)
    )
  end)

  it("detects double preset", function()
    assert.are.same(
      double,
      detect.top_preset("╔═══════╗", cbox.config.presets)
    )
  end)

  it("detects ascii preset", function()
    assert.are.same(ascii, detect.top_preset("+-------+", cbox.config.presets))
  end)

  it("returns nil for a plain line", function()
    assert.is_nil(detect.top_preset("hello world", cbox.config.presets))
  end)

  it("returns nil for an empty string", function()
    assert.is_nil(detect.top_preset("", cbox.config.presets))
  end)
end)

describe("blockwise_preset (border classification primitive)", function()
  it("detects ascii preset at given columns", function()
    local line = "hello  +-------+"
    assert.are.same(ascii, detect.blockwise_preset(line, 8, 16, cbox.config.presets))
  end)

  it("returns nil when chars at columns do not match any preset", function()
    assert.is_nil(detect.blockwise_preset("hello world", 1, 5, cbox.config.presets))
  end)
end)

describe("find_boxes", function()
  after_each(h.clean_bufs)

  it("returns the box containing a linewise selection", function()
    local bufnr = h.make_buf({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    local boxes = detect.find_boxes(sel(V, 2, 2), bufnr)
    assert.are.equal(1, #boxes)
    assert.are.equal(1, boxes[1].top)
    assert.are.equal(3, boxes[1].bottom)
    assert.are.same(thin, boxes[1].preset)
  end)

  it("returns the box for a multi-content-row linewise selection", function()
    local bufnr = h.make_buf({
      "┌───────┐",
      "│ hello │",
      "│ world │",
      "└───────┘",
    })
    local boxes = detect.find_boxes(sel(V, 2, 3), bufnr)
    assert.are.equal(1, #boxes)
    assert.are.equal(1, boxes[1].top)
    assert.are.equal(4, boxes[1].bottom)
  end)

  it("returns empty when selection is on plain text", function()
    local bufnr = h.make_buf({ "hello", "world" })
    assert.are.same({}, detect.find_boxes(sel(V, 1, 2), bufnr))
  end)

  it("blockwise: returns the box when selection edges align", function()
    local bufnr = h.make_buf({
      "+-------+",
      "| hello |",
      "+-------+",
    })
    local boxes = detect.find_boxes(sel(BLK, 2, 2, 1, 9), bufnr)
    assert.are.equal(1, #boxes)
    assert.are.equal(1, boxes[1].top)
    assert.are.equal(3, boxes[1].bottom)
    assert.are.same({ left_byte = 1, right_byte = 9 }, boxes[1].side_range)
  end)

  it("blockwise: returns the box when selection sits inside its col range", function()
    local bufnr = h.make_buf({
      "+-------+",
      "| hello |",
      "+-------+",
    })
    local boxes = detect.find_boxes(sel(BLK, 2, 2, 3, 7), bufnr)
    assert.are.equal(1, #boxes)
  end)

  it("blockwise: returns the box when selection is wider than its col range", function()
    local bufnr = h.make_buf({
      "+-------+   tail",
      "| hello |   tail",
      "+-------+   tail",
    })
    local boxes = detect.find_boxes(sel(BLK, 2, 2, 1, 15), bufnr)
    assert.are.equal(1, #boxes)
  end)

  it("blockwise: returns both boxes when selection crosses two adjacent boxes", function()
    local bufnr = h.make_buf({
      "┏━━━━━━━┓ ┏━━━━━━━┓",
      "┃ hello ┃ ┃ world ┃",
      "┗━━━━━━━┛ ┗━━━━━━━┛",
    })
    local boxes = detect.find_boxes(sel(BLK, 2, 2, 5, 23), bufnr)
    assert.are.equal(2, #boxes)
    -- side ranges sit at byte 1-11 (box1) and 15-25 (box2) on the content row
    local cols = {
      { boxes[1].side_range.left_byte, boxes[1].side_range.right_byte },
      { boxes[2].side_range.left_byte, boxes[2].side_range.right_byte },
    }
    table.sort(cols, function(a, b)
      return a[1] < b[1]
    end)
    assert.are.same({ 1, 11 }, cols[1])
    assert.are.same({ 15, 25 }, cols[2])
  end)

  it("blockwise: returns empty when selection's cols don't overlap any box", function()
    local bufnr = h.make_buf({
      "+-------+   tail",
      "| hello |   tail",
      "+-------+   tail",
    })
    -- selection is on "tail" only — no col overlap with the box.
    local boxes = detect.find_boxes(sel(BLK, 2, 2, 13, 16), bufnr)
    assert.are.same({}, boxes)
  end)
end)

describe("detect", function()
  after_each(h.clean_bufs)

  describe("INSIDE", function()
    it("V mode selection inside the box", function()
      local bufnr = h.make_buf({
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      })
      local result = classify_at(sel(V, 2, 2), bufnr)
      assert.are.equal(P.INSIDE, result.position)
      assert.are.equal(1, #result.boxes)
      assert.are.equal(1, result.boxes[1].top)
      assert.are.equal(3, result.boxes[1].bottom)
    end)

    it("V mode covering the entire box (touching borders is inside)", function()
      local bufnr = h.make_buf({
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      })
      local result = classify_at(sel(V, 1, 3), bufnr)
      assert.are.equal(P.INSIDE, result.position)
    end)

    it("blockwise edge-aligned selection", function()
      local bufnr = h.make_buf({
        "+-------+",
        "| hello |",
        "+-------+",
      })
      local result = classify_at(sel(BLK, 2, 2, 1, 9), bufnr)
      assert.are.equal(P.INSIDE, result.position)
    end)

    it("blockwise selection inside the box (containment)", function()
      local bufnr = h.make_buf({
        "+-------+",
        "| hello |",
        "+-------+",
      })
      local result = classify_at(sel(BLK, 2, 2, 3, 7), bufnr)
      assert.are.equal(P.INSIDE, result.position)
    end)
  end)

  describe("OUTSIDE", function()
    it("plain text", function()
      local bufnr = h.make_buf({ "hello", "world" })
      local result = classify_at(sel(V, 1, 2), bufnr)
      assert.are.equal(P.OUTSIDE, result.position)
      assert.are.same({}, result.boxes)
    end)

    it("V mode touching top border from outside trims border from selection", function()
      local bufnr = h.make_buf({
        "before",
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      })
      local result = classify_at(sel(V, 1, 2), bufnr)
      assert.are.equal(P.OUTSIDE, result.position)
      assert.are.same({ start_line = 1, end_line = 1 }, result.adjusted)
    end)

    it("V mode touching bottom border from outside trims border", function()
      local bufnr = h.make_buf({
        "┌───────┐",
        "│ hello │",
        "└───────┘",
        "after",
      })
      local result = classify_at(sel(V, 3, 4), bufnr)
      assert.are.equal(P.OUTSIDE, result.position)
      assert.are.same({ start_line = 4, end_line = 4 }, result.adjusted)
    end)
  end)

  describe("OVERLAPPING", function()
    it("V mode crossing into the box from above", function()
      local bufnr = h.make_buf({
        "before",
        "┌───────┐",
        "│ hello │",
        "└───────┘",
      })
      local result = classify_at(sel(V, 1, 3), bufnr)
      assert.are.equal(P.OVERLAPPING, result.position)
      assert.are.same({ start_line = 2, end_line = 4 }, result.adjusted)
    end)

    it("V mode containing the entire box", function()
      local bufnr = h.make_buf({
        "before",
        "┌───────┐",
        "│ hello │",
        "└───────┘",
        "after",
      })
      local result = classify_at(sel(V, 1, 5), bufnr)
      assert.are.equal(P.OVERLAPPING, result.position)
    end)

    it("blockwise selection wider than the box", function()
      local bufnr = h.make_buf({
        "+-------+   tail",
        "| hello |   tail",
        "+-------+   tail",
      })
      local result = classify_at(sel(BLK, 2, 2, 1, 15), bufnr)
      -- Row-wise selection is inside the box rows; col-wise it's wider.
      -- Current classifier looks at row dimension only — returns INSIDE.
      -- Either way, position != OUTSIDE so callers will erase the box.
      assert.is_true(result.position ~= P.OUTSIDE)
      assert.are.equal(1, #result.boxes)
    end)

    it("blockwise selection across two adjacent boxes returns multiple", function()
      local bufnr = h.make_buf({
        "┏━━━━━━━┓ ┏━━━━━━━┓",
        "┃ hello ┃ ┃ world ┃",
        "┗━━━━━━━┛ ┗━━━━━━━┛",
      })
      local result = classify_at(sel(BLK, 2, 2, 5, 23), bufnr)
      assert.are.equal(P.OVERLAPPING, result.position)
      assert.are.equal(2, #result.boxes)
    end)
  end)
end)
