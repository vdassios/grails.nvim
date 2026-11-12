local h = require 'helpers'

local T = {}

function T.initialize_handshake()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  local client = h.client(buf)
  h.eq('grails.nvim', client.server_info.name)
  h.eq('utf-8', client.offset_encoding)
  h.eq(h.app, client.root_dir)
end

function T.unknown_method_errors()
  local buf = h.edit 'web/grails-app/views/book/list.gsp'
  local res = h.client(buf):request_sync('grails/nothing', {}, 1000, buf)
  h.eq(-32601, res.err.code)
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

return T
