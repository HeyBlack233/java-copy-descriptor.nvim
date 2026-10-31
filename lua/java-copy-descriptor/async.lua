local M = {}

local error_handlers = setmetatable({}, { __mode = 'k' })

--- Run an async function in a coroutine and route uncaught errors to a callback.
--- The function may yield through `java-copy-descriptor.lsp.request`.
---@param fn fun()
---@param on_error fun(err: string)
function M.run(fn, on_error)
  local co
  co = coroutine.create(function()
    local ok, err = xpcall(fn, debug.traceback)
    error_handlers[co] = nil
    if not ok then
      on_error(err)
    end
  end)
  error_handlers[co] = on_error
  local ok, err = coroutine.resume(co)
  if not ok then
    error_handlers[co] = nil
    on_error(err)
  end
end

--- Resume a suspended coroutine and send failures to its error handler.
---@param co thread
---@param ...
function M.resume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    local handler = error_handlers[co]
    error_handlers[co] = nil
    if handler then
      handler(err)
    end
  end
end

return M
