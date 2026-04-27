vim.cmd([[set runtimepath+=.]])

vim.opt.swapfile = false
vim.opt.undofile = false

local cwd = vim.fn.getcwd()
local deps_dir = cwd .. "/.deps/start/"
vim.opt.runtimepath:append(deps_dir .. "plenary.nvim")

-- Make tests/ available as a Lua package root
package.path = cwd .. "/tests/?.lua;" .. package.path

require("plenary.busted")
