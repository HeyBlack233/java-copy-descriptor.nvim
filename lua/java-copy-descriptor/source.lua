local lsp = require('java-copy-descriptor.lsp')

local M = {}

local function split_lines(text)
  return vim.split(text, '\n', { plain = true })
end

--- Read and cache the full text of a source or jdt URI.
--- Current-buffer contents are used when available so unsaved edits are honored.
---@param ctx table
---@param uri string
---@return string text
---@return string[] lines
function M.read(ctx, uri)
  local cached = ctx.text_cache[uri]
  if cached then
    return cached.text, cached.lines
  end

  local text
  if uri:match('^jdt://') then
    local result, err = lsp.request(ctx.client, 'java/classFileContents', { uri = uri })
    if err then
      error(string.format('Could not load decompiled class contents: %s', err.message or err))
    end
    if type(result) ~= 'string' or result == '' then
      error('JDT LS returned empty class contents. Enable class file content support in nvim-jdtls.')
    end
    text = result
  elseif uri:match('^file://') then
    local fname = vim.uri_to_fname(uri)
    local bufnr = vim.fn.bufnr(fname)
    if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
      text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n')
    else
      local ok, lines = pcall(vim.fn.readfile, fname)
      if not ok then
        error(string.format('Could not read %s', fname))
      end
      text = table.concat(lines, '\n')
    end
  else
    error(string.format('Unsupported document URI: %s', uri))
  end

  text = text:gsub('\r\n', '\n')
  local lines = split_lines(text)
  ctx.text_cache[uri] = { text = text, lines = lines }
  return text, lines
end

---@param text string
---@return string
function M.package_name(text)
  local treesitter = require('java-copy-descriptor.treesitter')
  local parser = treesitter.parse(text)
  if not parser then
    return ''
  end
  local root = parser:parse()[1]:root()
  for child in root:iter_children() do
    if child:named() and child:type() == 'package_declaration' then
      return treesitter.node_text(child, text):gsub('package', ''):gsub(';', ''):gsub('%s', '')
    end
  end
  return ''
end

return M
