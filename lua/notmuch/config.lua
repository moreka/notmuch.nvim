local C = {}
local util = require("notmuch.util")

---Loads default notmuch config via cli
---
---@return { database_path: string, user_name: string, user_primary_email: string, exclude_tags: string[] }?
local load_config_from_notmuch = function()
  local cfg = util.shell_sync({ "notmuch", "config", "list" })
  if cfg == nil then
    util.error("cannot read config from notmuch")
    return nil
  end
  --HACK: make the output of notmuch config into a lua table
  cfg = cfg:gsub("=", '"]="')
  cfg = cfg:gsub("\n", '",\n["')
  cfg = cfg:sub(0, -3)
  cfg = '{\n["' .. cfg .. "}"
  local config = vim.fn.luaeval(cfg)

  return {
    database_path = config["database.path"],
    user_name = config["user.name"],
    user_primary_email = config["user.primary_email"],
    exclude_tags = vim.split(config["search.exclude_tags"], ";"),
  }
end

---@class NotmuchKeymap
---@field sendmail string

---@class NotmuchConfig
---@field notmuch_db_path string?
---@field from string?
---@field exclude_tags string[]?
---@field maildir_sync_cmd string?
---@field open_cmd string?
---@field keymaps NotmuchKeymap[]?

---Define default configuration of `notmuch.nvim`
---
---This function defines the default configuration options of the plugin
---including keymaps. The defaults can be overridden with options `opts` passed
---by the user in the `setup()` function.
---@return NotmuchConfig?
C.defaults = function()
  local nm_config = load_config_from_notmuch()
  local name = nm_config and nm_config.user_name or nil
  local email = nm_config and nm_config.user_primary_email or nil
  local db_path = nm_config and nm_config.database_path or nil
  local excluded_tags = nm_config and nm_config.exclude_tags or {}

  if not db_path then
    util.error("notmuch.nvim: database.path not configured.\n" .. "Please run: notmuch setup")
    return nil
  end

  if not name or not email then
    util.error("notmuch.nvim: user.name or user.primary_email not configured.\n" .. "Please run: notmuch setup")
    return nil
  end

  return {
    notmuch_db_path = db_path,
    from = name .. " <" .. email .. ">",
    exclude_tags = excluded_tags,
    maildir_sync_cmd = "mbsync -a",
    open_cmd = "xdg-open",
    keymaps = { -- This should capture all notmuch.nvim related keymappings
      sendmail = "<C-c><C-c>",
    },
  }
end

return C
