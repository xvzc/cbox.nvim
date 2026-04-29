-- Auto-load entry point for Neovim's plugin discovery.  Triggers the
-- one-shot setup at the bottom of `lua/cbox/init.lua` (guarded by
-- `vim.g.cbox_loaded`) so users get sensible defaults without having to
-- call `require("cbox").setup()` themselves.
if vim.g.cbox_loaded then
  return
end
require("cbox")
