local command = require('java-copy-descriptor.command')
local config = require('java-copy-descriptor.config')

local M = {}

---Configure the plugin.
---@param opts? table
---@return table
function M.setup(opts)
  return config.setup(opts)
end

---Copy the JVM descriptor of the Java method or constructor under the cursor.
function M.copy()
  command.copy()
end

---Resolve the descriptor under the cursor without writing to the clipboard.
---@param callback fun(err: string?, descriptor: string?, metadata: table?)
function M.descriptor_at_cursor(callback)
  command.descriptor_at_cursor(callback)
end

return M
