local script = debug.getinfo(1, 'S').source:sub(2)
local repo = vim.fn.fnamemodify(script, ':h:h:h')
vim.opt.rtp:append(repo)

local failures = 0
local checks = 0

local function check(name, condition, detail)
  checks = checks + 1
  if not condition then
    failures = failures + 1
    io.stderr:write(string.format('FAIL: %s%s\n', name, detail and ('\n  ' .. tostring(detail)) or ''))
  else
    print('ok: ' .. name)
  end
end

local function eq(name, actual, expected)
  check(name, actual == expected, string.format('expected %s, got %s', vim.inspect(expected), vim.inspect(actual)))
end

local function read(path)
  local file = assert(io.open(path, 'r'))
  local content = file:read('*a')
  file:close()
  return content
end

local fixture = repo .. '/tests/fixtures/project/src/demo/Foo.java'
local text = read(fixture)
local treesitter = require('java-copy-descriptor.treesitter')

if not treesitter.available() then
  io.stderr:write('FAIL: tree-sitter-java parser is not installed\n')
  vim.cmd('qa! 1')
end

local function fake_resolver(node, varargs)
  local node_type = node:type()
  local node_text = treesitter.node_text(node, text)
  if varargs then
    return '[' .. fake_resolver(node, false)
  end
  if node_type == 'integral_type' then
    return ({ byte = 'B', short = 'S', int = 'I', long = 'J', char = 'C' })[node_text]
  end
  if node_type == 'floating_point_type' then
    return ({ float = 'F', double = 'D' })[node_text]
  end
  if node_type == 'boolean_type' or node_text == 'boolean' then
    return 'Z'
  end
  if node_type == 'void_type' or node_text == 'void' then
    return 'V'
  end
  if node_type == 'array_type' then
    local value = fake_resolver(node:named_child(0), false)
    return string.rep('[', treesitter.dimensions_count(node, text)) .. value
  end
  if node_type == 'generic_type' then
    return fake_resolver(node:named_child(0), varargs)
  end
  if node_text == 'String' then
    return 'Ljava/lang/String;'
  end
  if node_text == 'Map' then
    return 'Ljava/util/Map;'
  end
  if node_text == 'List' then
    return 'Ljava/util/List;'
  end
  if node_text == 'T' then
    return 'Ljava/lang/Number;'
  end
  if node_text == 'Inner' then
    return 'Ldemo/Foo$Outer$Inner;'
  end
  if node_text == 'Color' then
    return 'Ldemo/Foo$Color;'
  end
  return 'Ljava/lang/Object;'
end

local descriptor = require('java-copy-descriptor.descriptor')

local plain = treesitter.find_decl_by_name(text, 'plain', 2)
check('plain declaration found', plain ~= nil)
if plain then
  local value = descriptor.build(plain.node, text, fake_resolver, { kind = 'method' })
  eq('plain descriptor', value, '(Ljava/lang/String;Ljava/util/Map;)Ljava/lang/String;')
end

local sum = treesitter.find_decl_by_name(text, 'sum', 1)
check('sum declaration found', sum ~= nil)
if sum then
  local value = descriptor.build(sum.node, text, fake_resolver, { kind = 'method' })
  eq('varargs descriptor', value, '([I)I')
end

local array = treesitter.find_decl_by_name(text, 'array', 1)
check('array declaration found', array ~= nil)
if array then
  local value = descriptor.build(array.node, text, fake_resolver, { kind = 'method' })
  eq('array descriptor', value, '([Ljava/lang/String;)[I')
end

local matrix = treesitter.find_decl_by_name(text, 'matrix', 1)
check('matrix declaration found', matrix ~= nil)
if matrix then
  local value = descriptor.build(matrix.node, text, fake_resolver, { kind = 'method' })
  eq('multidimensional descriptor', value, '([[Ljava/lang/String;)[[I')
end

local identity = treesitter.find_decl_by_name(text, 'identity', 1)
check('identity declaration found', identity ~= nil)
if identity then
  local value = descriptor.build(identity.node, text, fake_resolver, { kind = 'method' })
  eq('bounded type variable descriptor', value, '(Ljava/lang/Number;)Ljava/lang/Number;')
end

local ctor = treesitter.find_decl_by_name(text, 'Foo', 0)
check('constructor declaration found', ctor ~= nil)
if ctor then
  local value = descriptor.build(ctor.node, text, fake_resolver, { kind = 'constructor' })
  eq('constructor descriptor', value, '()V')
end

local inner = treesitter.find_decl_by_name(text, 'Inner', 1)
check('inner constructor found', inner ~= nil)
if inner then
  local value = descriptor.build(inner.node, text, fake_resolver, {
    kind = 'constructor',
    inner = true,
    enclosing_binary = 'demo/Foo$Outer',
  })
  eq('inner constructor descriptor', value, '(Ldemo/Foo$Outer;I)V')
end

local enum_ctor = treesitter.find_decl_by_name(text, 'Color', 1)
check('enum constructor found', enum_ctor ~= nil)
if enum_ctor then
  local value = descriptor.build(enum_ctor.node, text, fake_resolver, { kind = 'constructor', enum = true })
  eq('enum constructor descriptor', value, '(Ljava/lang/String;ILjava/lang/String;)V')
end

local point = treesitter.find_decl_by_name(text, 'Point', 2)
check('record compact constructor found', point ~= nil)
if point then
  local value = descriptor.build(point.node, text, fake_resolver, { kind = 'constructor' })
  eq('record compact constructor descriptor', value, '(II)V')
end

eq('default constructor descriptor', descriptor.default_constructor({}), '()V')
eq(
  'inner default constructor descriptor',
  descriptor.default_constructor({ inner = true, enclosing_binary = 'demo/Foo$Outer' }),
  '(Ldemo/Foo$Outer;)V'
)

local resolve = require('java-copy-descriptor.resolve')
local jdt = 'jdt://contents/gson.jar/com.google.gson/Gson.java?=project/%3Ccom.google.gson%28Gson.class'
eq('jdt binary name', resolve.binary_from_jdt_uri(jdt), 'com/google/gson/Gson')
local jdt_nested = 'jdt://contents/java.base/java.util/Map.java?=project/%3Cjava.util%28Map$Entry.class'
eq('jdt nested binary name', resolve.binary_from_jdt_uri(jdt_nested), 'java/util/Map$Entry')
eq('canonical nested binary', resolve.canonical_to_binary('java.util.Map.Entry', 'java.util'), 'java/util/Map$Entry')

local document = require('java-copy-descriptor.document')
eq(
  'method signature from hierarchy',
  document.method_signature_from_hierarchy({ name = 'plain(String, int[], Map<String, List<Long>>) : String' }),
  'plain(String, int[], Map<String, List<Long>>)'
)
eq(
  'generic method signature from hierarchy',
  document.method_signature_from_hierarchy({ name = 'generic(T) <T> : T' }),
  'generic(T)'
)

local clipboard = require('java-copy-descriptor.clipboard')
local ok = clipboard.write('test-value', 'a')
check('clipboard write', ok)
eq('clipboard value', vim.fn.getreg('a'), 'test-value')

eq('package name', require('java-copy-descriptor.source').package_name('package demo; class A {}'), 'demo')

local utf16_line = 'aé'
eq('utf16 to byte', treesitter.utf16_to_byte(utf16_line, 2), 3)
eq('byte to utf16', treesitter.byte_to_utf16(utf16_line, 3), 2)

local symbols = {
  {
    name = 'demo',
    kind = 4,
    children = {
      {
        name = 'Foo',
        kind = 5,
        children = {
          { name = 'Foo(int)', kind = 9 },
          { name = 'plain(String, Map)', kind = 6 },
        },
      },
    },
  },
}
check('document type path', document.find_type(symbols, 'demo', 'demo.Foo') ~= nil)
eq('direct constructors', #document.direct_children(document.find_type(symbols, 'demo', 'demo.Foo'), 9), 1)

print(string.format('\n%d checks, %d failures', checks, failures))
if failures > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('quitall')
end
