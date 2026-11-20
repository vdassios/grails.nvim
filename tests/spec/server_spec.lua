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

function T.no_document_text_is_sent()
  local buf = h.edit 'web/grails-app/views/book/show.gsp'
  local sent = {}
  local id = assert(vim.lsp.start({
    name = 'grails-sync',
    cmd = function(dispatchers)
      local rpc = require('grails.server').start(dispatchers)
      local notify = rpc.notify
      rpc.notify = function(method, params)
        sent[#sent + 1] = method
        return notify(method, params)
      end
      return rpc
    end,
    root_dir = h.app,
  }, { bufnr = buf }))
  local client = assert(vim.lsp.get_client_by_id(id))
  vim.wait(2000, function()
    return client.initialized
  end)
  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '<%-- edited --%>' })
  vim.wait(200)
  client:stop(true)
  vim.cmd.edit { bang = true }
  -- The server reads buffers itself (util.read): copying the text on each keystroke would be for nothing.
  h.eq({ 'initialized' }, sent)
end

function T.positions_are_byte_columns()
  local buf = h.edit 'web/grails-app/views/book/show.gsp'
  -- "Bücher – " sits before the tag: 12 bytes, 9 characters.
  local line = vim.api.nvim_buf_get_lines(buf, 5, 6, false)[1]
  local _, byte = h.pos({ line }, '/book/row', 1)
  local res = h.client(buf):request_sync('textDocument/definition', {
    textDocument = { uri = vim.uri_from_bufnr(buf) },
    position = { line = 5, character = byte },
  }, 1000, buf)
  h.eq(1, #res.result)
  h.eq(vim.uri_from_fname(h.path 'web/grails-app/views/book/_row.gsp'), res.result[1].uri)
end

return T
