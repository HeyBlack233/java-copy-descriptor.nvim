local treesitter = require('java-copy-descriptor.treesitter')

local M = {}

---Build a JVM method descriptor from a declaration node.
---@param decl vim.treesitter.Node
---@param text string
---@param resolve_type fun(node: vim.treesitter.Node, varargs: boolean): string?, string?
---@param meta { kind: 'method'|'constructor', enum: boolean?, inner: boolean?, enclosing_binary: string? }
---@return string? descriptor
---@return string? error
function M.build(decl, text, resolve_type, meta)
  local params = treesitter.parameter_nodes(decl, text)
  local param_descriptors = {}
  local prefix = {}

  if meta.kind == 'constructor' then
    if meta.enum then
      local already_prefixed = #params >= 2
        and treesitter.node_text(params[1].node, text) == 'String'
        and treesitter.node_text(params[2].node, text) == 'int'
      if not already_prefixed then
        prefix[#prefix + 1] = 'Ljava/lang/String;'
        prefix[#prefix + 1] = 'I'
      end
    end
    if meta.inner and meta.enclosing_binary then
      local enclosing_simple = meta.enclosing_binary:match('([^/]+)$') or ''
      enclosing_simple = enclosing_simple:gsub('%$.*$', '')
      local already_prefixed = enclosing_simple ~= ''
        and params[1]
        and treesitter.node_text(params[1].node, text):match(enclosing_simple) ~= nil
      if not already_prefixed then
        prefix[#prefix + 1] = 'L' .. meta.enclosing_binary .. ';'
      end
    end
  end

  for _, descriptor in ipairs(prefix) do
    param_descriptors[#param_descriptors + 1] = descriptor
  end

  for _, param in ipairs(params) do
    local descriptor, err = resolve_type(param.node, param.varargs)
    if not descriptor then
      return nil, err or 'Could not resolve a parameter type'
    end
    param_descriptors[#param_descriptors + 1] = descriptor
  end

  local return_descriptor = 'V'
  if meta.kind ~= 'constructor' then
    local return_type = treesitter.return_type(decl, text)
    if return_type then
      local descriptor, err = resolve_type(return_type, false)
      if not descriptor then
        return nil, err or 'Could not resolve the return type'
      end
      return_descriptor = descriptor
    end
  end

  return '(' .. table.concat(param_descriptors) .. ')' .. return_descriptor
end

---@param text string
---@return integer
function M.arity(decl, text)
  return #treesitter.parameter_nodes(decl, text)
end

---@param meta { enum: boolean?, inner: boolean?, enclosing_binary: string? }
---@return string
function M.default_constructor(meta)
  local params = {}
  if meta.enum then
    params[#params + 1] = 'Ljava/lang/String;'
    params[#params + 1] = 'I'
  end
  if meta.inner and meta.enclosing_binary then
    params[#params + 1] = 'L' .. meta.enclosing_binary .. ';'
  end
  return '(' .. table.concat(params) .. ')V'
end

return M
