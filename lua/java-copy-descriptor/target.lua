local descriptor = require('java-copy-descriptor.descriptor')
local document = require('java-copy-descriptor.document')
local lsp = require('java-copy-descriptor.lsp')
local resolve = require('java-copy-descriptor.resolve')
local source = require('java-copy-descriptor.source')
local treesitter = require('java-copy-descriptor.treesitter')

local M = {}

local function range_contains(range, position)
  if position.line < range.start.line or position.line > range["end"].line then
    return false
  end
  if position.line == range.start.line and position.character < range.start.character then
    return false
  end
  if position.line == range["end"].line and position.character >= range["end"].character then
    return false
  end
  return true
end

local function signature_parts(item)
  local signature = document.method_signature_from_hierarchy(item)
  local name = signature:match('^([%w_$]+)') or signature
  local params = signature:match('%((.*)%)') or ''
  local arity = 0
  local depth = 0
  if params ~= '' then
    arity = 1
    for index = 1, #params do
      local char = params:sub(index, index)
      if char == '<' then
        depth = depth + 1
      elseif char == '>' then
        depth = math.max(0, depth - 1)
      elseif char == ',' and depth == 0 then
        arity = arity + 1
      end
    end
  end
  return name, arity
end

local function get_symbols(ctx, uri)
  local cached = ctx.symbol_cache[uri]
  if cached then
    return cached.symbols, cached.package, cached.text
  end
  local symbols, err = lsp.request(ctx.client, 'textDocument/documentSymbol', {
    textDocument = { uri = uri },
  })
  if err then
    error(string.format('Could not read document symbols for %s: %s', uri, err.message or err))
  end
  local text = source.read(ctx, uri)
  local package = source.package_name(text)
  symbols = symbols or {}
  ctx.symbol_cache[uri] = { symbols = symbols, package = package, text = text }
  return symbols, package, text
end

local function find_declaration(ctx, uri, selection, fallback_name, fallback_arity)
  local text, lines = source.read(ctx, uri)
  local decl = treesitter.find_decl_by_selection(text, selection)
  if decl then
    return decl.node, lines, text
  end
  if fallback_name then
    local found = treesitter.find_decl_by_name(text, fallback_name, fallback_arity or 0)
    if found then
      return found.node, lines, text
    end
  end
  return nil, lines, text
end

local function meta_for_declaration(decl, text, kind, class_binary)
  local enclosing = treesitter.enclosing_type(decl)
  local meta = { kind = kind, enum = false, inner = false }
  if not enclosing then
    return meta
  end
  local enclosing_type = enclosing:type()
  meta.enum = enclosing_type == 'enum_declaration'
  if class_binary then
    local parent_binary = class_binary:match('(.+)%$[^%$]+$')
    meta.enclosing_binary = parent_binary
  end

  if enclosing_type == 'class_declaration' then
    local body = enclosing:parent()
    local parent_type = body and body:parent()
    if body and body:type() == 'class_body' and parent_type and parent_type:type() == 'class_declaration' then
      meta.inner = not treesitter.type_is_static(enclosing, text)
    end
  end
  return meta
end

local function make_type_resolver(ctx, uri, text, lines, decl)
  local type_params = treesitter.type_parameter_map(decl, text)

  local function fail(message)
    return nil, message
  end

  local resolve_type
  resolve_type = function(node, varargs)
    if not node then
      return fail('Missing Java type node')
    end
    local node_type = node:type()
    local primitive = treesitter.primitive_descriptor(node, text)
    if primitive then
      return primitive
    end
    if node_type == 'void_type' then
      return 'V'
    end
    if node_type == 'array_type' then
      local element = treesitter.field(node, 'element') or node:named_child(0)
      if not element then
        return fail('Java array type has no element type')
      end
      local element_descriptor, err = resolve_type(element, false)
      if not element_descriptor then
        return nil, err
      end
      local dimensions = treesitter.dimensions_count(node, text)
      return string.rep('[', dimensions) .. element_descriptor
    end
    if node_type == 'generic_type' or node_type == 'annotated_type' then
      local raw = treesitter.field(node, 'type') or node:named_child(0)
      if not raw then
        return fail('Java generic type has no raw type')
      end
      return resolve_type(raw, varargs)
    end
    if node_type == 'type_identifier' or node_type == 'scoped_type_identifier' then
      local name = treesitter.node_text(node, text)
      local parameter = type_params[name]
      if parameter then
        if parameter.bound then
          return resolve_type(parameter.bound, varargs)
        end
        return 'Ljava/lang/Object;'
      end

      local identifier = treesitter.rightmost_type_identifier(node, text) or node
      local position = treesitter.node_position(identifier, lines)
      local info = resolve.class_info(ctx, uri, position)
      if not info then
        return fail(string.format('Could not resolve Java type %s', name))
      end
      local value = 'L' .. info.binary .. ';'
      if varargs then
        value = '[' .. value
      end
      return value
    end
    if node_type == 'wildcard' then
      return 'Ljava/lang/Object;'
    end
    return fail(string.format('Unsupported Java type node: %s', node_type))
  end

  return function(node, varargs)
    local value, err = resolve_type(node, varargs)
    if not value then
      return nil, err
    end
    if varargs and value:sub(1, 1) ~= '[' then
      return '[' .. value
    end
    return value
  end
end

local function resolve_item(ctx, item)
  local uri = item.uri
  local owner = item.detail or ''
  local symbols, package = get_symbols(ctx, uri)
  local member = document.find_member_symbol(symbols, package, owner, item)
  local selection = member and member.selectionRange or item.selectionRange
  local fallback_name, fallback_arity = signature_parts(item)

  local decl, lines, text = find_declaration(ctx, uri, selection, fallback_name, fallback_arity)
  if not decl then
    error('Could not locate the Java declaration for the method under the cursor')
  end

  local kind = 'method'
  if item.kind == 9 or treesitter.is_constructor(decl) then
    kind = 'constructor'
  end
  local class_binary = nil
  if kind == 'constructor' then
    class_binary = resolve.owner_binary(ctx, uri, owner)
  end

  local meta = meta_for_declaration(decl, text, kind, class_binary)
  local type_resolver = make_type_resolver(ctx, uri, text, lines, decl)
  local value, err = descriptor.build(decl, text, type_resolver, meta)
  if not value then
    error(err or 'Could not build the JVM descriptor')
  end

  local name = item.name or ''
  name = name:match('^([%w_$]+)') or name
  return value, { owner = owner, name = name, kind = kind, uri = uri }
end

local function enclosing_type_node(node)
  local current = node
  while current do
    local node_type = current:type()
    if node_type == 'class_declaration'
      or node_type == 'enum_declaration'
      or node_type == 'record_declaration'
      or node_type == 'interface_declaration'
    then
      return current
    end
    current = current:parent()
  end
  return nil
end

local function raw_type_node(node)
  if not node then
    return nil
  end
  if node:type() == 'generic_type' or node:type() == 'annotated_type' then
    return treesitter.field(node, 'type') or node:named_child(0)
  end
  return node
end

local function argument_count(node)
  local arguments = treesitter.field(node, 'arguments')
  if not arguments then
    return 0
  end
  local count = 0
  for child in arguments:iter_children() do
    if child:named() then
      count = count + 1
    end
  end
  return count
end

local function constructor_context(ctx)
  local text = source.read(ctx, ctx.uri)
  local parser = treesitter.parse(text)
  if not parser then
    return nil
  end
  local root = parser:parse()[1]:root()
  local node = root:named_descendant_for_range(ctx.cursor_byte.line, ctx.cursor_byte.character, ctx.cursor_byte.line, ctx.cursor_byte.character)
  if not node then
    return nil
  end
  local current = node
  while current do
    local node_type = current:type()
    if node_type == 'object_creation_expression' then
      local type_node = raw_type_node(treesitter.field(current, 'type'))
      if not type_node then
        return nil
      end
      local identifier = treesitter.rightmost_type_identifier(type_node, text) or type_node
      local lines = vim.split(text, '\n', { plain = true })
      local position = treesitter.node_position(identifier, lines)
      local info = resolve.class_info(ctx, ctx.uri, position)
      if not info then
        return nil
      end
      return {
        kind = 'object_creation',
        node = current,
        class_uri = info.definition_uri,
        canonical = info.canonical,
        binary = info.binary,
        arguments_count = argument_count(current),
      }
    elseif node_type == 'explicit_constructor_invocation' then
      local constructor = treesitter.field(current, 'constructor')
      local enclosing = enclosing_type_node(current)
      if not constructor or not enclosing then
        return nil
      end
      local constructor_text = treesitter.node_text(constructor, text)
      local type_node = nil
      if constructor_text == 'this' then
        type_node = treesitter.field(enclosing, 'name')
      else
        local superclass = treesitter.field(enclosing, 'superclass')
        if superclass then
          type_node = raw_type_node(superclass:named_child(0))
        end
      end
      if not type_node then
        return nil
      end
      local identifier = treesitter.rightmost_type_identifier(type_node, text) or type_node
      local lines = vim.split(text, '\n', { plain = true })
      local position = treesitter.node_position(identifier, lines)
      local info = resolve.class_info(ctx, ctx.uri, position)
      if not info and constructor_text == 'this' then
        local name = treesitter.node_text(type_node, text)
        local package = treesitter.package_name(text)
        info = {
          canonical = package ~= '' and (package .. '.' .. name) or name,
          binary = resolve.canonical_to_binary(package ~= '' and (package .. '.' .. name) or name, package),
          definition_uri = ctx.uri,
        }
      end
      if not info then
        return nil
      end
      return {
        kind = constructor_text == 'this' and 'this' or 'super',
        node = current,
        class_uri = constructor_text == 'this' and ctx.uri or info.definition_uri,
        canonical = info.canonical,
        binary = info.binary,
        arguments_count = argument_count(current),
      }
    end
    current = current:parent()
  end
  return nil
end

local function constructor_declaration(ctx, class_uri, constructor_symbol, text)
  local decl = treesitter.find_decl_by_selection(text, constructor_symbol.selectionRange)
  if decl then
    return decl.node
  end
  local name, arity = signature_parts({ name = constructor_symbol.name or '' })
  local found = treesitter.find_decl_by_name(text, name, arity)
  return found and found.node or nil
end

local function resolve_constructor(ctx, constructor)
  local symbols, package, class_text = get_symbols(ctx, constructor.class_uri)
  local class_symbol = document.find_type(symbols, package, constructor.canonical)
  if not class_symbol then
    error(string.format('Could not find class %s in its Java document', constructor.canonical))
  end
  local constructors = document.direct_children(class_symbol, 9)
  local owner = constructor.canonical
  local name = owner:match('([^%.]+)$') or owner

  if #constructors == 0 then
    if constructor.arguments_count == 0 then
      local class_node = treesitter.find_type_by_selection(class_text, class_symbol.selectionRange)
      local meta = {
        kind = 'constructor',
        enum = class_symbol.kind == 10,
        inner = false,
      }
      if class_node and class_node:type() == 'class_declaration' then
        local body = class_node:parent()
        local parent_type = body and body:parent()
        if body and body:type() == 'class_body' and parent_type and parent_type:type() == 'class_declaration' then
          meta.inner = not treesitter.type_is_static(class_node, class_text)
        end
      end
      if constructor.binary then
        meta.enclosing_binary = constructor.binary:match('(.+)%$[^%$]+$')
      end
      return descriptor.default_constructor(meta), { owner = owner, name = name, kind = 'constructor' }
    end
    error('No matching constructor declaration found; compile or re-import the project first')
  end

  local chosen = nil
  local chosen_decl = nil
  for _, constructor_symbol in ipairs(constructors) do
    local refs, refs_err = lsp.request(ctx.client, 'textDocument/references', {
      textDocument = { uri = constructor.class_uri },
      position = constructor_symbol.selectionRange.start,
      context = { includeDeclaration = false },
    })
    if not refs_err and type(refs) == 'table' then
      for _, reference in ipairs(refs) do
        if reference.uri == ctx.uri and range_contains(reference.range, ctx.position) then
          if chosen then
            error('Ambiguous constructor call; multiple constructors reference the cursor')
          end
          chosen = constructor_symbol
          chosen_decl = constructor_declaration(ctx, constructor.class_uri, constructor_symbol, class_text)
        end
      end
    end
  end

  if not chosen then
    if #constructors == 1 then
      chosen = constructors[1]
      chosen_decl = constructor_declaration(ctx, constructor.class_uri, chosen, class_text)
    else
      local candidates = {}
      for _, constructor_symbol in ipairs(constructors) do
        local decl = constructor_declaration(ctx, constructor.class_uri, constructor_symbol, class_text)
        if decl and descriptor.arity(decl, class_text) == constructor.arguments_count then
          candidates[#candidates + 1] = { symbol = constructor_symbol, decl = decl }
        end
      end
      if #candidates == 1 then
        chosen = candidates[1].symbol
        chosen_decl = candidates[1].decl
      else
        error('Ambiguous constructor call; JDT LS references did not identify the selected overload')
      end
    end
  end

  if not chosen_decl then
    error('Could not locate the selected constructor declaration')
  end

  local meta = meta_for_declaration(chosen_decl, class_text, 'constructor', constructor.binary)
  local type_resolver = make_type_resolver(ctx, constructor.class_uri, class_text, vim.split(class_text, '\n', { plain = true }), chosen_decl)
  local value, err = descriptor.build(chosen_decl, class_text, type_resolver, meta)
  if not value then
    error(err or 'Could not build the constructor descriptor')
  end
  return value, { owner = owner, name = name, kind = 'constructor' }
end

local function prepare_call_hierarchy(ctx)
  local result, err = lsp.request(ctx.client, 'textDocument/prepareCallHierarchy', lsp.position_params(ctx.uri, ctx.position))
  if err then
    return nil
  end
  if type(result) ~= 'table' then
    return nil
  end
  return result
end

---Resolve the descriptor of the Java method or constructor under the cursor.
---@param ctx table
---@return string descriptor
---@return table metadata
function M.descriptor_at_cursor(ctx)
  local items = prepare_call_hierarchy(ctx)
  local method_item = nil
  local constructor_item = nil
  if items then
    for _, item in ipairs(items) do
      if item.kind == 6 then
        method_item = method_item or item
      elseif item.kind == 9 then
        constructor_item = constructor_item or item
      end
    end
  end

  if method_item then
    return resolve_item(ctx, method_item)
  end
  if constructor_item then
    local ok, value, metadata = pcall(resolve_item, ctx, constructor_item)
    if ok then
      return value, metadata
    end
    local constructor = constructor_context(ctx)
    if constructor then
      return resolve_constructor(ctx, constructor)
    end
    error(value)
  end

  local constructor = constructor_context(ctx)
  if constructor then
    return resolve_constructor(ctx, constructor)
  end

  error('No Java method or constructor found at the cursor')
end


return M
