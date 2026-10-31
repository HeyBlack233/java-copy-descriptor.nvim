local M = {}

local primitive_descriptors = {
  byte = 'B',
  short = 'S',
  int = 'I',
  long = 'J',
  char = 'C',
  float = 'F',
  double = 'D',
  boolean = 'Z',
  void = 'V',
}

local declaration_query = nil

local function field(node, name)
  if node.field then
    local nodes = node:field(name)
    return nodes and nodes[1] or nil
  end
  if node.child_by_field_name then
    return node:child_by_field_name(name)
  end
  return nil
end

M.field = field

local function get_query()
  if declaration_query then
    return declaration_query
  end
  declaration_query = vim.treesitter.query.parse('java', [[
    (method_declaration name: (identifier) @name) @decl
    (constructor_declaration name: (identifier) @name) @decl
    (compact_constructor_declaration name: (identifier) @name) @decl
  ]])
  return declaration_query
end

local function first_node(value)
  if type(value) == 'table' then
    return value[1]
  end
  return value
end

local function match_node(match, capture_ids, name)
  local id = capture_ids[name]
  if not id then
    return nil
  end
  return first_node(match[id])
end

---@param text string
---@return vim.treesitter.LanguageTree?
function M.parse(text)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, 'java')
  if not ok then
    return nil
  end
  return parser
end

---@return boolean
function M.available()
  local ok = pcall(vim.treesitter.language.add, 'java')
  return ok
end

---@param node vim.treesitter.Node
---@param text string
---@return string
function M.node_text(node, text)
  return vim.treesitter.get_node_text(node, text)
end

---@param text string
---@return vim.treesitter.Node?
function M.root(text)
  local parser = M.parse(text)
  if not parser then
    return nil
  end
  return parser:parse()[1]:root()
end

---@param text string
---@return string
function M.package_name(text)
  local root = M.root(text)
  if not root then
    return ''
  end
  for child in root:iter_children() do
    if child:named() and child:type() == 'package_declaration' then
      local name = child:named_child(0)
      if name then
        return M.node_text(name, text)
      end
    end
  end
  return ''
end

---@param line string
---@param utf16_index integer
---@return integer
function M.utf16_to_byte(line, utf16_index)
  return vim.str_byteindex(line, 'utf-16', utf16_index)
end

---@param line string
---@param byte_index integer
---@return integer
function M.byte_to_utf16(line, byte_index)
  return vim.str_utfindex(line, 'utf-16', byte_index)
end

---@param node vim.treesitter.Node
---@param lines string[]
---@return { line: integer, character: integer }
function M.node_position(node, lines)
  local row, col = node:start()
  local line = lines[row + 1] or ''
  return { line = row, character = M.byte_to_utf16(line, col) }
end

---@param node vim.treesitter.Node
---@param text string
---@return vim.treesitter.Node?
function M.rightmost_type_identifier(node, text)
  local node_type = node:type()
  if node_type == 'type_identifier' then
    return node
  end
  if node_type == 'generic_type' then
    local raw = node:named_child(0)
    return raw and M.rightmost_type_identifier(raw, text) or nil
  end
  if node_type == 'annotated_type' then
    local raw = field(node, 'type') or node:named_child(0)
    return raw and M.rightmost_type_identifier(raw, text) or nil
  end
  if node_type == 'scoped_type_identifier' then
    local count = node:named_child_count()
    for i = count - 1, 0, -1 do
      local found = M.rightmost_type_identifier(node:named_child(i), text)
      if found then
        return found
      end
    end
  end
  return nil
end

---@param node vim.treesitter.Node
---@param text string
---@return integer
function M.dimensions_count(node, text)
  local dimensions = field(node, 'dimensions')
  if not dimensions then
    for child in node:iter_children() do
      if child:named() and child:type() == 'dimensions' then
        dimensions = child
        break
      end
    end
  end
  if not dimensions then
    return 0
  end
  local value = M.node_text(dimensions, text)
  local _, count = value:gsub('%[', '')
  return count
end

---@param node vim.treesitter.Node
---@param text string
---@return boolean
function M.is_primitive(node, text)
  local node_type = node:type()
  if node_type == 'integral_type' or node_type == 'floating_point_type' or node_type == 'boolean_type' then
    return true
  end
  if node_type == 'void_type' then
    return true
  end
  return primitive_descriptors[M.node_text(node, text)] ~= nil
end

---@param node vim.treesitter.Node
---@param text string
---@return string?
function M.primitive_descriptor(node, text)
  return primitive_descriptors[M.node_text(node, text)]
end

---@param node vim.treesitter.Node
---@return vim.treesitter.Node?
function M.enclosing_type(node)
  local current = node:parent()
  while current do
    local node_type = current:type()
    if node_type == 'class_declaration'
      or node_type == 'enum_declaration'
      or node_type == 'record_declaration'
      or node_type == 'interface_declaration'
      or node_type == 'annotation_type_declaration'
    then
      return current
    end
    current = current:parent()
  end
  return nil
end

---@param node vim.treesitter.Node
---@param text string
---@return string
function M.type_name(node, text)
  return M.node_text(node, text)
end

---@param node vim.treesitter.Node
---@param text string
---@return boolean
function M.type_is_static(node, text)
  for child in node:iter_children() do
    if child:named() and child:type() == 'modifiers' then
      local value = M.node_text(child, text)
      return value:match('static') ~= nil
    end
  end
  return false
end

---@param node vim.treesitter.Node
---@return vim.treesitter.Node?
function M.parent_type(node)
  local parent = node:parent()
  while parent do
    local node_type = parent:type()
    if node_type == 'class_declaration'
      or node_type == 'enum_declaration'
      or node_type == 'record_declaration'
      or node_type == 'interface_declaration'
    then
      return parent
    end
    parent = parent:parent()
  end
  return nil
end

---@param decl vim.treesitter.Node
---@return boolean
function M.is_constructor(decl)
  local node_type = decl:type()
  return node_type == 'constructor_declaration' or node_type == 'compact_constructor_declaration'
end

---@param decl vim.treesitter.Node
---@param text string
---@return vim.treesitter.Node?
function M.return_type(decl, text)
  if M.is_constructor(decl) then
    return nil
  end
  return field(decl, 'type')
end

---@param node vim.treesitter.Node
---@param text string
---@return { node: vim.treesitter.Node, varargs: boolean }[]
function M.parameter_nodes(node, text)
  if node:type() == 'compact_constructor_declaration' then
    local record = node:parent()
    while record and record:type() ~= 'record_declaration' do
      record = record:parent()
    end
    if record then
      local params = field(record, 'parameters')
      if params then
        return M.parameter_nodes(params, text)
      end
    end
    return {}
  end

  local params = nil
  if node:type() == 'formal_parameters' then
    params = node
  else
    params = field(node, 'parameters')
  end
  if not params then
    return {}
  end

  local result = {}
  for child in params:iter_children() do
    if child:named() then
      local child_type = child:type()
      if child_type == 'formal_parameter' then
        local type_node = field(child, 'type')
        if type_node then
          result[#result + 1] = { node = type_node, varargs = false }
        end
      elseif child_type == 'spread_parameter' then
        local type_node = nil
        for part in child:iter_children() do
          if part:named()
            and (part:type() == 'type_identifier'
              or part:type() == 'scoped_type_identifier'
              or part:type() == 'generic_type'
              or part:type() == 'array_type'
              or part:type() == 'integral_type'
              or part:type() == 'floating_point_type'
              or part:type() == 'boolean_type')
          then
            type_node = part
            break
          end
        end
        if type_node then
          result[#result + 1] = { node = type_node, varargs = true }
        end
      end
    end
  end
  return result
end

---@param node vim.treesitter.Node
---@param text string
---@return table<string, vim.treesitter.Node?>
function M.type_parameter_map(node, text)
  local result = {}
  local current = node
  while current do
    for child in current:iter_children() do
      if child:named() and child:type() == 'type_parameters' then
        for parameter in child:iter_children() do
          if parameter:named() and parameter:type() == 'type_parameter' then
            local name_node = parameter:named_child(0)
            if name_node then
              local name = M.node_text(name_node, text)
              if result[name] == nil then
                local bound = nil
                for part in parameter:iter_children() do
                  if part:named() and part:type() == 'type_bound' then
                    bound = part:named_child(0)
                    break
                  end
                end
                result[name] = { bound = bound }
              end
            end
          end
        end
      end
    end
    current = current:parent()
  end
  return result
end

---Find a method or constructor declaration at an LSP selection range.
---@param text string
---@param selection { start: { line: integer, character: integer } }
---@return { node: vim.treesitter.Node, name: string, kind: string }?
function M.find_decl_by_selection(text, selection)
  local parser = M.parse(text)
  if not parser then
    return nil
  end
  local root = parser:parse()[1]:root()
  local query = get_query()
  local capture_ids = {}
  for id, name in pairs(query.captures) do
    capture_ids[name] = id
  end
  local lines = vim.split(text, '\n', { plain = true })
  local target_line = selection.start.line
  local target_line_text = lines[target_line + 1] or ''
  local target_byte = M.utf16_to_byte(target_line_text, selection.start.character)

  local best = nil
  for _, match in query:iter_matches(root, text, 0, -1) do
    local decl = match_node(match, capture_ids, 'decl')
    local name = match_node(match, capture_ids, 'name')
    if decl and name then
      local row, col = name:start()
      local node_type = decl:type()
      local kind = 'method'
      if node_type == 'constructor_declaration' or node_type == 'compact_constructor_declaration' then
        kind = 'constructor'
      end
      if row == target_line and col >= target_byte and col <= target_byte + 1 then
        return { node = decl, name = M.node_text(name, text), kind = kind }
      end

      local start_row, start_col, end_row, end_col = decl:range()
      local after_start = target_line > start_row or (target_line == start_row and target_byte >= start_col)
      local before_end = target_line < end_row or (target_line == end_row and target_byte <= end_col)
      if after_start and before_end then
        local span = (end_row - start_row) * 100000 + (end_col - start_col)
        if not best or span < best.span then
          best = {
            node = decl,
            name = M.node_text(name, text),
            kind = kind,
            span = span,
          }
        end
      end
    end
  end
  if best then
    return { node = best.node, name = best.name, kind = best.kind }
  end
  return nil
end

---Find the type declaration containing an LSP selection range.
---@param text string
---@param selection { start: { line: integer, character: integer } }
---@return vim.treesitter.Node?
function M.find_type_by_selection(text, selection)
  local parser = M.parse(text)
  if not parser then
    return nil
  end
  local root = parser:parse()[1]:root()
  local lines = vim.split(text, '\n', { plain = true })
  local line_text = lines[selection.start.line + 1] or ''
  local byte = M.utf16_to_byte(line_text, selection.start.character)
  local node = root:named_descendant_for_range(selection.start.line, byte, selection.start.line, byte)
  while node do
    local node_type = node:type()
    if node_type == 'class_declaration'
      or node_type == 'enum_declaration'
      or node_type == 'record_declaration'
      or node_type == 'interface_declaration'
    then
      return node
    end
    node = node:parent()
  end
  return nil
end

---Find a declaration by exact name and arity.
---@param text string
---@param name string
---@param arity integer
---@return { node: vim.treesitter.Node, kind: string }?
function M.find_decl_by_name(text, name, arity)
  local parser = M.parse(text)
  if not parser then
    return nil
  end
  local root = parser:parse()[1]:root()
  local query = get_query()
  local capture_ids = {}
  for id, capture_name in pairs(query.captures) do
    capture_ids[capture_name] = id
  end
  for _, match in query:iter_matches(root, text, 0, -1) do
    local decl = match_node(match, capture_ids, 'decl')
    local name_node = match_node(match, capture_ids, 'name')
    if decl and name_node and M.node_text(name_node, text) == name then
      local params = M.parameter_nodes(decl, text)
      if #params == arity then
        local node_type = decl:type()
        local kind = 'method'
        if node_type == 'constructor_declaration' or node_type == 'compact_constructor_declaration' then
          kind = 'constructor'
        end
        return { node = decl, kind = kind }
      end
    end
  end
  return nil
end

return M
