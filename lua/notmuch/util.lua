local u = {}
local v = vim.api

u.file_exists = function(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  else
    return false
  end
end

---Convert HTML content to plain text using w3m
local function html_to_text(html_content)
  local tmpfile = vim.fn.tempname() .. ".html"
  local f = io.open(tmpfile, "w")
  if not f then return html_content end

  f:write(html_content)
  f:close()

  local output = u.shell_sync({ "w3m", "-dump", "-T", "text/html", "-cols", "10000", tmpfile })
  os.remove(tmpfile)
  return output
end

local function get_data_for_msg_part(msgid, part)
  return u.shell_sync({ "notmuch", "show", ("--part=%d"):format(part), "id:" .. msgid })
end

---Process a single part (body content, attachments, etc.)
local function process_part(msgid, part, indent)
  local lines = {}
  local content_type = part["content-type"] or ""

  if (content_type == "multipart/mixed" or content_type == "multipart/related") and part.content then
    for _, inner_part in ipairs(part.content) do
      local inner_lines = process_part(msgid, inner_part, indent)
      vim.list_extend(lines, inner_lines)
    end
  elseif content_type == "multipart/alternative" and part.content then
    --TODO: for now just show the text/plain part
    for _, inner_part in ipairs(part.content) do
      if inner_part["content-type"] == "text/plain" then
        local inner_lines = process_part(msgid, inner_part, indent)
        vim.list_extend(lines, inner_lines)
        break
      end
    end
  elseif content_type == "text/plain" and part.content then
    for _, line in ipairs(vim.split(part.content, "\n")) do
      table.insert(lines, indent .. line)
    end
  elseif content_type == "text/html" then
    local data = get_data_for_msg_part(msgid, part.id)
    local html = html_to_text(data)
    for _, line in ipairs(vim.split(html, "\n")) do
      table.insert(lines, indent .. line)
    end
  else
    table.insert(lines, indent .. ("[part #%d: %s]"):format(part.id, content_type))
  end

  -- -- Handle multipart - recurse into sub-parts
  -- if part.content then
  --   for _, subpart in ipairs(part.content) do
  --     local sublines = process_part(subpart, indent)
  --     for _, line in ipairs(sublines) do
  --       table.insert(lines, line)
  --     end
  --   end
  --   return lines
  -- end
  --
  -- -- Handle text content
  -- if part.content then
  --   local content = part.content
  --
  --   -- Convert HTML to plain text
  --   if string.match(content_type, 'text/html') then
  --     content = html_to_text(content)
  --   end
  --
  --   -- Add content lines with indentation
  --   for line in content:gmatch('[^\n]+') do
  --     table.insert(lines, indent .. line)
  --   end
  -- end
  --
  -- -- Handle attachments (optional: show filename)
  -- if part.filename then
  --   table.insert(lines, indent .. '[Attachment: ' .. part.filename .. ']')
  -- end

  return lines
end

---Format headers for display
local function format_headers(headers, indent)
  local lines = {}
  local header_order = { "Subject", "From", "To", "Cc", "Bcc", "Date" }

  -- Add headers in preferred order
  for _, key in ipairs(header_order) do
    if headers[key] then table.insert(lines, indent .. key .. ": " .. headers[key]) end
  end

  -- Add any remaining headers
  for key, value in pairs(headers) do
    local found = false
    for _, ordered_key in ipairs(header_order) do
      if key == ordered_key then
        found = true
        break
      end
    end
    if not found then table.insert(lines, indent .. key .. ": " .. value) end
  end

  return lines
end

---Process a single message
local function process_message(msg, depth)
  local lines = {}
  local indent = string.rep("  ", depth)
  local msg_id = msg.id

  local fold_text = indent
  if msg.headers then
    fold_text = fold_text .. msg.headers.From .. " "
  end
  if msg.tags then
    fold_text = fold_text .. "(" .. table.concat(msg.tags, ",") .. ") "
  end
  vim.list_extend(lines, { fold_text .. "{{{", "" })

  if msg.headers then
    local header_lines = format_headers(msg.headers, indent)
    for _, line in ipairs(header_lines) do
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end

  if msg.body then
    for _, part in ipairs(msg.body) do
      local part_lines = process_part(msg_id, part, indent)
      for _, line in ipairs(part_lines) do
        table.insert(lines, line)
      end
    end
  end

  table.insert(lines, "}}}")
  return lines
end

---@param buf integer
---@param thread_json string
u.process_msgs_in_thread = function(buf, thread_json)
  local lines = {}

  -- Parse JSON
  local ok, data = pcall(vim.json.decode, thread_json)
  if not ok then
    vim.notify("Failed to parse notmuch JSON output", vim.log.levels.ERROR)
    return
  end

  -- Handle both single message and thread array formats
  local messages = data
  if type(data) ~= "table" then
    vim.notify("Invalid JSON format", vim.log.levels.ERROR)
    return
  end

  -- If data is wrapped in array, unwrap it
  if #data > 0 and data[1] then messages = data[1] end

  local traverse_message
  traverse_message = function(msg, depth)
    depth = depth or 0
    if msg[1] and msg[1][1] then
      local m = msg[1][1]
      local rest = msg[1][2]
      local msg_lines = process_message(m, depth)
      vim.list_extend(lines, msg_lines)
      if rest then traverse_message(rest, depth) end
    end
  end

  -- Start processing
  if #messages > 0 then
    traverse_message(messages, 0)
  else
    u.error("not implemented")
  end
  --   -- Single message, not a thread
  --   local msg_lines = process_message(messages, 0)
  --   for _, line in ipairs(msg_lines) do
  --     table.insert(lines, line)
  --   end
  -- end

  -- Set buffer contents in one operation
  v.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

---Runs a shell command synchronously and returns the stdout
---
---@param cmd string[]
---@return string?
u.shell_sync = function(cmd)
  local obj = vim.system(cmd, { text = true }):wait()
  if obj.code ~= 0 then return nil end
  return obj.stdout
end

---Notify with error severity
---
---@param msg string
u.error = function(msg) vim.notify(msg, vim.log.levels.ERROR) end

return u
