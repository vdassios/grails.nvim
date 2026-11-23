-- In-process language server. Neovim runs it through a function `cmd`
-- (`lsp/grails.lua`): `start` receives the client's dispatchers and returns the
-- RPC surface the client talks to.
local M = {}

--- @type table<string, fun(params: any): any>
local requests = {}

function requests.initialize()
  return {
    capabilities = {
      -- Byte columns, as Neovim and tree-sitter count. Neovim offers UTF-8 and keeps one encoding per client, so
      -- this server and grails_ls (UTF-16) attach to the same buffer without converting between them.
      positionEncoding = 'utf-8',
      -- No textDocumentSync: a request reads the buffer itself (util.read), so Neovim sends no document text.
      definitionProvider = true,
    },
    serverInfo = { name = 'grails.nvim' },
  }
end

function requests.shutdown()
  return vim.NIL
end

requests['textDocument/definition'] = function(params)
  -- grails_ls answers the same references once its project has been ready: two answers would make every jump a choice
  local buf = require('grails.util').find_buf(vim.uri_to_fname(params.textDocument.uri))
  if buf and require('grails.ls').ready(buf) then
    return {}
  end
  return require('grails.features.definition').definition(params)
end

--- @param dispatchers vim.lsp.rpc.Dispatchers
--- @return vim.lsp.rpc.PublicClient
function M.start(dispatchers)
  local closing = false
  local last_id = 0

  local function close()
    if not closing then
      closing = true
      dispatchers.on_exit(0, 0)
    end
  end

  return {
    request = function(method, params, callback, notify_reply_callback)
      if closing then
        return false
      end
      last_id = last_id + 1
      local id = last_id
      vim.schedule(function()
        local handler = requests[method]
        if not handler then
          callback { code = -32601, message = 'grails.nvim: method not found: ' .. method }
        else
          local ok, result = xpcall(handler, debug.traceback, params)
          if ok then
            callback(nil, result)
          else
            callback { code = -32603, message = result }
          end
        end
        if notify_reply_callback then
          notify_reply_callback(id)
        end
      end)
      return true, id
    end,
    notify = function(method)
      if method == 'exit' then
        close()
      end
      return true
    end,
    is_closing = function()
      return closing
    end,
    terminate = close,
  }
end

return M
