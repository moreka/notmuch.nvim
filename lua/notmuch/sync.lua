local s = {}
local v = vim.api

local config = require("notmuch.config")

s.sync_maildir = function()
  local sync_cmd = config.options.maildir_sync_cmd .. " ; notmuch new"
  print("Syncing and reindexing your Maildir...")
  v.nvim_command("!" .. sync_cmd)
end

return s
