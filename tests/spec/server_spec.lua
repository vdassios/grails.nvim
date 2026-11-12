local h = require 'helpers'

local T = {}

function T.initialize_handshake()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  local client = h.client(buf)
  h.eq('grails.nvim', client.server_info.name)
  h.eq('utf-8', client.offset_encoding)
  h.eq(true, client.server_capabilities.definitionProvider)
  h.eq(h.app, client.root_dir)
end

function T.unknown_method_errors()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  local res = h.client(buf):request_sync('grails/nothing', {}, 1000, buf)
  h.eq(-32601, res.err.code)
end

function T.missing_target_is_empty()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  local row, col = h.pos(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '/missing/thing', 1)
  local res = h.client(buf):request_sync('textDocument/definition', {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = row, character = col },
  }, 1000, buf)
  h.eq(nil, res.err)
  h.eq({}, res.result)
end

function T.did_save_under_grails_app_drops_the_index()
  local project = require 'grails.project'
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  local client = h.client(buf)
  local before = project.modules(h.app)
  client:notify('textDocument/didSave', { textDocument = { uri = vim.uri_from_bufnr(buf) } })
  vim.wait(100)
  assert(project.modules(h.app) ~= before, 'the index was not dropped')
end

function T.utf16_client_gets_utf16_columns()
  local buf = h.edit 'web/grails-app/views/book/show.gsp'
  local id = vim.lsp.start({
    name = 'grails-utf16',
    cmd = require('grails.server').start,
    root_dir = h.app,
    capabilities = { general = { positionEncodings = { 'utf-16' } } },
  }, { bufnr = buf })
  local client = assert(vim.lsp.get_client_by_id(id))
  vim.wait(2000, function()
    return client.initialized
  end)
  h.eq('utf-16', client.offset_encoding)
  -- "Bücher – " sits before the tag: 12 bytes, 9 UTF-16 code units.
  local line = vim.api.nvim_buf_get_lines(buf, 5, 6, false)[1]
  local _, byte = h.pos({ line }, '/book/row', 1)
  local res = client:request_sync('textDocument/definition', {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = 5, character = vim.str_utfindex(line, 'utf-16', byte) },
  }, 1000, buf)
  h.eq(1, #res.result)
  h.eq(vim.uri_from_fname(h.path 'web/grails-app/views/book/_row.gsp'), res.result[1].uri)
  client:stop(true)
end

return T
