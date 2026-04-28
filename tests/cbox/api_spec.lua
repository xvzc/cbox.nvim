local h = require("helpers")
local api = require("cbox.api")
local detect = require("cbox.detect")

local function get_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

-- Dispatcher mirroring `cbox.toggle` from init.lua.
local function toggle(s, bufnr, preset_name)
  local boxes = detect.find_boxes(s, bufnr)
  if #boxes ~= 1 then
    return api.wrap(s, bufnr, preset_name)
  end
  local position = detect.classify(s, boxes).position
  if position == detect.Position.OUTSIDE then
    return api.wrap(s, bufnr, preset_name)
  end
  if detect.is_linewise(s) then
    local b = boxes[1]
    local strictly_inside = s.start_line > b.top and s.end_line < b.bottom
    if strictly_inside and not detect.box_is_clean_linewise(b, bufnr) then
      api.wrap(s, bufnr, preset_name)
    else
      api.unwrap(s, bufnr)
    end
  elseif detect.boundaries_align(s, boxes[1], bufnr) then
    api.unwrap(s, bufnr)
  else
    api.wrap(s, bufnr, preset_name)
  end
end

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

describe("wrap", function()
  after_each(h.clean_bufs)

  it("V mode: draws a linewise box", function()
    local bufnr = h.make_buf({ "hello" })
    api.wrap(sel(V, 1, 1), bufnr, "thin")
    assert.are.same({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    }, get_lines(bufnr))
  end)

  it("V mode: wraps only selected lines, leaves others untouched", function()
    local bufnr = h.make_buf({ "before", "hello", "after" })
    api.wrap(sel(V, 2, 2), bufnr, "thin")
    assert.are.same({
      "before",
      "┌───────┐",
      "│ hello │",
      "└───────┘",
      "after",
    }, get_lines(bufnr))
  end)

  it("V mode multi-line: pads to longest width", function()
    local bufnr = h.make_buf({ "hi", "hello" })
    api.wrap(sel(V, 1, 2), bufnr, "thin")
    assert.are.same({
      "┌───────┐",
      "│ hi    │",
      "│ hello │",
      "└───────┘",
    }, get_lines(bufnr))
  end)

  it("<C-v> mode: draws a blockwise box", function()
    local bufnr = h.make_buf({ "hello" })
    api.wrap(sel(BLK, 1, 1, 1, 5), bufnr, "ascii")
    assert.are.same({
      "+-------+",
      "| hello |",
      "+-------+",
    }, get_lines(bufnr))
  end)

  it("v single-line: draws a blockwise box", function()
    local bufnr = h.make_buf({ "hello" })
    api.wrap(sel("v", 1, 1, 1, 5), bufnr, "ascii")
    assert.are.same({
      "+-------+",
      "| hello |",
      "+-------+",
    }, get_lines(bufnr))
  end)

  it("v multi-line: draws a linewise box", function()
    local bufnr = h.make_buf({ "hello", "world" })
    api.wrap(sel("v", 1, 2, 1, 5), bufnr, "thin")
    assert.are.same({
      "┌───────┐",
      "│ hello │",
      "│ world │",
      "└───────┘",
    }, get_lines(bufnr))
  end)

  it("uses config.theme when no preset_name given", function()
    local bufnr = h.make_buf({ "hello" })
    api.wrap(sel(V, 1, 1), bufnr)
    local lines = get_lines(bufnr)
    assert.truthy(vim.startswith(lines[1], "┌"))
  end)

  it("V mode with lua comments: strips prefix, draws box, restores prefix", function()
    local bufnr = h.make_buf({ "-- hello", "-- world" }, "lua")
    api.wrap(sel(V, 1, 2), bufnr, "thin")
    assert.are.same({
      "-- ┌───────┐",
      "-- │ hello │",
      "-- │ world │",
      "-- └───────┘",
    }, get_lines(bufnr))
  end)

  it("<C-v> mode with lua comment prefix: border rows get the comment prefix", function()
    local bufnr = h.make_buf({ "-- hello world" }, "lua")
    api.wrap(sel(BLK, 1, 1, 10, 14), bufnr, "bold")
    assert.are.same({
      "--       ┏━━━━━━━┓",
      "-- hello ┃ world ┃",
      "--       ┗━━━━━━━┛",
    }, get_lines(bufnr))
  end)

  it(
    "<C-v> mode: merges borders into adjacent box borders instead of inserting new rows",
    function()
      local bufnr = h.make_buf({
        "-- ┏━━━━━━━┓ ",
        "-- ┃ hello ┃ world",
        "-- ┗━━━━━━━┛ ",
      }, "lua")
      api.wrap(sel(BLK, 2, 2, 18, 22), bufnr, "bold")
      -- Selection's cols don't overlap the existing box → no boxes detected
      -- → plain wrap → merge_into_borders extends the existing borders to
      -- form a second adjacent box.
      assert.are.same({
        "-- ┏━━━━━━━┓ ┏━━━━━━━┓",
        "-- ┃ hello ┃ ┃ world ┃",
        "-- ┗━━━━━━━┛ ┗━━━━━━━┛",
      }, get_lines(bufnr))
    end
  )

  it(
    "<C-v> mode: append-merge ignores trailing whitespace on adjacent borders",
    function()
      local bufnr = h.make_buf({
        "┏━━━━━━━┓      ",
        "┃ hello ┃ world",
        "┗━━━━━━━┛      ",
      })
      api.wrap(sel(BLK, 2, 2, 15, 19), bufnr, "bold")
      -- Adjacent borders have 6 trailing spaces; without rstripping, the
      -- raw display width (15) >= box's left edge (11) would block append-
      -- merge.  Trailing whitespace must be trimmed before the width check.
      assert.are.same({
        "┏━━━━━━━┓ ┏━━━━━━━┓",
        "┃ hello ┃ ┃ world ┃",
        "┗━━━━━━━┛ ┗━━━━━━━┛",
      }, get_lines(bufnr))
    end
  )

  it(
    "<C-v> mode: replace-merge when adjacent border extends past selection start",
    function()
      local bufnr = h.make_buf({
        "--       ┏━━━━━━━┓",
        "-- hello ┃ world ┃",
        "--       ┗━━━━━━━┛",
      }, "lua")
      api.wrap(sel(BLK, 2, 2, 4, 8), bufnr, "bold")
      assert.are.same({
        "-- ┏━━━━━━━┓ ┏━━━━━━━┓",
        "-- ┃ hello ┃ ┃ world ┃",
        "-- ┗━━━━━━━┛ ┗━━━━━━━┛",
      }, get_lines(bufnr))
    end
  )

  it(
    "<C-v> mode: splice-merge wraps text sitting in a gap between two adjacent boxes",
    function()
      -- Selection sits between two existing boxes (in the whitespace gap on
      -- above/below).  Byte-replace fails because above/below have wider
      -- chars (┌, ─) at byte offsets that don't match content row's prefix.
      -- Pad-and-append fails because above/below extend past box_disp_start.
      -- The display-based splice strategy slots the new border in at the
      -- correct disp range, shifting the right-side existing border further
      -- right by the new box's expansion.
      local bufnr = h.make_buf({
        "--          ┌───┐   ┌───┐",
        "-- box  box │ h │ell│ o │",
        "--          └───┘   └───┘",
      }, "lua")
      api.wrap(sel(BLK, 2, 2, 22, 24), bufnr, "thin")
      assert.are.same({
        "--          ┌───┐┌─────┐┌───┐",
        "-- box  box │ h ││ ell ││ o │",
        "--          └───┘└─────┘└───┘",
      }, get_lines(bufnr))
    end
  )

  it("block-only filetype (html) on plain input: plain box (no auto-comment)", function()
    -- Plain input stays plain after wrap, preserving wrap → unwrap round-trip.
    -- User must explicitly comment the input first if they want a commented box.
    local bufnr = h.make_buf({ "hello" }, "html")
    api.wrap(sel(V, 1, 1), bufnr, { theme = "thin" })
    assert.are.same({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    }, get_lines(bufnr))
  end)

  it(
    "block-only filetype (html): preserves block comment when input is commented",
    function()
      local bufnr = h.make_buf({ "<!-- hello -->" }, "html")
      api.wrap(sel(V, 1, 1), bufnr, { theme = "thin" })
      assert.are.same({
        "<!-- ┌───────┐ -->",
        "<!-- │ hello │ -->",
        "<!-- └───────┘ -->",
      }, get_lines(bufnr))
    end
  )

  it(
    "block-only filetype: append-merge works when existing box is on the left (suffix stripped before strategies)",
    function()
      -- Mirror of the previous test but with the existing box on the left
      -- side and selection on the right word.  Append-merge needs the suffix
      -- removed so rtrim can shrink the line below box_disp_start.
      local bufnr = h.make_buf({
        "<!-- ┌────────┐         -->",
        "<!-- │ apples │ oranges -->",
        "<!-- └────────┘         -->",
      }, "markdown")
      api.wrap(sel(BLK, 2, 2, 21, 27), bufnr, { theme = "thin" })
      assert.are.same({
        "<!-- ┌────────┐ ┌─────────┐ -->",
        "<!-- │ apples │ │ oranges │ -->",
        "<!-- └────────┘ └─────────┘ -->",
      }, get_lines(bufnr))
    end
  )

  it(
    "block-only filetype: merge_into_borders strips block suffix too (adjacent box extends)",
    function()
      -- Regression: merge_into_borders' internal strip helper must remove
      -- both the block-comment prefix AND suffix before checking top_preset
      -- on the adjacent rows.  Otherwise the trailing " -->" prevents the
      -- adjacent box from being recognized and merge falls through to insert.
      local bufnr = h.make_buf({
        "<!--        ┌─────────┐ -->",
        "<!-- apples │ oranges │ -->",
        "<!--        └─────────┘ -->",
      }, "markdown")
      api.wrap(sel(BLK, 2, 2, 6, 11), bufnr, { theme = "thin" })
      assert.are.same({
        "<!-- ┌────────┐ ┌─────────┐ -->",
        "<!-- │ apples │ │ oranges │ -->",
        "<!-- └────────┘ └─────────┘ -->",
      }, get_lines(bufnr))
    end
  )

  it("block-only filetype: pads border rows so closing suffix aligns", function()
    -- Regression: when content row has trailing text past the box (suffix
    -- preserved by wrap_lines), border rows must be padded to the same
    -- width so the block-comment closing delim aligns across rows.
    local bufnr = h.make_buf({ "<!-- oranges apple -->" }, "html")
    api.wrap(sel(BLK, 1, 1, 6, 12), bufnr, { theme = "thin" })
    assert.are.same({
      "<!-- ┌─────────┐       -->",
      "<!-- │ oranges │ apple -->",
      "<!-- └─────────┘       -->",
    }, get_lines(bufnr))
  end)

  it(
    "<C-v> mode: inserts fresh border rows when adjacent rows are not box borders",
    function()
      local bufnr = h.make_buf({
        "above",
        "-- ┃ hello ┃ world",
        "below",
      }, "lua")
      api.wrap(sel(BLK, 2, 2, 18, 22), bufnr, "bold")
      -- "above" / "below" are plain text, not box borders → no merge.
      -- Two new rows are inserted around the wrapped row (5 rows total).
      assert.are.equal(5, #get_lines(bufnr))
    end
  )
end)

describe("unwrap", function()
  after_each(h.clean_bufs)

  it("linewise: erases box when selection is inside", function()
    local bufnr = h.make_buf({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    api.unwrap(sel(V, 2, 2), bufnr)
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)

  it("linewise: erases box when entire box is selected", function()
    local bufnr = h.make_buf({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    api.unwrap(sel(V, 1, 3), bufnr)
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)

  it("linewise: erases box when selection overlaps from above", function()
    local bufnr = h.make_buf({
      "before",
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    api.unwrap(sel(V, 1, 3), bufnr)
    assert.are.same({ "before", "hello" }, get_lines(bufnr))
  end)

  it("linewise: no-op when selection is outside any box", function()
    local bufnr = h.make_buf({ "hello", "world" })
    local before = get_lines(bufnr)
    api.unwrap(sel(V, 1, 2), bufnr)
    assert.are.same(before, get_lines(bufnr))
  end)

  it("linewise: no-op when touching border from outside", function()
    local bufnr = h.make_buf({
      "before",
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    local before = get_lines(bufnr)
    api.unwrap(sel(V, 1, 2), bufnr)
    assert.are.same(before, get_lines(bufnr))
  end)

  it("blockwise: erases box when selection covers side chars", function()
    local bufnr = h.make_buf({
      "+-------+",
      "| hello |",
      "+-------+",
    })
    api.unwrap(sel(BLK, 2, 2, 1, 9), bufnr)
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)

  it("block-only filetype (html): unwraps per-line block-wrapped box", function()
    local bufnr = h.make_buf({
      "<!-- ┌───────┐ -->",
      "<!-- │ hello │ -->",
      "<!-- └───────┘ -->",
    }, "html")
    api.unwrap(sel(V, 2, 2), bufnr)
    assert.are.same({ "<!-- hello -->" }, get_lines(bufnr))
  end)
end)

describe("toggle", function()
  after_each(h.clean_bufs)

  it("OUTSIDE: wraps the selection", function()
    local bufnr = h.make_buf({ "hello" })
    toggle(sel(V, 1, 1), bufnr, "thin")
    assert.are.same({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    }, get_lines(bufnr))
  end)

  it("INSIDE: unwraps the box", function()
    local bufnr = h.make_buf({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    toggle(sel(V, 2, 2), bufnr, "thin")
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)

  it("INSIDE on border: unwraps the box", function()
    local bufnr = h.make_buf({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    toggle(sel(V, 1, 1), bufnr, "thin")
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)

  it("OVERLAPPING: unwraps the box", function()
    local bufnr = h.make_buf({
      "before",
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    toggle(sel(V, 1, 3), bufnr, "thin")
    assert.are.same({ "before", "hello" }, get_lines(bufnr))
  end)

  it("OUTSIDE touching border: wraps only the non-border part", function()
    local bufnr = h.make_buf({
      "before",
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    })
    toggle(sel(V, 1, 2), bufnr, "thin")
    assert.are.same({
      "┌────────┐",
      "│ before │",
      "└────────┘",
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    }, get_lines(bufnr))
  end)

  it("double-toggle round-trips back to original", function()
    local input = { "hello", "world" }
    local bufnr = h.make_buf(input)
    local s = sel(V, 1, 2)
    toggle(s, bufnr, "thin")
    toggle(sel(V, 2, 3), bufnr, "thin")
    assert.are.same(input, get_lines(bufnr))
  end)

  it("blockwise OUTSIDE: wraps the column selection", function()
    local bufnr = h.make_buf({ "hello" })
    toggle(sel(BLK, 1, 1, 1, 5), bufnr, "ascii")
    assert.are.same({
      "+-------+",
      "| hello |",
      "+-------+",
    }, get_lines(bufnr))
  end)

  it("blockwise INSIDE: unwraps the box", function()
    local bufnr = h.make_buf({
      "+-------+",
      "| hello |",
      "+-------+",
    })
    toggle(sel(BLK, 2, 2, 1, 9), bufnr, "ascii")
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)

  it("blockwise selection across two adjacent boxes: merges into one", function()
    local bufnr = h.make_buf({
      "┏━━━━━━━┓ ┏━━━━━━━┓",
      "┃ hello ┃ ┃ world ┃",
      "┗━━━━━━━┛ ┗━━━━━━━┛",
    })
    -- selection on line 2 from "h" of "hello" (byte 5) to "d" of "world" (byte 23)
    toggle(sel(BLK, 2, 2, 5, 23), bufnr, "bold")
    assert.are.same({
      "┏━━━━━━━━━━━━━┓",
      "┃ hello world ┃",
      "┗━━━━━━━━━━━━━┛",
    }, get_lines(bufnr))
  end)

  it("blockwise selection inside the box: unwraps", function()
    local bufnr = h.make_buf({
      "+-------+",
      "| hello |",
      "+-------+",
    })
    -- selection covers just "hello" (cols 3-7), inside the box's column range.
    toggle(sel(BLK, 2, 2, 3, 7), bufnr, "ascii")
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)

  it("blockwise selection wider than the box: unwraps in place", function()
    local bufnr = h.make_buf({
      "+-------+   tail",
      "| hello |   tail",
      "+-------+   tail",
    })
    -- Selection (cols 1-15) contains the 9-col box → boundaries align (box ⊆
    -- sel) → unwrap.  The box's footprint shrinks to its content width so the
    -- surrounding text on each row stays aligned.
    toggle(sel(BLK, 2, 2, 1, 15), bufnr, "ascii")
    assert.are.same({
      "        tail",
      "hello   tail",
      "        tail",
    }, get_lines(bufnr))
  end)

  it(
    "V mode: redraws two parallel boxes into a single linewise box around their content",
    function()
      local bufnr = h.make_buf({
        "-- ┏━━━━━━━━┓ ┏━━━━━━━━┓",
        "-- ┃ hello1 ┃ ┃ world1 ┃",
        "-- ┃ hello2 ┃ ┃ world2 ┃",
        "-- ┗━━━━━━━━┛ ┗━━━━━━━━┛",
      }, "lua")
      toggle(sel(V, 2, 3), bufnr, "bold")
      assert.are.same({
        "-- ┏━━━━━━━━━━━━━━━┓",
        "-- ┃ hello1 world1 ┃",
        "-- ┃ hello2 world2 ┃",
        "-- ┗━━━━━━━━━━━━━━━┛",
      }, get_lines(bufnr))
    end
  )

  it("V mode: redraws partial box with prefix text into a full linewise box", function()
    local bufnr = h.make_buf({
      "--        ┏━━━━━━━━┓",
      "-- hello3 ┃ world3 ┃",
      "--        ┗━━━━━━━━┛",
    }, "lua")
    toggle(sel(V, 2, 2), bufnr, "bold")
    assert.are.same({
      "-- ┏━━━━━━━━━━━━━━━┓",
      "-- ┃ hello3 world3 ┃",
      "-- ┗━━━━━━━━━━━━━━━┛",
    }, get_lines(bufnr))
  end)

  it("V mode: redraws partial box with suffix text into a full linewise box", function()
    local bufnr = h.make_buf({
      "-- ┏━━━━━━━━┓",
      "-- ┃ hello4 ┃ world4",
      "-- ┗━━━━━━━━┛",
    }, "lua")
    toggle(sel(V, 2, 2), bufnr, "bold")
    assert.are.same({
      "-- ┏━━━━━━━━━━━━━━━┓",
      "-- ┃ hello4 world4 ┃",
      "-- ┗━━━━━━━━━━━━━━━┛",
    }, get_lines(bufnr))
  end)

  it("toggle on box wrapping a single-space content preserves the space", function()
    -- Regression: unwrapping a box whose content is whitespace-only used to
    -- trim everything to "" and lose the space, jamming the surrounding text
    -- together.  Now whitespace-only content is preserved as-is.
    local bufnr = h.make_buf({
      "--        ┌───┐",
      "-- box box│   │hello",
      "--        └───┘",
    }, "lua")
    toggle(sel(BLK, 2, 2, 14, 14), bufnr, "thin")
    assert.are.same({ "-- box box hello" }, get_lines(bufnr))
  end)

  it(
    "blockwise sel spanning multiple boxes wraps only the combined box contents",
    function()
      -- Sel spans box1 ("he") + inter-box junk + box2 ("llo").  After erase
      -- the line is "-- box box hello" but only "hello" came from the boxes
      -- the sel touched.  Wrap should target "hello" only (not "box box").
      local bufnr = h.make_buf({
        "--         ┌────┐┌─────┐",
        "-- box box │ he ││ llo │",
        "--         └────┘└─────┘",
      }, "lua")
      toggle(sel(BLK, 2, 2, 16, 28), bufnr, "thin")
      assert.are.same({
        "--         ┌───────┐",
        "-- box box │ hello │",
        "--         └───────┘",
      }, get_lines(bufnr))
    end
  )

  it(
    "blockwise selection across two adjacent boxes inside a lua comment: merges into one",
    function()
      local bufnr = h.make_buf({
        "-- ┏━━━━━━━┓ ┏━━━━━━━┓",
        "-- ┃ hello ┃ ┃ world ┃",
        "-- ┗━━━━━━━┛ ┗━━━━━━━┛",
      }, "lua")
      -- selection on line 2: "h" of "hello" at byte 8, "d" of "world" at byte 26
      toggle(sel(BLK, 2, 2, 8, 26), bufnr, "bold")
      assert.are.same({
        "-- ┏━━━━━━━━━━━━━┓",
        "-- ┃ hello world ┃",
        "-- ┗━━━━━━━━━━━━━┛",
      }, get_lines(bufnr))
    end
  )

  it("multi-row blockwise selection inside a multi-content-row box: unwraps", function()
    local bufnr = h.make_buf({
      "+-------+",
      "| hello |",
      "| world |",
      "+-------+",
    })
    -- selection covers content rows 2-3, cols 3-7 (sel ⊆ box) → boundary
    -- align → unwrap.
    toggle(sel(BLK, 2, 3, 3, 7), bufnr, "ascii")
    assert.are.same({ "hello", "world" }, get_lines(bufnr))
  end)

  it("multi-row blockwise selection wider than the box: unwraps in place", function()
    local bufnr = h.make_buf({
      "+-------+   tail",
      "| hello |   tail",
      "| world |   tail",
      "+-------+   tail",
    })
    -- sel cols 1-15 contains the 9-col box across content rows → box ⊆ sel
    -- → boundary align → unwrap.
    toggle(sel(BLK, 2, 3, 1, 15), bufnr, "ascii")
    assert.are.same({
      "        tail",
      "hello   tail",
      "world   tail",
      "        tail",
    }, get_lines(bufnr))
  end)

  it("multi-row blockwise: merges borders into adjacent multi-row box borders", function()
    local bufnr = h.make_buf({
      "┏━━━━━━━┓",
      "┃ hello ┃ world",
      "┃ hello ┃ world",
      "┃ hello ┃ world",
      "┃ hello ┃ world",
      "┗━━━━━━━┛",
    })
    -- selection covers "world" across rows 2-5; cols outside the existing
    -- box's col range, so find_boxes returns nothing → plain wrap path.
    -- merge_into_borders extends the existing top/bottom borders.
    toggle(sel(BLK, 2, 5, 15, 19), bufnr, "bold")
    assert.are.same({
      "┏━━━━━━━┓ ┏━━━━━━━┓",
      "┃ hello ┃ ┃ world ┃",
      "┃ hello ┃ ┃ world ┃",
      "┃ hello ┃ ┃ world ┃",
      "┃ hello ┃ ┃ world ┃",
      "┗━━━━━━━┛ ┗━━━━━━━┛",
    }, get_lines(bufnr))
  end)

  it(
    "multi-row blockwise: merges borders into adjacent multi-row box borders inside a lua comment",
    function()
      local bufnr = h.make_buf({
        "-- ┏━━━━━━━┓",
        "-- ┃ hello ┃ world",
        "-- ┃ hello ┃ world",
        "-- ┃ hello ┃ world",
        "-- ┃ hello ┃ world",
        "-- ┗━━━━━━━┛",
      }, "lua")
      -- selection covers "world" across rows 2-5: byte col 18=w, 22=d
      toggle(sel(BLK, 2, 5, 18, 22), bufnr, "bold")
      assert.are.same({
        "-- ┏━━━━━━━┓ ┏━━━━━━━┓",
        "-- ┃ hello ┃ ┃ world ┃",
        "-- ┃ hello ┃ ┃ world ┃",
        "-- ┃ hello ┃ ┃ world ┃",
        "-- ┃ hello ┃ ┃ world ┃",
        "-- ┗━━━━━━━┛ ┗━━━━━━━┛",
      }, get_lines(bufnr))
    end
  )

  it(
    "multi-row blockwise: above/below borders with no leading padding — append-merge the new box",
    function()
      local bufnr = h.make_buf({
        "-- hello1 world1",
        "-- hello2 world2",
        "-- ┏━━━━━━━━┓",
        "-- ┃ hello3 ┃ world3",
        "-- ┃ hello4 ┃ world4",
        "-- ┗━━━━━━━━┛",
        "-- hello5 world5",
        "-- hello6 world6",
      }, "lua")
      -- selection rows 4-5 byte cols 19-24 (covering "world3"/"world4").
      -- Above (row 3) is a top border at cols 4-13; below (row 6) is a
      -- bottom border at cols 4-13.  The byte cols of the sel (19-24) on
      -- the borders land on UTF-8 boundaries inside the ━ run, but the
      -- structure differs from the content line — byte-replace must be
      -- skipped (different display layout) and append-merge used instead.
      toggle(sel(BLK, 4, 5, 19, 24), bufnr, "bold")
      assert.are.same({
        "-- hello1 world1",
        "-- hello2 world2",
        "-- ┏━━━━━━━━┓ ┏━━━━━━━━┓",
        "-- ┃ hello3 ┃ ┃ world3 ┃",
        "-- ┃ hello4 ┃ ┃ world4 ┃",
        "-- ┗━━━━━━━━┛ ┗━━━━━━━━┛",
        "-- hello5 world5",
        "-- hello6 world6",
      }, get_lines(bufnr))
    end
  )

  it(
    "multi-row blockwise on plain text: pure insert (no merging into adjacent rows)",
    function()
      local bufnr = h.make_buf({
        "-- hello1 world1",
        "-- hello2 world2",
        "-- hello3 world3",
        "-- hello4 world4",
        "-- hello5 world5",
        "-- hello6 world6",
        "-- hello7 world7",
        "-- hello8 world8",
        "-- hello9 world9",
      }, "lua")
      -- sel rows 4-5 byte cols 4-9 (covering "hello4"/"hello5").
      -- Adjacent rows (3 and 6) are plain text, not borders → pure insert.
      toggle(sel(BLK, 4, 5, 4, 9), bufnr, "bold")
      assert.are.same({
        "-- hello1 world1",
        "-- hello2 world2",
        "-- hello3 world3",
        "-- ┏━━━━━━━━┓",
        "-- ┃ hello4 ┃ world4",
        "-- ┃ hello5 ┃ world5",
        "-- ┗━━━━━━━━┛",
        "-- hello6 world6",
        "-- hello7 world7",
        "-- hello8 world8",
        "-- hello9 world9",
      }, get_lines(bufnr))
    end
  )

  it(
    "single-row blockwise selection inside one of several content rows: erases box, wraps only that row",
    function()
      local bufnr = h.make_buf({
        "┏━━━━━━━┓",
        "┃ hello ┃ world",
        "┃ hello ┃ world",
        "┃ hello ┃ world",
        "┃ hello ┃ world",
        "┗━━━━━━━┛",
      })
      -- selection on row 4 only, byte cols 5-19 cover "hello ┃ world".
      -- partial col overlap → erase box → wrap only the (mapped) row 4.
      toggle(sel(BLK, 4, 4, 5, 19), bufnr, "bold")
      assert.are.same({
        "hello world",
        "hello world",
        "┏━━━━━━━━━━━━━┓",
        "┃ hello world ┃",
        "┗━━━━━━━━━━━━━┛",
        "hello world",
      }, get_lines(bufnr))
    end
  )

  it(
    "multi-row blockwise selection spanning two vertically separated boxes: merges into one",
    function()
      local bufnr = h.make_buf({
        "+-------+",
        "| hello |",
        "+-------+",
        "+-------+",
        "| world |",
        "+-------+",
      })
      -- sel rows 1-6, cols 3-7 covers both boxes' content cols → 2 boxes
      -- detected → wrap (merge).
      toggle(sel(BLK, 1, 6, 3, 7), bufnr, "ascii")
      assert.are.same({
        "+-------+",
        "| hello |",
        "| world |",
        "+-------+",
      }, get_lines(bufnr))
    end
  )

  it("html: V toggle round-trips commented input through wrap → unwrap", function()
    local bufnr = h.make_buf({ "<!-- hello -->" }, "html")
    -- Wrap detects + preserves the existing block comment.
    api.wrap(sel(V, 1, 1), bufnr, { theme = "thin" })
    assert.are.same({
      "<!-- ┌───────┐ -->",
      "<!-- │ hello │ -->",
      "<!-- └───────┘ -->",
    }, get_lines(bufnr))
    -- Unwrap restores the original commented content.
    api.unwrap(sel(V, 2, 2), bufnr)
    assert.are.same({ "<!-- hello -->" }, get_lines(bufnr))
  end)

  it("html: V toggle round-trips PLAIN input through wrap → unwrap", function()
    local bufnr = h.make_buf({ "hello" }, "html")
    api.wrap(sel(V, 1, 1), bufnr, { theme = "thin" })
    assert.are.same({
      "┌───────┐",
      "│ hello │",
      "└───────┘",
    }, get_lines(bufnr))
    api.unwrap(sel(V, 2, 2), bufnr)
    assert.are.same({ "hello" }, get_lines(bufnr))
  end)
end)
