-- In-process language server. Neovim runs it through a function `cmd`
-- (`lsp/grails.lua`): `start` receives the client's dispatchers and returns the
-- RPC surface the client talks to.
local M = {}

--- @class grails.State
--- @field encoding 'utf-8'|'utf-16'

--- @type table<string, fun(state: grails.State, params: any): any>
local requests = {}

function requests.initialize(state, params)
  local offered = vim.tbl_get(params or {}, 'capabilities', 'general', 'positionEncodings') or {}
  state.encoding = vim.list_contains(offered, 'utf-8') and 'utf-8' or 'utf-16'
  return {
    capabilities = {
      positionEncoding = state.encoding,
      textDocumentSync = { openClose = true, change = 1, save = true },
      definitionProvider = true,
    },
    serverInfo = { name = 'grails.nvim' },
  }
end

function requests.shutdown()
  return vim.NIL
end

requests['textDocument/definition'] = function(state, params)
  return require('grails.features.definition').definition(params, state.encoding)
end

--- @type table<string, fun(state: grails.State, params: any)>
local notifications = {
  ['textDocument/didSave'] = function(_, params)
    local path = vim.uri_to_fname(params.textDocument.uri)
    if path:find('/grails-app/', 1, true) then
      require('grails.project').invalidate(path)
    end
  end,
}

--- @param dispatchers vim.lsp.rpc.Dispatchers
--- @return vim.lsp.rpc.PublicClient
function M.start(dispatchers)
  --- @type grails.State
  local state = { encoding = 'utf-16' }
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
          local ok, result = xpcall(handler, debug.traceback, state, params)
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
    notify = function(method, params)
      if method == 'exit' then
        close()
      elseif notifications[method] then
        local ok, err = xpcall(notifications[method], debug.traceback, state, params)
        if not ok then
          vim.notify('grails.nvim: ' .. err, vim.log.levels.ERROR)
        end
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
