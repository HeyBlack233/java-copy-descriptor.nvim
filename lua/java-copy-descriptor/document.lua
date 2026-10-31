local M = {}

local TYPE_KINDS = {
  [5] = true, -- Class
  [10] = true, -- Enum
  [11] = true, -- Interface
  [23] = true, -- Struct
}

local function normalize_symbols(result)
  if type(result) ~= 'table' then
    return {}
  end
  return result
end

--- Build fully-qualified paths for all class-like document symbols.
---@param symbols table[]
---@param package string?
---@return table[]
function M.type_paths(symbols, package)
  local paths = {}
  local function walk(items, enclosing, current_package)
    for _, symbol in ipairs(items) do
      local name = symbol.name or ''
      local kind = symbol.kind
      local next_package = current_package
      local next_enclosing = enclosing
      if kind == 4 then
        next_package = name
      elseif TYPE_KINDS[kind] then
        local path = next_enclosing and (next_enclosing .. '.' .. name) or name
        if next_package and next_package ~= '' then
          path = next_package .. '.' .. path
        end
        paths[#paths + 1] = { symbol = symbol, path = path, name = name }
        next_enclosing = next_enclosing and (next_enclosing .. '.' .. name) or name
      end
      if symbol.children then
        walk(symbol.children, next_enclosing, next_package)
      end
    end
  end
  walk(symbols, nil, package)
  return paths
end

---@param symbols table[]
---@param package string
---@param canonical string
---@return table?
function M.find_type(symbols, package, canonical)
  local paths = M.type_paths(symbols, package)
  local best = nil
  for _, entry in ipairs(paths) do
    if entry.path == canonical then
      return entry.symbol
    end
    if entry.name == canonical:match('([^%.]+)$') then
      best = best or entry.symbol
    end
  end
  return best
end

---@param class_symbol table?
---@param kind integer
---@return table[]
function M.direct_children(class_symbol, kind)
  if not class_symbol or not class_symbol.children then
    return {}
  end
  local result = {}
  for _, child in ipairs(class_symbol.children) do
    if not kind or child.kind == kind then
      result[#result + 1] = child
    end
  end
  return result
end

---@param symbols table[]
---@param package string
---@param canonical string
---@param kind integer
---@return table[]
function M.children_of_type(symbols, package, canonical, kind)
  local class_symbol = M.find_type(symbols, package, canonical)
  return M.direct_children(class_symbol, kind)
end

---@param item table
---@return string
function M.method_signature_from_hierarchy(item)
  local signature = item.name or ''
  local open_index = signature:find('(', 1, true)
  if not open_index then
    return signature
  end
  local depth = 0
  for index = open_index, #signature do
    local char = signature:sub(index, index)
    if char == '(' then
      depth = depth + 1
    elseif char == ')' then
      depth = depth - 1
      if depth == 0 then
        return signature:sub(1, index)
      end
    end
  end
  return signature
end

--- Find a direct method/constructor symbol matching a call-hierarchy item.
---@param symbols table[]
---@param package string
---@param canonical_owner string
---@param item table
---@return table?
function M.find_member_symbol(symbols, package, canonical_owner, item)
  local class_symbol = M.find_type(symbols, package, canonical_owner)
  if not class_symbol or not class_symbol.children then
    return nil
  end
  local signature = M.method_signature_from_hierarchy(item)
  local candidates = {}
  for _, child in ipairs(class_symbol.children) do
    if (child.kind == 6 or child.kind == 9) and child.name == signature then
      candidates[#candidates + 1] = child
    end
  end
  if #candidates == 1 then
    return candidates[1]
  end
  if #candidates > 1 then
    return candidates[1]
  end
  return nil
end

---@param symbols table[]
---@return table[]
function M.flatten(symbols)
  local result = {}
  local function walk(items, parent)
    for _, symbol in ipairs(items) do
      result[#result + 1] = { symbol = symbol, parent = parent }
      if symbol.children then
        walk(symbol.children, symbol)
      end
    end
  end
  walk(symbols, nil)
  return result
end

return M
