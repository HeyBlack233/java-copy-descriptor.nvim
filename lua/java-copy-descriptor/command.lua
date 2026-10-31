local async = require('java-copy-descriptor.async')
local clipboard = require('java-copy-descriptor.clipboard')
local config = require('java-copy-descriptor.config')
local lsp = require('java-copy-descriptor.lsp')
local target = require('java-copy-descriptor.target')
local treesitter = require('java-copy-descriptor.treesitter')

local M = {}

local function build_context()
  if not treesitter.available() then
    return nil, 'The tree-sitter-java parser is not installed. Install it with :TSInstall java.'
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local options = config.get()
  local client = lsp.get_client(bufnr, options.client_name)
  if not client then
    return nil, string.format('No %s LSP client is attached to this buffer', options.client_name)
  end
  if vim.bo[bufnr].filetype ~= 'java' then
    return nil, 'JavaCopyDescriptor only works in Java buffers'
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ''
  local character = treesitter.byte_to_utf16(line, cursor[2])
  return {
    bufnr = bufnr,
    client = client,
    uri = vim.uri_from_bufnr(bufnr),
    position = { line = cursor[1] - 1, character = character },
    cursor_byte = { line = cursor[1] - 1, character = cursor[2] },
    text_cache = {},
    symbol_cache = {},
    type_cache = {},
  }
end

local function first_line(value)
  return (tostring(value):match('^[^\n]*') or tostring(value))
end

local function notify_error(err)
  if config.get().notify then
    vim.notify('JavaCopyDescriptor: ' .. first_line(err), vim.log.levels.ERROR)
  end
end

local function notify_success(descriptor_text, metadata)
  local options = config.get()
  if not options.notify then
    return
  end
  local owner = metadata and metadata.owner
  local name = metadata and metadata.name
  local subject = descriptor_text
  if owner and name then
    subject = string.format('%s#%s %s', owner, name, descriptor_text)
  elseif owner then
    subject = string.format('%s %s', owner, descriptor_text)
  end
  vim.notify('JavaCopyDescriptor: copied ' .. subject, vim.log.levels.INFO)
end

---Run the descriptor request asynchronously.
---@param callback fun(err: string?, descriptor: string?, metadata: table?)
function M.descriptor_at_cursor(callback)
  local ctx, err = build_context()
  if not ctx then
    callback(err)
    return
  end

  local called = false
  local function finish(error_message, value, metadata)
    if called then
      return
    end
    called = true
    callback(error_message, value, metadata)
  end

  async.run(function()
    local value, metadata = target.descriptor_at_cursor(ctx)
    if not value then
      finish('Could not build a JVM descriptor for the cursor')
      return
    end
    finish(nil, value, metadata)
  end, function(error_message)
    finish(tostring(error_message))
  end)
end

---Copy the JVM descriptor under the cursor to the configured register.
function M.copy()
  M.descriptor_at_cursor(function(err, descriptor_text, metadata)
    if err then
      notify_error(err)
      return
    end
    local options = config.get()
    local ok, write_err = clipboard.write(descriptor_text, options.clipboard_register)
    if not ok then
      notify_error(write_err)
      return
    end
    notify_success(descriptor_text, metadata)
  end)
end

return M
