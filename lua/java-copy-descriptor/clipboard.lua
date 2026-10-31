local M = {}

---Write text to a Neovim clipboard register and verify the result.
---@param text string
---@param register string
---@return boolean ok
---@return string? error
function M.write(text, register)
  local ok, err = pcall(vim.fn.setreg, register, text)
  if not ok then
    return false, string.format('Could not write to register %s: %s', register, tostring(err))
  end
  if vim.fn.getreg(register) ~= text then
    return false, string.format('Register %s is not writable; configure a clipboard provider', register)
  end
  return true
end

return M
