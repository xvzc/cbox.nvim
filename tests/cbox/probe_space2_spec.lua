local h = require("helpers")
local cbox = require("cbox")

local function get_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function dump(bufnr, label)
  print(label .. ":")
  for i, l in ipairs(get_lines(bufnr)) do
    print(string.format("  [%d] %q", i, l))
  end
end

describe("box-prefix probe", function()
  after_each(h.clean_bufs)
  it("box at disp 7-11 with 3 inner spaces", function()
    local bufnr = h.make_buf({
      "--    ┌───┐",
      "-- box│   │ box hello",
      "--    └───┘",
    }, "lua")
    vim.api.nvim_set_current_buf(bufnr)
    -- Cursor on middle space inside box. byte 11 = middle space.
    vim.api.nvim_win_set_cursor(0, { 2, 10 })
    cbox.toggle()
    dump(bufnr, "5-wide box, cursor middle")
  end)

  it("box at disp 7-9 with 1 inner space", function()
    local bufnr = h.make_buf({
      "--    ┌─┐",
      "-- box│ │ box hello",
      "--    └─┘",
    }, "lua")
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { 2, 9 })
    cbox.toggle()
    dump(bufnr, "3-wide box, cursor inner space")
  end)
end)
