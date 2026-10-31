local async = require('java-copy-descriptor.async')

local M = {}

--- Return the jdtls client attached to the buffer.
---@param bufnr integer
---@param client_name string
---@return vim.lsp.Client?
function M.get_client(bufnr, client_name)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = client_name })
  if #clients == 0 then
    clients = vim.lsp.get_clients({ name = client_name })
  end
  if #clients > 1 then
    for _, client in ipairs(clients) do
      if client.attached_buffers and client.attached_buffers[bufnr] then
        return client
      end
    end
  end
  return clients[1]
end

--- Send a request and suspend the current coroutine until the response arrives.
--- @param client vim.lsp.Client
--- @param method string
--- @param params table
--- @param bufnr? integer
--- @return any result
--- @return table? error
function M.request(client, method, params, bufnr)
  local co = coroutine.running()
  if not co then
    error('java-copy-descriptor.lsp.request must run in a coroutine')
  end

  local response = nil
  client:request(method, params, function(err, result)
    response = { err = err, result = result }
    if coroutine.status(co) == 'suspended' then
      async.resume(co)
    end
  end, bufnr)

  while response == nil do
    coroutine.yield()
  end

  if response.err then
    return nil, response.err
  end
  return response.result
end

--- Execute a workspace command supported by jdtls.
--- @param client vim.lsp.Client
--- @param command string
--- @param arguments any[]
--- @param bufnr? integer
--- @return any result
--- @return table? error
function M.execute_command(client, command, arguments, bufnr)
  return M.request(client, 'workspace/executeCommand', {
    command = command,
    arguments = arguments,
  }, bufnr)
end

--- Create an LSP TextDocumentPositionParams table.
--- @param uri string
--- @param position { line: integer, character: integer }
--- @return table
function M.position_params(uri, position)
  return {
    textDocument = { uri = uri },
    position = position,
  }
end

return M
