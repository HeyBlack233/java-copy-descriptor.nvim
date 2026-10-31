local script = debug.getinfo(1, 'S').source:sub(2)
local repo = vim.fn.fnamemodify(script, ':h:h:h')
vim.opt.rtp:append(repo)
vim.opt.rtp:append(vim.fn.stdpath('data') .. '/lazy/nvim-jdtls')
vim.cmd('filetype on')

local jdtls_bin = os.getenv('JDTLS_BIN')
if not jdtls_bin or jdtls_bin == '' then
  jdtls_bin = vim.fn.exepath('jdtls')
end
if jdtls_bin == '' then
  local mason = vim.fn.stdpath('data') .. '/mason/bin/jdtls'
  if vim.fn.executable(mason) == 1 then
    jdtls_bin = mason
  end
end
if jdtls_bin == '' or vim.fn.executable(jdtls_bin) ~= 1 then
  print('SKIP: jdtls not found')
  vim.cmd('quitall!')
  return
end
if not pcall(require, 'jdtls') then
  print('SKIP: nvim-jdtls not found')
  vim.cmd('quitall!')
  return
end

local fixture = repo .. '/tests/fixtures/project'
local jar = repo .. '/tests/.tmp/tiny-dep.jar'
if vim.fn.filereadable(jar) ~= 1 then
  print('SKIP: fixture jar missing; run tests/run.sh')
  vim.cmd('quitall!')
  return
end

vim.cmd('edit ' .. fixture .. '/src/demo/Foo.java')
vim.bo.filetype = 'java'
local bufnr = vim.api.nvim_get_current_buf()
local config_dir = vim.fn.stdpath('data') .. '/mason/packages/jdtls/config_linux'
if vim.fn.isdirectory(config_dir) ~= 1 then
  print('SKIP: jdtls configuration directory not found')
  vim.cmd('quitall!')
  return
end

local data_dir = repo .. '/tests/.tmp/jdtls-data'
local jdtls = require('jdtls')
jdtls.start_or_attach({
  cmd = {
    jdtls_bin,
    '-data', data_dir,
    '-configuration', config_dir,
  },
  root_dir = fixture,
  settings = {
    java = {
      import = {
        gradle = { enabled = false, wrapper = { enabled = false } },
      },
    },
  },
})
vim.wait(20000, function()
  return #vim.lsp.get_clients({ bufnr = bufnr, name = 'jdtls' }) > 0
end, 100)
local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'jdtls' })[1]
if client then
  local imported = false
  client:request('workspace/executeCommand', {
    command = 'java.project.import',
    arguments = {},
  }, function()
    imported = true
  end, bufnr)
  vim.wait(30000, function()
    return imported
  end, 100)
end
vim.wait(3000, function()
  return false
end, 100)

local failures = 0
local checks = 0
local function eq(name, actual, expected)
  checks = checks + 1
  if actual ~= expected then
    failures = failures + 1
    io.stderr:write(string.format('FAIL: %s\n  expected %s\n  actual   %s\n', name, vim.inspect(expected), vim.inspect(actual)))
  else
    print('ok: ' .. name)
  end
end

local function find_position(marker, token, occurrence)
  occurrence = occurrence or 1
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local seen = 0
  for index, line in ipairs(lines) do
    local search_from = 1
    while true do
      local start_index = line:find(marker, search_from, true)
      if not start_index then
        break
      end
      local token_start = line:find(token, start_index, true)
      if token_start and token_start < start_index + #marker then
        seen = seen + 1
        if seen == occurrence then
          return index - 1, token_start - 1
        end
      end
      search_from = start_index + #marker
    end
  end
  error('Could not find marker ' .. marker .. ' / ' .. token)
end

local function descriptor_for(marker, token, occurrence)
  local line, character = find_position(marker, token, occurrence)
  vim.api.nvim_win_set_cursor(0, { line + 1, character })
  local done, result, error_message = false, nil, nil
  require('java-copy-descriptor').descriptor_at_cursor(function(err, value)
    error_message, result, done = err, value, true
  end)
  vim.wait(12000, function()
    return done
  end, 50)
  if not done then
    error('timed out resolving ' .. marker)
  end
  if error_message then
    error(error_message)
  end
  return result
end

local function expect(marker, token, expected, occurrence)
  local ok, value = pcall(descriptor_for, marker, token, occurrence)
  if not ok then
    checks = checks + 1
    failures = failures + 1
    io.stderr:write(string.format('FAIL: %s\n  %s\n', marker, tostring(value)))
    return
  end
  eq(marker, value, expected)
end

expect('public String plain', 'plain', '(Ljava/lang/String;Ljava/util/Map;)Ljava/lang/String;')
expect('foo.plain("x"', 'plain', '(Ljava/lang/String;Ljava/util/Map;)Ljava/lang/String;')
expect('private static int hidden', 'hidden', '(I)I')
expect('hidden(1)', 'hidden', '(I)I')
expect('public static int sum', 'sum', '([I)I')
expect('sum(1, 2, 3)', 'sum', '([I)I')
expect('public static <T extends Number> T identity', 'identity', '(Ljava/lang/Number;)Ljava/lang/Number;')
expect('identity(1)', 'identity', '(Ljava/lang/Number;)Ljava/lang/Number;')
expect('public int[] array', 'array', '([Ljava/lang/String;)[I')
expect('foo.array', 'array', '([Ljava/lang/String;)[I')
expect('String name();', 'name', '()Ljava/lang/String;')
expect('.name()', 'name', '()Ljava/lang/String;')
expect('new Circle()', 'Circle', '()V')
expect('public Inner(int value)', 'Inner', '(Ldemo/Foo$Outer;I)V')
expect('outer.new Inner(1)', 'Inner', '(Ldemo/Foo$Outer;I)V')
expect('new Foo.Outer()', 'Outer', '()V')
expect('outer.new DefaultInner()', 'DefaultInner', '(Ldemo/Foo$Outer;)V')
expect('Color(String label)', 'Color', '(Ljava/lang/String;ILjava/lang/String;)V')
expect('super(1)', 'super', '(I)V')
expect('this("x")', 'this', '(Ljava/lang/String;)V')
expect('new Child()', 'Child', '()V')
expect('new Chain(1)', 'Chain', '(I)V')
expect('public int[][] matrix', 'matrix', '([[Ljava/lang/String;)[[I')
expect('foo.matrix', 'matrix', '([[Ljava/lang/String;)[[I')
expect('public Point {', 'Point', '(II)V')
expect('new Point(1, 2)', 'Point', '(II)V')
expect('new Plain()', 'Plain', '()V')
expect('new Foo()', 'Foo', '()V')
expect('new TinyDep("x")', 'TinyDep', '(Ljava/lang/String;)V')
expect('new TinyDep(1)', 'TinyDep', '(I)V')
expect('new TinyDep("x").new Nested(1)', 'Nested', '(Llib/TinyDep;I)V')
expect('new TinyDep("x").new DefaultNested()', 'DefaultNested', '(Llib/TinyDep;)V')
expect('dep.format(null)', 'format', '(Ljava/util/List;)Ljava/lang/String;')
expect('TinyDep.describe(null, 1, 2)', 'describe', '(Ljava/util/Map;[I)Ljava/lang/String;')
expect('TinyDep.pick(1)', 'pick', '(Ljava/lang/Number;)Ljava/lang/Number;')
expect('TinyDep.overloaded(1)', 'overloaded', '(I)I')
expect('TinyDep.overloaded("x")', 'overloaded', '(Ljava/lang/String;)I')

-- Exercise the public command and the real clipboard register.
vim.cmd('runtime plugin/java-copy-descriptor.lua')
vim.fn.setreg('+', '')
local line, character = find_position('foo.plain("x"', 'plain')
vim.api.nvim_win_set_cursor(0, { line + 1, character })
vim.cmd('JavaCopyDescriptor')
vim.wait(12000, function()
  return vim.fn.getreg('+') == '(Ljava/lang/String;Ljava/util/Map;)Ljava/lang/String;'
end, 50)
checks = checks + 1
if vim.fn.getreg('+') ~= '(Ljava/lang/String;Ljava/util/Map;)Ljava/lang/String;' then
  failures = failures + 1
  io.stderr:write('FAIL: :JavaCopyDescriptor clipboard\n')
else
  print('ok: :JavaCopyDescriptor clipboard')
end

-- Verify that descriptors follow unsaved buffer edits.
local plain_line = nil
for index, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
  if line:find('public String plain', 1, true) then
    plain_line = index
    break
  end
end
if plain_line then
  local old_line = vim.api.nvim_buf_get_lines(bufnr, plain_line - 1, plain_line, false)[1]
  local new_line = old_line:gsub('String text', 'int text')
  vim.api.nvim_buf_set_lines(bufnr, plain_line - 1, plain_line, false, { new_line })
  vim.wait(2000, function()
    return false
  end, 100)
  expect('public String plain', 'plain', '(ILjava/util/Map;)Ljava/lang/String;')
end


print(string.format('\n%d checks, %d failures', checks, failures))
if failures > 0 then
  vim.cmd('cquit 1')
else
  vim.cmd('quitall!')
end
