# Security

Never hardcode absolute paths containing usernames or system-specific directories.

```lua
-- incorrect
local path = "/Users/username/folder/cbox.nvim"

-- correct
local path = vim.fn.stdpath("data") .. "/cbox"
```

```json
// incorrect
{ "command": "cd /Users/username/folder/cbox.nvim && make test" }

// correct
{ "command": "make test" }
```
