local lsp = require('java-copy-descriptor.lsp')
local source = require('java-copy-descriptor.source')

local M = {}

local function urldecode(value)
  return (value:gsub('%%(%x%x)', function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

local function first_content(value)
  if type(value) == 'string' then
    return value
  end
  if type(value) ~= 'table' then
    return nil
  end
  if value.value then
    return value.value
  end
  if value.kind == 'markdown' or value.kind == 'plaintext' then
    return value.value
  end
  for _, item in ipairs(value) do
    local found = first_content(item)
    if found then
      return found
    end
  end
  return nil
end

local function hover_text(result)
  if not result or not result.contents then
    return nil
  end
  local value = first_content(result.contents)
  if not value then
    return nil
  end
  value = vim.trim(value)
  value = value:match('^[^\n]*') or value
  return value
end

local function normalize_canonical(value)
  if not value then
    return nil
  end
  value = value:gsub('%s+$', '')
  local open_paren = value:find('(', 1, true)
  if open_paren then
    value = value:sub(1, open_paren - 1)
    local segments = vim.split(value, '.', { plain = true })
    if #segments >= 2 and segments[#segments] == segments[#segments - 1] then
      table.remove(segments)
      value = table.concat(segments, '.')
    end
  end
  value = value:gsub('^class%s+', '')
  value = value:gsub('^interface%s+', '')
  value = value:gsub('^enum%s+', '')
  value = value:gsub('^record%s+', '')
  value = value:gsub('^@interface%s+', '')
  local generic = value:find('<', 1, true)
  if generic then
    value = value:sub(1, generic - 1)
  end
  return vim.trim(value)
end

--- Request the first line of a Java hover.
---@param client vim.lsp.Client
---@param uri string
---@param position { line: integer, character: integer }
---@return string?
function M.hover_value(client, uri, position)
  local result, err = lsp.request(client, 'textDocument/hover', lsp.position_params(uri, position))
  if err then
    return nil
  end
  return hover_text(result)
end

--- Request definition locations.
---@param client vim.lsp.Client
---@param uri string
---@param position { line: integer, character: integer }
---@return table?
function M.definition(client, uri, position)
  local result, err = lsp.request(client, 'textDocument/definition', lsp.position_params(uri, position))
  if err or type(result) ~= 'table' then
    return nil
  end
  if result.uri then
    return result
  end
  for _, location in ipairs(result) do
    if location.uri then
      return location
    end
  end
  return nil
end

---@param uri string
---@return string?
function M.binary_from_jdt_uri(uri)
  local decoded = urldecode(uri)
  local tail = decoded:match('<([^<]+)$') or decoded
  local package, class = tail:match('([%w_.]+)%(([%w_$]+)%.class')
  if not package or not class then
    return nil
  end
  return package:gsub('%.', '/') .. '/' .. class
end

---@param canonical string
---@param package string
---@return string
function M.canonical_to_binary(canonical, package)
  package = package or ''
  if package ~= '' and canonical:sub(1, #package + 1) == package .. '.' then
    local remainder = canonical:sub(#package + 2)
    return package:gsub('%.', '/') .. '/' .. remainder:gsub('%.', '$')
  end
  return canonical:gsub('%.', '$')
end

--- Resolve a class type to its canonical and binary names.
---@param ctx table
---@param uri string
---@param position { line: integer, character: integer }
---@return { canonical: string, binary: string, definition_uri: string }?
function M.class_info(ctx, uri, position)
  local key = string.format('%s|%d|%d', uri, position.line, position.character)
  local cached = ctx.type_cache[key]
  if cached then
    return cached
  end

  local canonical = normalize_canonical(M.hover_value(ctx.client, uri, position))
  if not canonical or canonical == '' then
    return nil
  end
  local location = M.definition(ctx.client, uri, position)
  if not location then
    return nil
  end

  local binary
  if location.uri:match('^jdt://') then
    binary = M.binary_from_jdt_uri(location.uri)
  elseif location.uri:match('^file://') then
    local text = source.read(ctx, location.uri)
    local package = source.package_name(text)
    binary = M.canonical_to_binary(canonical, package)
  end
  if not binary then
    return nil
  end

  local info = {
    canonical = canonical,
    binary = binary,
    definition_uri = location.uri,
  }
  ctx.type_cache[key] = info
  return info
end

--- Resolve the binary name of an owner class from an item URI and canonical name.
---@param ctx table
---@param uri string
---@param canonical string
---@return string?
function M.owner_binary(ctx, uri, canonical)
  if not canonical then
    return nil
  end
  if uri:match('^jdt://') then
    return M.binary_from_jdt_uri(uri)
  end
  if uri:match('^file://') then
    local text = source.read(ctx, uri)
    return M.canonical_to_binary(canonical, source.package_name(text))
  end
  return nil
 end

--- Parse a hover value that describes a type variable.
---@param value string
---@return { name: string, bound: string? }?
function M.parse_type_variable(value)
  if not value then
    return nil
  end
  local name, bound = value:match('^([%w_$]+)%s+extends%s+([%w_.$<>?]+)')
  if name then
    return { name = name, bound = bound }
  end
  local single = value:match('^([%w_$]+)$')
  if single then
    return { name = single, bound = nil }
  end
  return nil
end

return M
