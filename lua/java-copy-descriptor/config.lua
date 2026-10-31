local M = {}

M.defaults = {
  client_name = 'jdtls',
  clipboard_register = '+',
  notify = true,
}

M.options = vim.deepcopy(M.defaults)

--- Configure the plugin.
---@param opts? table
---@return table
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', M.defaults, opts or {})
  return M.options
end

---@return table
function M.get()
  return M.options
end

return M
